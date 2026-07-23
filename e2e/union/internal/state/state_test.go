package state_test

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/onbloc/gno-ibc/e2e/union/internal/state"
)

func TestValidateCompleteState(t *testing.T) {
	saved, expected := completeState()
	if err := saved.Validate(expected); err != nil {
		t.Fatal(err)
	}

	saved.Channels = nil
	if err := saved.Validate(expected); err == nil ||
		!strings.Contains(err.Error(), "channel") {
		t.Fatalf("error = %v, want incomplete channel state", err)
	}
}

func TestSaveBootstrapIsExclusiveAndPrivate(t *testing.T) {
	path := filepath.Join(t.TempDir(), "bootstrap-in-progress.json")
	saved, _ := completeState()
	if err := state.SaveBootstrap(path, saved); err != nil {
		t.Fatal(err)
	}
	if err := state.SaveBootstrap(path, saved); err == nil ||
		!strings.Contains(err.Error(), "already exists") {
		t.Fatalf("error = %v, want exclusive-create failure", err)
	}
	info, err := os.Stat(path)
	if err != nil {
		t.Fatal(err)
	}
	if info.Mode().Perm() != 0o600 {
		t.Fatalf("mode = %o, want 600", info.Mode().Perm())
	}
}

func TestValidateRejectsTerminalFailedWork(t *testing.T) {
	saved, expected := completeState()
	saved.Phase = state.Phase("failed-work")
	if err := saved.Validate(expected); err == nil ||
		!strings.Contains(err.Error(), "terminal") {
		t.Fatalf("error = %v, want terminal failed-work", err)
	}
}

func TestValidateRejectsInconsistentFailedWork(t *testing.T) {
	tests := []struct {
		name   string
		change func(*state.State)
	}{
		{"negative baseline", func(saved *state.State) { saved.FailedWork.Baseline = -1 }},
		{"final ahead of baseline", func(saved *state.State) {
			final := int64(1)
			saved.FailedWork.Final = &final
		}},
		{"repaired at baseline", func(saved *state.State) { saved.FailedWork.Repaired = []int64{0} }},
		{"duplicate repaired", func(saved *state.State) { saved.FailedWork.Repaired = []int64{1, 1} }},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			saved, expected := completeState()
			tc.change(&saved)
			if err := saved.Validate(expected); err == nil {
				t.Fatal("inconsistent failed-work state unexpectedly accepted")
			}
		})
	}
}

func TestValidateRequiresSavedEVMClientsInTheirAllowlists(t *testing.T) {
	tests := []struct {
		name   string
		change func(*state.State)
	}{
		{"plain", func(saved *state.State) { saved.Allowlists.Plain = "1,2,3" }},
		{"Proof Lens", func(saved *state.State) { saved.Allowlists.ProofLens = "6" }},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			saved, expected := completeState()
			tc.change(&saved)
			if err := saved.Validate(expected); err == nil ||
				!strings.Contains(err.Error(), "allowlist") {
				t.Fatalf("error = %v, want role allowlist rejection", err)
			}
		})
	}
}

func TestLoadRejectsTrailingJSON(t *testing.T) {
	path := filepath.Join(t.TempDir(), "state.json")
	if err := os.WriteFile(path, []byte(`{"phase":"complete"} {}`), 0o600); err != nil {
		t.Fatal(err)
	}
	if _, err := state.Load(path); err == nil {
		t.Fatal("trailing JSON unexpectedly accepted")
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

func TestPrepareArtifactsCreatesPrivateOwnedDirectory(t *testing.T) {
	repo := t.TempDir()
	scriptDir := filepath.Join(repo, "e2e", "union")
	artifactDir := filepath.Join(scriptDir, "artifacts")
	if err := os.MkdirAll(scriptDir, 0o700); err != nil {
		t.Fatal(err)
	}
	if err := state.PrepareArtifacts(repo, scriptDir, artifactDir, filepath.Join(artifactDir, "state.json")); err != nil {
		t.Fatal(err)
	}
	info, err := os.Stat(artifactDir)
	if err != nil {
		t.Fatal(err)
	}
	if info.Mode().Perm() != 0o700 {
		t.Fatalf("artifact mode = %o, want 700", info.Mode().Perm())
	}
}

func completeState() (state.State, state.Expected) {
	final := int64(0)
	expected := state.Expected{
		VoyagerRevision:     "9024777562dcaa01613017cd0b958569b85e243e",
		Chains:              state.Chains{Union: "union-devnet-1", EVM: "17000", Gno: "dev.ibc"},
		EVMChainID:          "17000",
		TopologyFingerprint: "53b14ed7e73989ece8823a4cf115bf409ef8a046",
		GnoPort:             "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm",
		EVMPort:             "0x5555555555555555555555555555555555555555",
		Version:             "ucs03-zkgm-0",
	}
	return state.State{
		Phase:           state.PhaseComplete,
		VoyagerRevision: expected.VoyagerRevision,
		Chains:          expected.Chains,
		EVMTopology: state.EVMTopology{
			ChainID:            expected.EVMChainID,
			AddressFingerprint: expected.TopologyFingerprint,
		},
		Ports:      state.Ports{Gno: expected.GnoPort, EVM: expected.EVMPort},
		Version:    expected.Version,
		FailedWork: state.FailedWork{Baseline: 0, Final: &final, Repaired: []int64{1}},
		Clients: state.Clients{
			GnoUnion: 13,
			UnionGno: 14,
			UnionEVM: 15,
			EVMUnion: 4,
			GnoEVM:   14,
			EVMGno:   5,
		},
		Allowlists:  state.Allowlists{Plain: "1,2,3,4", ProofLens: "5"},
		Connections: &state.HandshakeIDs{Gno: 1, EVM: 1},
		Channels:    &state.HandshakeIDs{Gno: 1, EVM: 1},
	}, expected
}
