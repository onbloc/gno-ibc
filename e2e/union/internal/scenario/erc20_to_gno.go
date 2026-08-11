package scenario

import (
	"context"
	"fmt"
)

// runERC20ToGnoScenario executes one disposable packet attempt.
func (r *Runner) runERC20ToGnoScenario(ctx context.Context) error {
	if r.packet != nil {
		return fmt.Errorf("ERC20 packet already submitted")
	}
	packet, _, err := r.submitERC20Packet(ctx, 0)
	if err != nil {
		return err
	}
	r.packet = packet
	result, err := r.observePacket(ctx)
	if err != nil {
		return err
	}
	return r.finishPacket(result)
}
