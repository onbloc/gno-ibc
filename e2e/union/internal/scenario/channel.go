package scenario

import (
	"context"
	"encoding/hex"
	"fmt"
	"strings"

	"github.com/onbloc/gno-ibc/e2e/union/internal/config"
	"github.com/onbloc/gno-ibc/e2e/union/internal/state"
	"github.com/onbloc/gno-ibc/e2e/union/internal/voyager"
)

// runChannelScenario establishes and verifies S1. Completed stages verify
// the saved topology without repeating writes.
func (r *Runner) runChannelScenario(ctx context.Context) error {
	if r.saved != nil && r.saved.Phase == state.PhaseComplete {
		if err := r.verifyClientRelations(ctx); err != nil {
			return err
		}
		if err := r.verifyOpenHandshakes(ctx); err != nil {
			return err
		}
		return r.verifyNoNewFailedWork(ctx)
	}
	if err := r.indexUnionAndGno(ctx); err != nil {
		return err
	}
	if err := r.establishUnderlyingClients(ctx); err != nil {
		return err
	}
	if err := r.establishLensClients(ctx); err != nil {
		return err
	}
	if err := r.allowlistAndIndexEVM(ctx); err != nil {
		return err
	}
	if err := r.establishConnection(ctx); err != nil {
		return err
	}
	if err := r.establishChannel(ctx); err != nil {
		return err
	}
	if err := r.verifyClientRelations(ctx); err != nil {
		return err
	}
	if err := r.verifyOpenHandshakes(ctx); err != nil {
		return err
	}
	if err := r.verifyNoNewFailedWork(ctx); err != nil {
		return err
	}
	return r.saveChannelEvidence(ctx)
}

func (r *Runner) indexUnionAndGno(context.Context) error {
	return fmt.Errorf("live channel scenario is not implemented yet")
}

func (r *Runner) establishUnderlyingClients(context.Context) error { return nil }
func (r *Runner) establishLensClients(context.Context) error       { return nil }
func (r *Runner) allowlistAndIndexEVM(context.Context) error       { return nil }
func (r *Runner) establishConnection(context.Context) error        { return nil }
func (r *Runner) establishChannel(context.Context) error           { return nil }
func (r *Runner) verifyClientRelations(ctx context.Context) error {
	if r.saved == nil {
		return fmt.Errorf("client verification requires resume state")
	}
	s := r.saved
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

func (r *Runner) verifyOpenHandshakes(ctx context.Context) error {
	if r.saved == nil || r.saved.Connections == nil || r.saved.Channels == nil {
		return fmt.Errorf("handshake verification requires complete resume state")
	}
	s := r.saved
	for _, check := range []voyager.ConnectionExpectation{
		{Chain: r.cfg.GnoChainID, ID: s.Connections.Gno, Client: s.Clients.GnoEVM, CounterpartyClient: s.Clients.EVMGno, CounterpartyID: s.Connections.EVM},
		{Chain: r.cfg.EVMChainID, ID: s.Connections.EVM, Client: s.Clients.EVMGno, CounterpartyClient: s.Clients.GnoEVM, CounterpartyID: s.Connections.Gno},
	} {
		if err := r.voyager.VerifyConnection(ctx, check); err != nil {
			return err
		}
	}
	gnoPort := "0x" + hex.EncodeToString([]byte(r.cfg.GnoZKGMPort))
	for _, check := range []voyager.ChannelExpectation{
		{Chain: r.cfg.GnoChainID, ID: s.Channels.Gno, Connection: s.Connections.Gno, CounterpartyID: s.Channels.EVM, CounterpartyPort: strings.ToLower(r.cfg.EVMZKGMContract), Version: config.ChannelVersion},
		{Chain: r.cfg.EVMChainID, ID: s.Channels.EVM, Connection: s.Connections.EVM, CounterpartyID: s.Channels.Gno, CounterpartyPort: gnoPort, Version: config.ChannelVersion},
	} {
		if err := r.voyager.VerifyChannel(ctx, check); err != nil {
			return err
		}
	}
	return nil
}

func (r *Runner) verifyNoNewFailedWork(ctx context.Context) error {
	if r.saved == nil || r.saved.FailedWork.Final == nil {
		return fmt.Errorf("failed-work verification requires complete resume state")
	}
	latest, err := r.voyager.FailedWorkID(ctx, *r.saved.FailedWork.Final, r.saved.FailedWork.Repaired)
	if err != nil {
		return err
	}
	if latest != *r.saved.FailedWork.Final {
		return fmt.Errorf("Voyager recorded new failed work after ID %d (latest %d)", *r.saved.FailedWork.Final, latest)
	}
	return nil
}
func (r *Runner) saveChannelEvidence(context.Context) error { return nil }
