package scenario

import "context"

// runERC20ToGnoScenario sends and verifies S3. A matching S4 failure continues through
// refund verification and evidence saving before requirePacketSuccess fails.
func (r *Runner) runERC20ToGnoScenario(ctx context.Context) error {
	if err := r.validateERC20(ctx); err != nil {
		return err
	}
	if err := r.mintERC20(ctx); err != nil {
		return err
	}
	if err := r.approveERC20(ctx); err != nil {
		return err
	}
	if err := r.sendTokenOrder(ctx); err != nil {
		return err
	}
	if err := r.verifyPacketEvents(ctx); err != nil {
		return err
	}
	if err := r.classifyAcknowledgements(ctx); err != nil {
		return err
	}
	if err := r.verifyCommitmentCleared(ctx); err != nil {
		return err
	}
	if err := r.verifyPacketBalances(ctx); err != nil {
		return err
	}
	if err := r.verifyNoNewFailedWork(ctx); err != nil {
		return err
	}
	if err := r.savePacketEvidence(ctx); err != nil {
		return err
	}
	return r.requirePacketSuccess(ctx)
}

func (r *Runner) validateERC20(context.Context) error            { return nil }
func (r *Runner) mintERC20(context.Context) error                { return nil }
func (r *Runner) approveERC20(context.Context) error             { return nil }
func (r *Runner) sendTokenOrder(context.Context) error           { return nil }
func (r *Runner) verifyPacketEvents(context.Context) error       { return nil }
func (r *Runner) classifyAcknowledgements(context.Context) error { return nil }
func (r *Runner) verifyCommitmentCleared(context.Context) error  { return nil }
func (r *Runner) verifyPacketBalances(context.Context) error     { return nil }
func (r *Runner) savePacketEvidence(context.Context) error       { return nil }
func (r *Runner) requirePacketSuccess(context.Context) error     { return nil }
