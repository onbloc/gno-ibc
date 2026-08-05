// Package scenario owns the order and acceptance evidence for the live
// Union-EVM-Gno scenarios.
package scenario

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	osexec "os/exec"
	"path/filepath"
	"strings"

	"github.com/onbloc/gno-ibc/e2e/union/internal/config"
	"github.com/onbloc/gno-ibc/e2e/union/internal/evm"
	"github.com/onbloc/gno-ibc/e2e/union/internal/gno"
	"github.com/onbloc/gno-ibc/e2e/union/internal/state"
	"github.com/onbloc/gno-ibc/e2e/union/internal/union"
	"github.com/onbloc/gno-ibc/e2e/union/internal/voyager"
)

// Options are the runner's explicit write and resume boundaries.
type Options struct {
	Apply                              bool
	Resume                             bool
	ForgedProofRejection               bool
	ERC20ToGno                         bool
	AmountBoundaries                   bool
	GnoToEVM                           bool
	RelayerInsufficientBalanceFailover bool
	RelayerOfflineFailover             bool
	RelayerBalanceRecovery             bool
	EVMToGnoTimeoutRefund              bool
	GnoToEVMTimeoutRefund              bool
}

// Normalize enables prerequisites implied by selected scenarios.
func (o *Options) Normalize() {
	if o.AmountBoundaries || o.GnoToEVM {
		o.ERC20ToGno = true
	}
}

// PacketEnabled reports whether a selected scenario uses the live packet tools.
func (o Options) PacketEnabled() bool {
	return o.ERC20ToGno || o.AmountBoundaries || o.GnoToEVM ||
		o.RelayerInsufficientBalanceFailover || o.RelayerOfflineFailover ||
		o.RelayerBalanceRecovery || o.EVMToGnoTimeoutRefund || o.GnoToEVMTimeoutRefund
}

// Runner executes the live acceptance scenarios.
type Runner struct {
	cfg      config.Config
	voyager  *voyager.Runtime
	evm      *evm.Client
	gno      *gno.Client
	union    *union.Client
	options  Options
	current  state.State
	packet   *state.Packet
	progress io.Writer

	evmIndexFrom     string
	reservedEVMPlain int64

	gnoConnectionEvidence json.RawMessage
	evmConnectionEvidence json.RawMessage
	gnoChannelEvidence    json.RawMessage
	evmChannelEvidence    json.RawMessage
}

// New validates and loads resume state before any external command can run.
func New(cfg config.Config, options Options) (*Runner, error) {
	return newRunnerWithClients(
		cfg, options, voyager.New(cfg, os.Stderr), evm.New(cfg), gno.New(cfg), union.New(cfg),
	)
}

func newRunnerWithClients(
	cfg config.Config,
	options Options,
	voyagerRuntime *voyager.Runtime,
	evmClient *evm.Client,
	gnoClient *gno.Client,
	unionClient *union.Client,
) (*Runner, error) {
	options.Normalize()
	if options.PacketEnabled() && !options.Apply {
		return nil, fmt.Errorf("packet scenarios require --apply")
	}
	if options.ForgedProofRejection && !options.Apply {
		return nil, fmt.Errorf("--forged-proof-rejection requires --apply")
	}
	if (options.GnoToEVM || options.GnoToEVMTimeoutRefund) && cfg.GnoRecipient != gno.DevSenderAddress {
		return nil, fmt.Errorf("Gno-to-EVM scenarios require the dev Gno sender")
	}
	runner := &Runner{
		cfg: cfg, options: options,
		voyager:  voyagerRuntime,
		evm:      evmClient,
		gno:      gnoClient,
		union:    unionClient,
		current:  newState(cfg),
		progress: os.Stderr,
	}
	if !options.Resume {
		return runner, nil
	}
	saved, err := state.Load(cfg.StateFile)
	if err != nil {
		return nil, err
	}
	if err := saved.Validate(expectedState(cfg)); err != nil {
		return nil, err
	}
	runner.current = saved
	return runner, nil
}

