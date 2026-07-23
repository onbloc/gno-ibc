package scenario

import (
	"context"

	"github.com/onbloc/gno-ibc/e2e/union/internal/state"
)

var saveBootstrap = state.SaveBootstrap

// runChannelScenario establishes and verifies S1. Resume skips bootstrap and
// never repeats an ambiguous write.
func (r *Runner) runChannelScenario(ctx context.Context) error {
	if r.options.Resume && r.current.Phase == state.PhaseComplete {
		if err := r.verifyClientRelations(ctx); err != nil {
			return err
		}
		if err := r.verifyOpenHandshakes(ctx); err != nil {
			return err
		}
		return r.verifyNoNewFailedWork(ctx)
	}
	if !r.options.Resume {
		if err := r.indexUnionAndGno(ctx); err != nil {
			return err
		}
		if err := r.establishUnderlyingClients(ctx); err != nil {
			return err
		}
		if err := r.establishLensClients(ctx); err != nil {
			return err
		}
		if err := r.allowlistAndIndexEVM(ctx); err != nil {
			return err
		}
	}
	if err := r.verifyClientRelations(ctx); err != nil {
		return err
	}
	if err := r.establishConnection(ctx); err != nil {
		return err
	}
	if err := r.establishChannel(ctx); err != nil {
		return err
	}
	if err := r.verifyNoNewFailedWork(ctx); err != nil {
		return err
	}
	return r.saveChannelEvidence()
}

func (r *Runner) indexUnionAndGno(ctx context.Context) error {
	baseline, err := r.voyager.FailedWorkID(ctx, 0, nil)
	if err != nil {
		return err
	}
	r.current.FailedWork.Baseline = baseline
	r.reservedEVMPlain, err = r.voyager.NextClientID(ctx, r.cfg.EVMChainID)
	if err != nil {
		return err
	}
	rendered, err := r.renderVoyager(
		[]int64{r.reservedEVMPlain}, []int64{r.reservedEVMPlain + 1},
	)
	if err != nil {
		return err
	}
	if err := r.voyager.Restart(ctx, rendered); err != nil {
		return err
	}
	r.evmIndexFrom, err = r.voyager.LatestFinalizedHeight(ctx, r.cfg.EVMChainID)
	if err != nil {
		return err
	}
	if err := r.voyager.Index(ctx, r.cfg.UnionChainID, ""); err != nil {
		return err
	}
	return r.voyager.Index(ctx, r.cfg.GnoChainID, "")
}

func (r *Runner) allowlistAndIndexEVM(ctx context.Context) error {
	if err := r.voyager.Index(ctx, r.cfg.EVMChainID, r.evmIndexFrom); err != nil {
		return err
	}
	plain, proof, err := r.voyager.EVMAllowlists(ctx)
	if err != nil {
		return err
	}
	r.current.Allowlists = state.Allowlists{Plain: joinIDs(plain), ProofLens: joinIDs(proof)}
	rendered, err := r.renderVoyager(plain, proof)
	if err != nil {
		return err
	}
	return r.voyager.Restart(ctx, rendered)
}
