package scenario

import (
	"context"
	"encoding/hex"
	"errors"
	"os"
	"path/filepath"
	"slices"
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
	cfg.VoyagerImage = "union-voyager-e2e:" + config.VoyagerRevision[:12]
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
	ctx, cancel := context.WithCancel(context.Background())
	recorder := &resumeExecutor{cancel: cancel}
	runner, err := newRunner(cfg, recorder, Options{Apply: true, Resume: true})
	if err != nil {
		t.Fatal(err)
	}
	if err := os.Remove(cfg.StateFile); err != nil {
		t.Fatal(err)
	}
	if err := runner.Run(ctx); err != nil {
		t.Fatal(err)
	}
	if recorder.stopContextErr != nil {
		t.Fatalf("cleanup inherited scenario cancellation: %v", recorder.stopContextErr)
	}
	for _, command := range recorder.commands {
		if !readOnlyResumeCommand(command) {
			t.Fatalf("completed resume issued a non-read-only command: %s %s", command.Name, strings.Join(command.Args, " "))
		}
	}
}

func TestConnectionSubmittingResumeDoesNotRebroadcastWhenSlotsAreMissing(t *testing.T) {
	cfg := resumableState(t, state.PhaseConnectionSubmitting)
	recorder := &resumeExecutor{missingKind: "connection"}
	runner, err := newRunner(cfg, recorder, Options{Apply: true, Resume: true})
	if err != nil {
		t.Fatal(err)
	}
	err = runner.Run(context.Background())
	if err == nil || !strings.Contains(err.Error(), "connection submission is ambiguous") {
		t.Fatalf("error = %v", err)
	}
	if recorder.broadcasts != 0 {
		t.Fatalf("broadcasts = %d, want zero", recorder.broadcasts)
	}
}

func TestChannelSubmittingResumeDoesNotRebroadcastWhenSlotsAreMissing(t *testing.T) {
	cfg := resumableState(t, state.PhaseChannelSubmitting)
	recorder := &resumeExecutor{missingKind: "channel"}
	runner, err := newRunner(cfg, recorder, Options{Apply: true, Resume: true})
	if err != nil {
		t.Fatal(err)
	}
	err = runner.Run(context.Background())
	if err == nil || !strings.Contains(err.Error(), "channel submission is ambiguous") {
		t.Fatalf("error = %v", err)
	}
	if recorder.broadcasts != 0 {
		t.Fatalf("broadcasts = %d, want zero", recorder.broadcasts)
	}
}

func TestSubmittingResumeAdvancesOnlyFromMatchingExternalState(t *testing.T) {
	tests := []struct {
		name      string
		phase     state.Phase
		wantPhase state.Phase
	}{
		{"connection", state.PhaseConnectionSubmitting, state.PhaseConnectionSubmitted},
		{"channel", state.PhaseChannelSubmitting, state.PhaseComplete},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			cfg := resumableState(t, tc.phase)
			recorder := new(resumeExecutor)
			runner, err := newRunner(cfg, recorder, Options{Resume: true})
			if err != nil {
				t.Fatal(err)
			}
			err = runner.Run(context.Background())
			if tc.name == "connection" {
				if err == nil || !strings.Contains(err.Error(), "has no channel IDs") {
					t.Fatalf("error = %v", err)
				}
			} else if err != nil {
				t.Fatal(err)
			}
			saved, err := state.Load(cfg.StateFile)
			if err != nil {
				t.Fatal(err)
			}
			if saved.Phase != tc.wantPhase {
				t.Fatalf("phase = %s, want %s", saved.Phase, tc.wantPhase)
			}
			if recorder.broadcasts != 0 {
				t.Fatalf("broadcasts = %d, want zero", recorder.broadcasts)
			}
		})
	}
}

func resumableState(t *testing.T, phase state.Phase) config.Config {
	t.Helper()
	cfg := testConfig(t)
	cfg.VoyagerImage = "union-voyager-e2e:" + config.VoyagerRevision[:12]
	cfg.VoyagerRustLog = "warn"
	cfg.CommandTimeout = time.Second
	cfg.ScenarioTimeout = time.Second
	cfg.PollInterval = 0
	cfg.VoyagerStopTimeout = time.Second
	cfg.CleanupTimeout = 2 * time.Second
	if err := state.PrepareArtifacts(
		filepath.Dir(filepath.Dir(cfg.ScriptDir)), cfg.ScriptDir, cfg.ArtifactDir, cfg.StateFile,
	); err != nil {
		t.Fatal(err)
	}
	saved := completedState(cfg, 7)
	saved.Phase = phase
	saved.FailedWork.Final = nil
	if phase == state.PhaseConnectionSubmitting {
		saved.Channels = nil
	}
	if err := state.Save(cfg.StateFile, saved); err != nil {
		t.Fatal(err)
	}
	return cfg
}

