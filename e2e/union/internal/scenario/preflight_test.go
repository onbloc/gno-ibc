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
)

func TestDryPreflightRunsNoCommands(t *testing.T) {
	cfg := testConfig(t)
	recorder := new(recordingExecutor)
	runner, err := newRunner(cfg, recorder, Options{})
	if err != nil {
		t.Fatal(err)
	}
	if err := runner.Run(context.Background()); err != nil {
		t.Fatal(err)
	}
	if len(recorder.commands) != 0 {
		t.Fatalf("commands = %#v, want none", recorder.commands)
	}
}

func TestPacketPreflightRejectsMissingCommandsBeforeDocker(t *testing.T) {
	cfg := testConfig(t)
	t.Setenv("PATH", t.TempDir())
	recorder := new(recordingExecutor)
	runner, err := newRunner(cfg, recorder, Options{Apply: true, ERC20ToGno: true})
	if err != nil {
		t.Fatal(err)
	}
	err = runner.Run(context.Background())
	if err == nil || !strings.Contains(err.Error(), "missing required packet command") {
		t.Fatalf("error = %v", err)
	}
	if len(recorder.commands) != 0 {
		t.Fatalf("commands = %#v, want none", recorder.commands)
	}
}

func TestGnoToEVMRequiresDevSenderBeforeCommands(t *testing.T) {
	cfg := testConfig(t)
	recorder := new(recordingExecutor)
	_, err := newRunner(
		cfg, recorder,
		Options{Apply: true, GnoToEVM: true},
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
		Options{Apply: true, GnoToEVM: true},
	); err != nil {
		t.Fatal(err)
	}
}

func TestDependentScenariosEnableERC20ToGno(t *testing.T) {
	for _, options := range []Options{
		{Apply: true, AmountBoundaries: true},
		{Apply: true, GnoToEVM: true},
	} {
		cfg := testConfig(t)
		cfg.GnoRecipient = gno.DevSenderAddress
		runner, err := newRunner(cfg, new(recordingExecutor), options)
		if err != nil {
			t.Fatal(err)
		}
		if !runner.options.ERC20ToGno {
			t.Fatal("ERC20-to-Gno prerequisite was not enabled")
		}
	}
}

func TestPacketEnabled(t *testing.T) {
	for _, options := range []Options{
		{ERC20ToGno: true},
		{AmountBoundaries: true},
		{GnoToEVM: true},
		{RelayerInsufficientBalanceFailover: true},
		{RelayerOfflineFailover: true},
		{RelayerBalanceRecovery: true},
		{EVMToGnoTimeoutRefund: true},
		{GnoToEVMTimeoutRefund: true},
	} {
		if !options.PacketEnabled() {
			t.Fatalf("options %#v did not enable packet config", options)
		}
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
		ScriptDir:                 scriptDir,
		UnionChainID:              "union-devnet-1",
		EVMChainID:                "17000",
		GnoChainID:                "dev.ibc",
		UnionVoyagerRevision:      testVoyagerRevision,
		EVMIBCHandler:             "0x1111111111111111111111111111111111111111",
		EVMMulticall:              "0x2222222222222222222222222222222222222222",
		EVMCometBLSClientImpl:     "0x3333333333333333333333333333333333333333",
		EVMProofLensClientImpl:    "0x4444444444444444444444444444444444444444",
		GnoZKGMPort:               "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm",
		EVMZKGMContract:           "0x5555555555555555555555555555555555555555",
		EVMTestERC20:              "0x6666666666666666666666666666666666666666",
		GnoRecipient:              "g1" + strings.Repeat("a", 38),
		EVMTestAmount:             "1000000000000",
		RelayerEmptyPrivateKey:    "0x" + strings.Repeat("1", 64),
		RelayerOfflinePrivateKey:  "0x" + strings.Repeat("2", 64),
		RelayerRecoveryPrivateKey: "0x" + strings.Repeat("3", 64),
		ArtifactDir:               artifactDir,
	}
}
