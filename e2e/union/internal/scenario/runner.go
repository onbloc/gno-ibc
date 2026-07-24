// Package scenario owns the order and acceptance evidence for the live
// Union-EVM-Gno scenarios.
package scenario

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
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
	Apply            bool
	Resume           bool
	ERC20ToGno       bool
	AmountBoundaries bool
	GnoToEVM         bool
}

// Runner executes the live acceptance scenarios.
type Runner struct {
	cfg     config.Config
	voyager *voyager.Runtime
	evm     *evm.Client
	gno     *gno.Client
	union   *union.Client
	options Options
	current state.State

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
	if options.ERC20ToGno && !options.Apply {
		return nil, fmt.Errorf("--erc20-to-gno requires --apply")
	}
	if options.AmountBoundaries && !options.ERC20ToGno {
		return nil, fmt.Errorf("--amount-boundaries requires --erc20-to-gno")
	}
	if options.GnoToEVM && !options.ERC20ToGno {
		return nil, fmt.Errorf("--gno-to-evm requires --erc20-to-gno")
	}
	if options.GnoToEVM && cfg.GnoRecipient != gno.DevSenderAddress {
		return nil, fmt.Errorf("--gno-to-evm requires the dev Gno sender")
	}
	runner := &Runner{
		cfg: cfg, options: options,
		voyager: voyagerRuntime,
		evm:     evmClient,
		gno:     gnoClient,
		union:   unionClient,
		current: newState(cfg),
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
	rendered, err := r.preflight(ctx)
	if err != nil {
		return err
	}
	if !r.options.Apply && !r.options.Resume {
		return nil
	}
	repoRoot := filepath.Clean(filepath.Join(r.cfg.ScriptDir, "..", ".."))
	if err := state.PrepareArtifacts(repoRoot, r.cfg.ScriptDir, r.cfg.ArtifactDir, r.cfg.StateFile); err != nil {
		return err
	}
	if !r.options.Resume {
		if err := state.EnsureFresh(r.cfg.StateFile, r.bootstrapFile()); err != nil {
			return err
		}
	}
	defer func() {
		cleanupCtx, cancel := context.WithTimeout(context.WithoutCancel(ctx), r.cfg.CleanupTimeout)
		defer cancel()
		runErr = errors.Join(runErr, r.voyager.Close(cleanupCtx))
	}()
	if err := r.voyager.Start(ctx, rendered); err != nil {
		return err
	}
	if !r.options.Resume {
		if err := saveBootstrap(r.bootstrapFile(), r.current); err != nil {
			return err
		}
	}
	if err := r.runChannelScenario(ctx); err != nil {
		return err
	}
	for _, sc := range scenarioCases {
		if !sc.enabled(r.options) {
			continue
		}
		if err := sc.run(r, ctx); err != nil {
			return fmt.Errorf("scenario %s: %w", sc.name, err)
		}
	}
	return nil
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
	if err := r.voyager.ValidateSource(ctx); err != nil {
		return nil, err
	}
	if r.options.ERC20ToGno {
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

func (r *Runner) bootstrapFile() string {
	return filepath.Join(r.cfg.ArtifactDir, "bootstrap-in-progress.json")
}

func expectedState(cfg config.Config) state.Expected {
	packetLedgerAmount, _ := config.PacketLedgerAmount(cfg.EVMTestAmount)
	return state.Expected{
		VoyagerRevision:     cfg.UnionVoyagerRevision,
		Chains:              state.Chains{Union: cfg.UnionChainID, EVM: cfg.EVMChainID, Gno: cfg.GnoChainID},
		EVMChainID:          cfg.EVMChainID,
		TopologyFingerprint: cfg.TopologyFingerprint(),
		GnoPort:             cfg.GnoZKGMPort,
		EVMPort:             cfg.EVMZKGMContract,
		Version:             config.ChannelVersion,
		PacketToken:         cfg.EVMTestERC20,
		PacketRecipient:     cfg.GnoRecipient,
		PacketAmount:        cfg.EVMTestAmount,
		PacketLedgerAmount:  packetLedgerAmount,
	}
}

func newState(cfg config.Config) state.State {
	return state.State{
		Phase:           state.PhaseBootstrap,
		VoyagerRevision: cfg.UnionVoyagerRevision,
		Chains:          state.Chains{Union: cfg.UnionChainID, EVM: cfg.EVMChainID, Gno: cfg.GnoChainID},
		EVMTopology: state.EVMTopology{
			ChainID: cfg.EVMChainID, AddressFingerprint: cfg.TopologyFingerprint(),
		},
		Ports:      state.Ports{Gno: cfg.GnoZKGMPort, EVM: strings.ToLower(cfg.EVMZKGMContract)},
		Version:    config.ChannelVersion,
		FailedWork: state.FailedWork{Repaired: []int64{}},
	}
}