func completedState(cfg config.Config, final int64) state.State {
	return state.State{
		Phase: state.PhaseComplete, VoyagerRevision: cfg.UnionVoyagerRevision,
		Chains:      state.Chains{Union: cfg.UnionChainID, EVM: cfg.EVMChainID, Gno: cfg.GnoChainID},
		EVMTopology: state.EVMTopology{ChainID: cfg.EVMChainID, AddressFingerprint: cfg.TopologyFingerprint()},
		Ports:       state.Ports{Gno: cfg.GnoZKGMPort, EVM: cfg.EVMZKGMContract},
		Version:     config.ChannelVersion,
		FailedWork:  state.FailedWork{Baseline: final, Final: &final},
		Clients:     state.Clients{GnoUnion: 1, UnionGno: 2, UnionEVM: 3, EVMUnion: 4, GnoEVM: 5, EVMGno: 6},
		Allowlists:  state.Allowlists{Plain: "4", ProofLens: "6"},
		Connections: &state.HandshakeIDs{Gno: 11, EVM: 12},
		Channels:    &state.HandshakeIDs{Gno: 21, EVM: 22},
	}
}

func readOnlyResumeCommand(command process.Command) bool {
	if command.Name == "git" {
		return slices.Contains(command.Args, "rev-parse") || slices.Contains(command.Args, "status")
	}
	if command.Name != "docker" || len(command.Args) == 0 {
		return false
	}
	switch command.Args[0] {
	case "build", "image", "ps", "run", "inspect", "stop", "rm":
		return true
	case "exec":
		if len(command.Args) < 8 {
			return false
		}
		operation := command.Args[7:]
		return slices.Equal(operation, []string{"rpc", "info"}) ||
			(len(operation) == 4 && operation[0] == "rpc" &&
				(operation[1] == "client-info" || operation[1] == "client-meta" || operation[1] == "ibc-state")) ||
			(len(operation) == 5 && operation[0] == "rpc" && operation[1] == "client-state" &&
				operation[4] == "--decode") ||
			slices.Equal(operation, []string{"queue", "query-failed", "--per-page", "100"})
	}
	return false
}

type resumeExecutor struct {
	dockerTestRuntime
	commands    []process.Command
	cancel      context.CancelFunc
	missingKind string
	broadcasts  int
}

func (r *resumeExecutor) Run(ctx context.Context, command process.Command) (process.Result, error) {
	r.commands = append(r.commands, command)
	return r.dockerTestRuntime.run(ctx, command, r.voyagerResponse)
}

func (r *resumeExecutor) voyagerResponse(args []string) (process.Result, error) {
	joined := strings.Join(args, " ")
	switch {
	case joined == "rpc info":
		return process.Result{Stdout: []byte("{}")}, nil
	case strings.HasPrefix(joined, "q e "):
		r.broadcasts++
		return process.Result{}, nil
	case strings.HasPrefix(joined, "queue query-failed"):
		if r.cancel != nil {
			r.cancel()
		}
		return process.Result{Stdout: []byte(`[{"id":7}]`)}, nil
	case strings.HasPrefix(joined, "rpc client-info "):
		chain, id := trailingChainID(args)
		clientType, ibc := expectedClient(chain, id)
		return process.Result{Stdout: []byte(`{"client_type":"` + clientType + `","ibc_interface":"` + ibc + `"}`)}, nil
	case strings.HasPrefix(joined, "rpc client-meta "):
		chain, id := trailingChainID(args)
		return process.Result{Stdout: []byte(`{"counterparty_chain_id":"` + counterparty(chain, id) + `","counterparty_height":"1"}`)}, nil
	case strings.HasPrefix(joined, "rpc client-state "):
		chain, id := trailingChainID(args[:len(args)-1])
		if chain == "dev.ibc" && id == 5 {
			return process.Result{Stdout: []byte(`{"state":{"l1_client_id":1,"l2_client_id":3,"l2_chain_id":"17000"}}`)}, nil
		}
		return process.Result{Stdout: []byte(`{"state":{"l1_client_id":4,"l2_client_id":2,"l2_chain_id":"dev.ibc"}}`)}, nil
	case strings.Contains(joined, `"connection"`):
		if r.missingKind == "connection" {
			return process.Result{Stdout: []byte(`{"state":null}`)}, nil
		}
		chain := args[len(args)-2]
		if chain == "dev.ibc" {
			return process.Result{Stdout: []byte(`{"state":{"state":"OPEN","client_id":5,"counterparty_client_id":6,"counterparty_connection_id":12}}`)}, nil
		}
		return process.Result{Stdout: []byte(`{"state":{"state":"OPEN","client_id":6,"counterparty_client_id":5,"counterparty_connection_id":11}}`)}, nil
	case strings.Contains(joined, `"channel"`):
		if r.missingKind == "channel" {
			return process.Result{Stdout: []byte(`{"state":null}`)}, nil
		}
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

func argumentAfter(args []string, flag string) string {
	for i := range len(args) - 1 {
		if args[i] == flag {
			return args[i+1]
		}
	}
	return ""
}
