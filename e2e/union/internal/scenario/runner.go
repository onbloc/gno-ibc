// Package scenario owns the order and acceptance evidence for the live
// Union-EVM-Gno scenarios.
package scenario

import (
	"bytes"
	"context"
	"fmt"
	"os"
	"path/filepath"

	"github.com/onbloc/gno-ibc/e2e/union/internal/config"
	"github.com/onbloc/gno-ibc/e2e/union/internal/process"
	"github.com/onbloc/gno-ibc/e2e/union/internal/state"
)

// Options are the runner's explicit write and resume boundaries.
type Options struct {
	Apply      bool
	Resume     bool
	ERC20ToGno bool
}

// Runner executes the live acceptance scenarios.
type Runner struct {
	cfg     config.Config
	exec    process.Executor
	options Options
	saved   *state.State
}

// New validates and loads resume state before any external command can run.
func New(cfg config.Config, options Options) (*Runner, error) {
	return newRunner(cfg, process.OSExecutor{}, options)
}

func newRunner(cfg config.Config, executor process.Executor, options Options) (*Runner, error) {
	if options.ERC20ToGno && !options.Apply {
		return nil, fmt.Errorf("--erc20-to-gno requires --apply")
	}
	runner := &Runner{cfg: cfg, exec: executor, options: options}
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
	runner.saved = &saved
	return runner, nil
}

func (r *Runner) preflight(ctx context.Context) error {
	template, err := os.ReadFile(filepath.Join(r.cfg.ScriptDir, "config.jsonc.template"))
	if err != nil {
		return fmt.Errorf("missing Voyager config template")
	}
	var plain, proof []int64
	if r.saved != nil {
		plain, proof, err = r.saved.Allowlists.IDs()
		if err != nil {
			return err
		}
	}
	if _, err := config.RenderVoyager(template, r.cfg, plain, proof); err != nil {
		return err
	}
	result, err := r.execute(ctx, process.Command{
		Name: "git",
		Args: []string{"-C", r.cfg.UnionVoyagerDir, "rev-parse", "HEAD"},
	})
	if err != nil {
		return fmt.Errorf("UNION_VOYAGER_DIR is not a readable git checkout")
	}
	if string(bytes.TrimSpace(result.Stdout)) != r.cfg.UnionVoyagerRevision {
		return fmt.Errorf("union-voyager checkout does not match UNION_VOYAGER_REVISION")
	}
	result, err = r.execute(ctx, process.Command{
		Name: "git",
		Args: []string{"-C", r.cfg.UnionVoyagerDir, "status", "--porcelain"},
	})
	if err != nil {
		return fmt.Errorf("UNION_VOYAGER_DIR is not a readable git checkout")
	}
	if len(bytes.TrimSpace(result.Stdout)) != 0 {
		return fmt.Errorf("union-voyager checkout must be clean")
	}
	return nil
}

func (r *Runner) execute(ctx context.Context, command process.Command) (process.Result, error) {
	if r.cfg.CommandTimeout <= 0 {
		return r.exec.Run(ctx, command)
	}
	commandCtx, cancel := context.WithTimeout(ctx, r.cfg.CommandTimeout)
	defer cancel()
	return r.exec.Run(commandCtx, command)
}

func expectedState(cfg config.Config) state.Expected {
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
	}
}
