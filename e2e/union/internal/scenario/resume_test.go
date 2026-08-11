package scenario

import (
	"context"
	"encoding/hex"
	"errors"
	"path/filepath"
	"strconv"
	"strings"
	"testing"
	"time"

	"github.com/onbloc/gno-ibc/e2e/union/internal/config"
	"github.com/onbloc/gno-ibc/e2e/union/internal/process"
	"github.com/onbloc/gno-ibc/e2e/union/internal/state"
)

func TestCompletedResumeUsesLoadedStateAndBroadcastsNothing(t *testing.T) {
	cfg := testConfig(t)
	cfg.VoyagerImage = "union-voyager-e2e:" + testVoyagerRevision[:12]
	cfg.VoyagerRustLog = "warn"
	cfg.CommandTimeout = time.Second
	cfg.ScenarioTimeout = time.Second
	cfg.VoyagerStopTimeout = time.Second
	cfg.CleanupTimeout = 2 * time.Second
	if err := state.PrepareArtifacts(
		filepath.Dir(filepath.Dir(cfg.ScriptDir)), cfg.ScriptDir, cfg.ArtifactDir, cfg.StateFile,
	); err != nil {
		t.Fatal(err)
	}
	final := int64(7)
	saved := completedState(cfg, final)
	if err := state.Save(cfg.StateFile, saved); err != nil {
		t.Fatal(err)
	}
	recorder := &resumeExecutor{}
	runner, err := newRunner(cfg, recorder, Options{Apply: true, Resume: true})
	if err != nil {
		t.Fatal(err)
	}
	if err := runner.Run(context.Background()); err != nil {
		t.Fatal(err)
	}
	if recorder.writes != 0 {
		t.Fatalf("completed resume issued %d writes", recorder.writes)
	}
}

func completedState(cfg config.Config, final int64) state.State {
	return state.State{
		VoyagerRevision: cfg.UnionVoyagerRevision,
		Chains:          state.Chains{Union: cfg.UnionChainID, EVM: cfg.EVMChainID, Gno: cfg.GnoChainID},
		EVMTopology:     expectedState(cfg).EVMTopology,
		Ports:           state.Ports{Gno: cfg.GnoZKGMPort, EVM: cfg.EVMZKGMContract},
		Version:         config.ChannelVersion,
		FailedWork:      state.FailedWork{Baseline: final, Final: &final},
		Clients:         state.Clients{GnoUnion: 1, UnionGno: 2, UnionEVM: 3, EVMUnion: 4, GnoEVM: 5, EVMGno: 6},
		Allowlists:      state.Allowlists{Plain: "4", ProofLens: "6"},
		Connections:     &state.HandshakeIDs{Gno: 11, EVM: 12},
		Channels:        &state.HandshakeIDs{Gno: 21, EVM: 22},
	}
}

type resumeExecutor struct {
	dockerTestRuntime
	writes int
}

func (r *resumeExecutor) Run(ctx context.Context, command process.Command) (process.Result, error) {
	for _, arg := range command.Args {
		switch arg {
		case "index", "msg", "q":
			r.writes++
		}
	}
	return r.dockerTestRuntime.run(ctx, command, r.voyagerResponse)
}

func (r *resumeExecutor) voyagerResponse(args []string) (process.Result, error) {
	joined := strings.Join(args, " ")
	switch {
	case joined == "rpc info":
		return process.Result{Stdout: []byte("{}")}, nil
	case strings.HasPrefix(joined, "queue query-failed"):
		return process.Result{Stdout: []byte(`[{"id":7}]`)}, nil
	case strings.HasPrefix(joined, "rpc client-info "):
		chain, id := trailingChainID(args)
		clientType, ibc := expectedClient(chain, id)
		return process.Result{Stdout: []byte(`{"client_type":"` + clientType + `","ibc_interface":"` + ibc + `"}`)}, nil
	case strings.HasPrefix(joined, "rpc client-meta "):
		chain, id := trailingChainID(args)
		return process.Result{Stdout: []byte(`{"counterparty_chain_id":"` + counterparty(chain, id) + `","counterparty_height":"1"}`)}, nil
	case strings.HasPrefix(joined, "rpc query ") && strings.Contains(joined, `"client_status"`):
		return process.Result{Stdout: []byte(`"active"`)}, nil
	case strings.HasPrefix(joined, "rpc client-state "):
		chain, id := trailingChainID(args[:len(args)-1])
		if chain == "dev.ibc" && id == 5 {
			return process.Result{Stdout: []byte(`{"state":{"l1_client_id":1,"l2_client_id":3,"l2_chain_id":"17000"}}`)}, nil
		}
		return process.Result{Stdout: []byte(`{"state":{"l1_client_id":4,"l2_client_id":2,"l2_chain_id":"dev.ibc"}}`)}, nil
	case strings.Contains(joined, `"connection"`):
		chain := args[len(args)-2]
		if chain == "dev.ibc" {
			return process.Result{Stdout: []byte(`{"state":{"state":"OPEN","client_id":5,"counterparty_client_id":6,"counterparty_connection_id":12}}`)}, nil
		}
		return process.Result{Stdout: []byte(`{"state":{"state":"OPEN","client_id":6,"counterparty_client_id":5,"counterparty_connection_id":11}}`)}, nil
	case strings.Contains(joined, `"channel"`):
		chain := args[len(args)-2]
		if chain == "dev.ibc" {
			return process.Result{Stdout: []byte(`{"state":{"state":"OPEN","connection_id":11,"counterparty_channel_id":22,"counterparty_port_id":"0x5555555555555555555555555555555555555555","version":"ucs03-zkgm-0"}}`)}, nil
		}
		port := "0x" + hex.EncodeToString([]byte("gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm"))
		return process.Result{Stdout: []byte(`{"state":{"state":"OPEN","connection_id":12,"counterparty_channel_id":21,"counterparty_port_id":"` + port + `","version":"ucs03-zkgm-0"}}`)}, nil
	default:
		return process.Result{}, errors.New("unexpected Voyager command")
	}
}

func trailingChainID(args []string) (string, int64) {
	id, _ := strconv.ParseInt(args[len(args)-1], 10, 64)
	return args[len(args)-2], id
}

func expectedClient(chain string, id int64) (string, string) {
	switch {
	case chain == "dev.ibc" && id == 1:
		return "cometbls", "ibc-gno"
	case chain == "union-devnet-1" && id == 2:
		return "gno", "ibc-cosmwasm"
	case chain == "union-devnet-1" && id == 3:
		return "trusted/evm/mpt", "ibc-cosmwasm"
	case chain == "17000" && id == 4:
		return "cometbls", "ibc-solidity"
	case chain == "dev.ibc" && id == 5:
		return "state-lens/ics23/mpt", "ibc-gno"
	default:
		return "proof-lens", "ibc-solidity"
	}
}

func counterparty(chain string, id int64) string {
	switch {
	case chain == "dev.ibc" && id == 1:
		return "union-devnet-1"
	case chain == "dev.ibc":
		return "17000"
	case chain == "union-devnet-1" && id == 2:
		return "dev.ibc"
	case chain == "union-devnet-1":
		return "17000"
	case id == 4:
		return "union-devnet-1"
	default:
		return "dev.ibc"
	}
}
