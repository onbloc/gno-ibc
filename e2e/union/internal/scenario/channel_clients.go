package scenario

import (
	"context"
	"encoding/json"
	"slices"
	"strconv"
	"strings"

	"github.com/onbloc/gno-ibc/e2e/union/internal/state"
	"github.com/onbloc/gno-ibc/e2e/union/internal/voyager"
)

func (r *Runner) establishUnderlyingClients(ctx context.Context) error {
	clients := []struct {
		target       *int64
		chain        string
		counterparty string
		clientType   string
		ibcInterface string
		reserved     int64
	}{
		{&r.current.Clients.GnoUnion, r.cfg.GnoChainID, r.cfg.UnionChainID, "cometbls", "ibc-gno", 0},
		{&r.current.Clients.UnionGno, r.cfg.UnionChainID, r.cfg.GnoChainID, "gno", "ibc-cosmwasm", 0},
		{&r.current.Clients.UnionEVM, r.cfg.UnionChainID, r.cfg.EVMChainID, "trusted/evm/mpt", "ibc-cosmwasm", 0},
		{&r.current.Clients.EVMUnion, r.cfg.EVMChainID, r.cfg.UnionChainID, "cometbls", "ibc-solidity", r.reservedEVMPlain},
	}
	for _, client := range clients {
		id := client.reserved
		var err error
		if id == 0 {
			id, err = r.voyager.NextClientID(ctx, client.chain)
			if err != nil {
				return err
			}
		}
		*client.target = id
		if err := r.createClient(ctx, voyager.ClientCreation{ClientExpectation: voyager.ClientExpectation{
			Chain: client.chain, Counterparty: client.counterparty,
			ClientType: client.clientType, IBCInterface: client.ibcInterface, ID: id,
		}}); err != nil {
			return err
		}
	}
	return nil
}

func (r *Runner) establishLensClients(ctx context.Context) error {
	height, err := r.voyager.ClientHeight(ctx, r.cfg.UnionChainID, r.current.Clients.UnionEVM)
	if err != nil {
		return err
	}
	lensConfig, _ := json.Marshal(map[string]any{
		"l1_client_id": r.current.Clients.GnoUnion, "host_chain_id": r.cfg.GnoChainID,
		"l2_client_id": r.current.Clients.UnionEVM, "timestamp_offset": 88,
		"state_root_offset": 0, "storage_root_offset": 32,
	})
	r.current.Clients.GnoEVM, err = r.voyager.NextClientID(ctx, r.cfg.GnoChainID)
	if err != nil {
		return err
	}
	if err := r.createClient(ctx, voyager.ClientCreation{
		ClientExpectation: voyager.ClientExpectation{
			Chain: r.cfg.GnoChainID, Counterparty: r.cfg.EVMChainID,
			ClientType: "state-lens/ics23/mpt", IBCInterface: "ibc-gno", ID: r.current.Clients.GnoEVM,
		},
		Config: string(lensConfig), Height: height,
	}); err != nil {
		return err
	}

	height, err = r.voyager.ClientHeight(ctx, r.cfg.UnionChainID, r.current.Clients.UnionGno)
	if err != nil {
		return err
	}

	lensConfig, _ = json.Marshal(map[string]any{
		"l1_client_id": r.current.Clients.EVMUnion, "host_chain_id": r.cfg.EVMChainID,
		"l2_client_id": r.current.Clients.UnionGno, "timestamp_offset": 24,
	})

	r.current.Clients.EVMGno = r.reservedEVMPlain + 1
	if err := r.createClient(ctx, voyager.ClientCreation{
		ClientExpectation: voyager.ClientExpectation{
			Chain: r.cfg.EVMChainID, Counterparty: r.cfg.GnoChainID,
			ClientType: "proof-lens", IBCInterface: "ibc-solidity", ID: r.current.Clients.EVMGno,
		},
		Config: string(lensConfig), Height: height,
	}); err != nil {
		return err
	}

	return nil
}

func (r *Runner) createClient(ctx context.Context, client voyager.ClientCreation) error {
	return r.voyager.CreateClient(
		ctx, client, r.current.FailedWork.Baseline, r.current.FailedWork.Repaired,
		func(id int64) error {
			r.current.FailedWork.Repaired = append(r.current.FailedWork.Repaired, id)
			slices.Sort(r.current.FailedWork.Repaired)
			return state.Save(r.cfg.StateFile, r.current)
		},
	)
}

func (r *Runner) verifyClientRelations(ctx context.Context) error {
	s := &r.current
	checks := []voyager.ClientExpectation{
		{Chain: r.cfg.GnoChainID, Counterparty: r.cfg.UnionChainID, ClientType: "cometbls", IBCInterface: "ibc-gno", ID: s.Clients.GnoUnion},
		{Chain: r.cfg.UnionChainID, Counterparty: r.cfg.GnoChainID, ClientType: "gno", IBCInterface: "ibc-cosmwasm", ID: s.Clients.UnionGno},
		{Chain: r.cfg.UnionChainID, Counterparty: r.cfg.EVMChainID, ClientType: "trusted/evm/mpt", IBCInterface: "ibc-cosmwasm", ID: s.Clients.UnionEVM},
		{Chain: r.cfg.EVMChainID, Counterparty: r.cfg.UnionChainID, ClientType: "cometbls", IBCInterface: "ibc-solidity", ID: s.Clients.EVMUnion},
		{Chain: r.cfg.GnoChainID, Counterparty: r.cfg.EVMChainID, ClientType: "state-lens/ics23/mpt", IBCInterface: "ibc-gno", ID: s.Clients.GnoEVM},
		{Chain: r.cfg.EVMChainID, Counterparty: r.cfg.GnoChainID, ClientType: "proof-lens", IBCInterface: "ibc-solidity", ID: s.Clients.EVMGno},
	}
	for _, check := range checks {
		if err := r.voyager.VerifyClient(ctx, check); err != nil {
			return err
		}
	}
	if err := r.voyager.VerifyLens(ctx, voyager.LensExpectation{
		Chain: r.cfg.GnoChainID, L2Chain: r.cfg.EVMChainID,
		ID: s.Clients.GnoEVM, L1: s.Clients.GnoUnion, L2: s.Clients.UnionEVM,
	}); err != nil {
		return err
	}
	return r.voyager.VerifyLens(ctx, voyager.LensExpectation{
		Chain: r.cfg.EVMChainID, L2Chain: r.cfg.GnoChainID,
		ID: s.Clients.EVMGno, L1: s.Clients.EVMUnion, L2: s.Clients.UnionGno,
	})
}

func joinIDs(ids []int64) string {
	values := make([]string, len(ids))
	for i, id := range ids {
		values[i] = strconv.FormatInt(id, 10)
	}
	return strings.Join(values, ",")
}
