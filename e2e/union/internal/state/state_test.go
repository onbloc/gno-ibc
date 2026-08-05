package state_test

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/onbloc/gno-ibc/e2e/union/internal/state"
)

func TestTopologyCheckpoint(t *testing.T) {
	saved, expected := completeState()
	if err := saved.Validate(expected); err != nil {
		t.Fatal(err)
	}
	saved.EVMTopology.IBCHandler = strings.ToUpper(saved.EVMTopology.IBCHandler)
	if err := saved.Validate(expected); err != nil {
		t.Fatalf("mixed-case EVM address rejected: %v", err)
	}
	saved.EVMTopology.IBCHandler = "0xffffffffffffffffffffffffffffffffffffffff"
	if err := saved.Validate(expected); err == nil || !strings.Contains(err.Error(), "topology") {
		t.Fatalf("error = %v, want changed EVM topology", err)
	}
	saved.EVMTopology = expected.EVMTopology
	saved.Channels = nil
	if err := saved.Validate(expected); err == nil || !strings.Contains(err.Error(), "channel") {
		t.Fatalf("error = %v, want incomplete channel state", err)
	}
}

func TestSaveWritesPrivateLoadableState(t *testing.T) {
	saved, _ := completeState()
	path := filepath.Join(t.TempDir(), "state.json")
	if err := state.Save(path, saved); err != nil {
		t.Fatal(err)
	}
	info, err := os.Stat(path)
	if err != nil {
		t.Fatal(err)
	}
	if info.Mode().Perm() != 0o600 {
		t.Fatalf("state mode = %o, want 600", info.Mode().Perm())
	}
	if _, err := state.Load(path); err != nil {
		t.Fatal(err)
	}
}

func completeState() (state.State, state.Expected) {
	final := int64(0)
	expected := state.Expected{
		VoyagerRevision: "revision", Chains: state.Chains{Union: "union", EVM: "17000", Gno: "gno"},
		EVMTopology: state.EVMTopology{
			ChainID: "17000", IBCHandler: "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
			Multicall: "0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb", ZKGM: "0xcccccccccccccccccccccccccccccccccccccccc",
			CometBLSClientImpl:  "0xdddddddddddddddddddddddddddddddddddddddd",
			ProofLensClientImpl: "0xeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee",
		},
		GnoPort: "gno-port", EVMPort: "0x5555555555555555555555555555555555555555", Version: "version",
	}
	return state.State{
		VoyagerRevision: expected.VoyagerRevision, Chains: expected.Chains,
		EVMTopology: expected.EVMTopology,
		Ports:       state.Ports{Gno: expected.GnoPort, EVM: expected.EVMPort}, Version: expected.Version,
		FailedWork:  state.FailedWork{Final: &final},
		Clients:     state.Clients{GnoUnion: 1, UnionGno: 2, UnionEVM: 3, EVMUnion: 4, GnoEVM: 5, EVMGno: 6},
		Allowlists:  state.Allowlists{Plain: "4", ProofLens: "6"},
		Connections: &state.HandshakeIDs{Gno: 1, EVM: 1}, Channels: &state.HandshakeIDs{Gno: 1, EVM: 1},
	}, expected
}