// Run owns Voyager for the complete selected scenario sequence.
func (r *Runner) Run(ctx context.Context) (runErr error) {
	r.progressf("preflight: started")
	rendered, err := r.preflight(ctx)
	if err != nil {
		return err
	}
	r.progressf("preflight: passed")
	if !r.options.Apply && !r.options.Resume {
		return nil
	}
	repoRoot := filepath.Clean(filepath.Join(r.cfg.ScriptDir, "..", ".."))
	if err := state.PrepareArtifacts(repoRoot, r.cfg.ScriptDir, r.cfg.ArtifactDir, r.cfg.StateFile); err != nil {
		return err
	}
	if !r.options.Resume {
		if err := state.EnsureFresh(r.cfg.StateFile); err != nil {
			return err
		}
	}
	defer func() {
		cleanupCtx, cancel := context.WithTimeout(context.WithoutCancel(ctx), r.cfg.CleanupTimeout)
		defer cancel()
		runErr = errors.Join(runErr, r.voyager.Close(cleanupCtx))
	}()
	r.progressf("Voyager: starting")
	if err := r.voyager.Start(ctx, rendered); err != nil {
		return err
	}
	r.progressf("Voyager: ready")
	r.progressf("channel topology: started")
	if err := r.runChannelScenario(ctx); err != nil {
		return err
	}
	r.progressf("channel topology: passed")
	for _, sc := range scenarioCases {
		if !sc.enabled(r.options) {
			continue
		}
		if err := r.runScenario(ctx, sc); err != nil {
			return err
		}
	}
	return nil
}

func (r *Runner) runScenario(ctx context.Context, sc scenarioCase) error {
	r.progressf("scenario %s: started", sc.name)
	if err := sc.run(r, ctx); err != nil {
		r.progressf("scenario %s: failed: %v", sc.name, err)
		return fmt.Errorf("scenario %s: %w", sc.name, err)
	}
	r.progressf("scenario %s: passed", sc.name)
	return nil
}

func (r *Runner) progressf(format string, args ...any) {
	if r.progress != nil {
		fmt.Fprintf(r.progress, "e2e: "+format+"\n", args...)
	}
}

func (r *Runner) preflight(ctx context.Context) ([]byte, error) {
	var plain, proof []int64
	var err error
	if r.options.Resume {
		plain, proof, err = r.current.Allowlists.IDs()
		if err != nil {
			return nil, err
		}
	}
	rendered, err := r.renderVoyager(plain, proof)
	if err != nil {
		return nil, err
	}
	if r.options.PacketEnabled() || r.options.ForgedProofRejection {
		for _, name := range []string{"cast", "gnokey"} {
			if _, err := osexec.LookPath(name); err != nil {
				return nil, fmt.Errorf("missing required packet command: %s", name)
			}
		}
	}
	if r.options.AmountBoundaries {
		if _, err := osexec.LookPath("forge"); err != nil {
			return nil, fmt.Errorf("missing required packet command: forge")
		}
	}
	return rendered, nil
}

func (r *Runner) renderVoyager(plain, proof []int64) ([]byte, error) {
	template, err := os.ReadFile(filepath.Join(r.cfg.ScriptDir, "config.jsonc.template"))
	if err != nil {
		return nil, fmt.Errorf("missing Voyager config template")
	}
	return config.RenderVoyager(template, r.cfg, plain, proof)
}

func expectedState(cfg config.Config) state.Expected {
	return state.Expected{
		VoyagerRevision: cfg.UnionVoyagerRevision,
		Chains:          state.Chains{Union: cfg.UnionChainID, EVM: cfg.EVMChainID, Gno: cfg.GnoChainID},
		EVMTopology: state.EVMTopology{
			ChainID:             cfg.EVMChainID,
			IBCHandler:          cfg.EVMIBCHandler,
			Multicall:           cfg.EVMMulticall,
			ZKGM:                cfg.EVMZKGMContract,
			CometBLSClientImpl:  cfg.EVMCometBLSClientImpl,
			ProofLensClientImpl: cfg.EVMProofLensClientImpl,
		},
		GnoPort: cfg.GnoZKGMPort,
		EVMPort: cfg.EVMZKGMContract,
		Version: config.ChannelVersion,
	}
}

func newState(cfg config.Config) state.State {
	expected := expectedState(cfg)
	return state.State{
		VoyagerRevision: expected.VoyagerRevision,
		Chains:          expected.Chains,
		EVMTopology:     expected.EVMTopology,
		Ports:           state.Ports{Gno: expected.GnoPort, EVM: strings.ToLower(expected.EVMPort)},
		Version:         expected.Version,
		FailedWork:      state.FailedWork{Repaired: []int64{}},
	}
}
