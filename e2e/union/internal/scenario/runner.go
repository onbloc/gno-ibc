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

	"github.com/onbloc/gno-ibc/e2e/union/internal/config"
	"github.com/onbloc/gno-ibc/e2e/union/internal/evm"
	"github.com/onbloc/gno-ibc/e2e/union/internal/gno"
	"github.com/onbloc/gno-ibc/e2e/union/internal/state"
	"github.com/onbloc/gno-ibc/e2e/union/internal/union"
	"github.com/onbloc/gno-ibc/e2e/union/internal/voyager"
)

// Options select writes and live scenarios.
type Options struct {
	Apply                              bool
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

// New validates the selected scenarios before any external command can run.
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
		current:  state.State{FailedWork: state.FailedWork{Repaired: []int64{}}},
		progress: os.Stderr,
	}
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
	if !r.options.Apply {
		return nil
	}
	repoRoot := filepath.Clean(filepath.Join(r.cfg.ScriptDir, "..", ".."))
	if err := state.PrepareArtifacts(repoRoot, r.cfg.ScriptDir, r.cfg.ArtifactDir); err != nil {
		return err
	}
	defer func() {
		cleanupCtx, cancel := context.WithTimeout(context.WithoutCancel(ctx), r.cfg.CleanupTimeout)
		defer cancel()
		if runErr != nil {
			logFile, err := os.OpenFile(filepath.Join(r.cfg.ArtifactDir, "voyager.log"), os.O_CREATE|os.O_WRONLY|os.O_TRUNC, 0o600)
			if err == nil {
				err = errors.Join(r.voyager.CaptureLogs(cleanupCtx, logFile), logFile.Close())
			}
			runErr = errors.Join(runErr, err)
		}
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

func (r *Runner) restoreZKGM(
	ctx context.Context,
	setPaused func(context.Context, bool) (string, error),
	runErr *error,
) {
	cleanupCtx, cancel := context.WithTimeout(context.WithoutCancel(ctx), r.cfg.CleanupTimeout)
	defer cancel()
	_, err := setPaused(cleanupCtx, false)
	*runErr = errors.Join(*runErr, err)
}

func (r *Runner) preflight(ctx context.Context) ([]byte, error) {
	rendered, err := r.renderVoyager(nil, nil)
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
