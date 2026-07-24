package scenario

import (
	"context"
	"errors"
	"path/filepath"
	"strings"
	"testing"

	"github.com/onbloc/gno-ibc/e2e/union/internal/config"
	"github.com/onbloc/gno-ibc/e2e/union/internal/gno"
	"github.com/onbloc/gno-ibc/e2e/union/internal/process"
	"github.com/onbloc/gno-ibc/e2e/union/internal/state"
)

func TestInvalidResumeStateRunsNoCommands(t *testing.T) {
	cfg := testConfig(t)
	if err := state.PrepareArtifacts(
		filepath.Dir(filepath.Dir(cfg.ScriptDir)),
		cfg.ScriptDir,
		cfg.ArtifactDir,
		cfg.StateFile,
	); err != nil {
		t.Fatal(err)
	}
	if err := state.Save(cfg.StateFile, state.State{Phase: state.PhaseComplete}); err != nil {
		t.Fatal(err)
	}
	recorder := new(recordingExecutor)
	if _, err := newRunner(cfg, recorder, Options{Apply: true, Resume: true}); err == nil {
		t.Fatal("invalid resume state unexpectedly accepted")
	}
	if len(recorder.commands) != 0 {
		t.Fatalf("commands = %#v, want none", recorder.commands)
	}
}

func TestIncompletePacketResumeRunsNoCommands(t *testing.T) {
	cfg := testConfig(t)
	if err := state.PrepareArtifacts(
		filepath.Dir(filepath.Dir(cfg.ScriptDir)),
		cfg.ScriptDir,
		cfg.ArtifactDir,
		cfg.StateFile,
	); err != nil {
		t.Fatal(err)
	}
	saved := completedState(cfg, 7)
	saved.Phase = state.Phase("packet-complete")
	if err := state.Save(cfg.StateFile, saved); err != nil {
		t.Fatal(err)
	}
	recorder := new(recordingExecutor)
	if _, err := newRunner(cfg, recorder, Options{Apply: true, Resume: true}); err == nil {
		t.Fatal("incomplete packet state unexpectedly accepted")
	}
	if len(recorder.commands) != 0 {
		t.Fatalf("commands = %#v, want none", recorder.commands)
	}
}

func TestUnsupportedResumePhaseRunsNoCommands(t *testing.T) {
	cfg := testConfig(t)
	if err := state.PrepareArtifacts(
		filepath.Dir(filepath.Dir(cfg.ScriptDir)),
		cfg.ScriptDir,
		cfg.ArtifactDir,
		cfg.StateFile,
	); err != nil {
		t.Fatal(err)
	}
	saved := completedState(cfg, 7)
	saved.Phase = state.Phase("bootstrap-in-progress")
	saved.Channels = nil
	if err := state.Save(cfg.StateFile, saved); err != nil {
		t.Fatal(err)
	}
	recorder := new(recordingExecutor)
	if _, err := newRunner(cfg, recorder, Options{Apply: true, Resume: true}); err == nil {
		t.Fatal("unsupported resume phase unexpectedly accepted")
	}
	if len(recorder.commands) != 0 {
		t.Fatalf("commands = %#v, want none", recorder.commands)
	}
}

func TestDryPreflightUsesOnlyReadOnlyGitChecks(t *testing.T) {
	cfg := testConfig(t)
	recorder := &recordingExecutor{results: []process.Result{
		{Stdout: []byte(config.VoyagerRevision + "\n")},
		{},
	}}
	runner, err := newRunner(cfg, recorder, Options{})
	if err != nil {
		t.Fatal(err)
	}
	if err := runner.Run(context.Background()); err != nil {
		t.Fatal(err)
	}
	if len(recorder.commands) != 2 {
		t.Fatalf("commands = %#v, want two git checks", recorder.commands)
	}
	for _, command := range recorder.commands {
		if command.Name != "git" {
			t.Fatalf("command = %#v, want git", command)
		}
	}
}

func TestPacketPreflightRejectsMissingCommandsBeforeDocker(t *testing.T) {
	cfg := testConfig(t)
	t.Setenv("PATH", t.TempDir())
	recorder := &recordingExecutor{results: []process.Result{
		{Stdout: []byte(config.VoyagerRevision + "\n")},
		{},
	}}
	runner, err := newRunner(cfg, recorder, Options{Apply: true, ERC20ToGno: true})
	if err != nil {
		t.Fatal(err)
	}
	err = runner.Run(context.Background())
	if err == nil || !strings.Contains(err.Error(), "missing required packet command") {
		t.Fatalf("error = %v", err)
	}
	if len(recorder.commands) != 2 {
		t.Fatalf("commands = %#v, want only git preflight", recorder.commands)
	}
}

func TestGnoToEVMRequiresDevSenderBeforeCommands(t *testing.T) {
	cfg := testConfig(t)
	recorder := new(recordingExecutor)
	_, err := newRunner(
		cfg, recorder,
		Options{Apply: true, ERC20ToGno: true, GnoToEVM: true},
	)
	if err == nil || !strings.Contains(err.Error(), "dev Gno sender") {
		t.Fatalf("error = %v, want dev sender", err)
	}
	if len(recorder.commands) != 0 {
		t.Fatalf("commands = %#v, want none", recorder.commands)
	}
	cfg.GnoRecipient = gno.DevSenderAddress
	if _, err := newRunner(
		cfg, recorder,
		Options{Apply: true, ERC20ToGno: true, GnoToEVM: true},
	); err != nil {
		t.Fatal(err)
	}
}

type recordingExecutor struct {
	commands []process.Command
	results  []process.Result
}

func (r *recordingExecutor) Run(_ context.Context, command process.Command) (process.Result, error) {
	r.commands = append(r.commands, command)
	if len(r.results) == 0 {
		return process.Result{}, errors.New("unexpected command")
	}
	result := r.results[0]
	r.results = r.results[1:]
	return result, nil
}

func testConfig(t *testing.T) config.Config {
	t.Helper()
	scriptDir, err := filepath.Abs(filepath.Join("..", ".."))
	if err != nil {
		t.Fatal(err)
	}
	artifactDir := filepath.Join(t.TempDir(), "artifacts")
	return config.Config{
		ScriptDir:              scriptDir,
		UnionChainID:           "union-devnet-1",
		EVMChainID:             "17000",
		GnoChainID:             "dev.ibc",
		UnionVoyagerDir:        t.TempDir(),
		UnionVoyagerRevision:   config.VoyagerRevision,
		EVMIBCHandler:          "0x1111111111111111111111111111111111111111",
		EVMMulticall:           "0x2222222222222222222222222222222222222222",
		EVMCometBLSClientImpl:  "0x3333333333333333333333333333333333333333",
		EVMProofLensClientImpl: "0x4444444444444444444444444444444444444444",
		GnoZKGMPort:            "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm",
		EVMZKGMContract:        "0x5555555555555555555555555555555555555555",
		EVMTestERC20:           "0x6666666666666666666666666666666666666666",
		GnoRecipient:           "g1" + strings.Repeat("a", 38),
		EVMTestAmount:          "1000000000000",
		ArtifactDir:            artifactDir,
		StateFile:              filepath.Join(artifactDir, "state.json"),
	}
}
