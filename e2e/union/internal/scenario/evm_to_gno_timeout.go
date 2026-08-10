package scenario

import (
	"context"
	"fmt"
	"strconv"
	"time"

	"github.com/onbloc/gno-ibc/e2e/union/internal/state"
)

const evmToGnoTimeout = 3 * time.Minute

// runEVMToGnoTimeoutRefund pauses Gno delivery and proves the EVM timeout refund.
func (r *Runner) runEVMToGnoTimeoutRefund(ctx context.Context) (runErr error) {
	if r.current.Channels == nil || r.current.FailedWork.Final == nil {
		return fmt.Errorf("EVM-to-Gno timeout requires a verified complete channel state")
	}
	shouldUnpause := true
	defer func() {
		if shouldUnpause {
			r.restoreZKGM(ctx, r.gno.SetZKGMPaused, &runErr)
		}
	}()
	pauseTx, err := r.gno.SetZKGMPaused(ctx, true)
	if err != nil {
		return err
	}
	r.progressf("scenario evm-to-gno-timeout-refund: Gno ZKGM paused (tx=%s)", pauseTx)

	packet, timeoutTimestamp, err := r.submitERC20Packet(ctx, evmToGnoTimeout)
	if err != nil {
		return err
	}
	r.progressf("scenario evm-to-gno-timeout-refund: packet=%s timeout_ns=%d; waiting for EVM timeout",
		packet.PacketHash, timeoutTimestamp)
	timedOut, err := r.evm.WaitTimeout(ctx, *packet.EVMFromBlock, r.current.Channels.EVM, packet.PacketHash)
	if err != nil {
		return err
	}
	if err := r.evm.VerifyCommitmentCleared(ctx, packet.PacketHash); err != nil {
		return err
	}
	receiveCount, err := r.gno.EventCount(ctx, "PacketRecv", packet.PacketHash)
	if err != nil {
		return err
	}
	if receiveCount != 0 {
		return fmt.Errorf("paused Gno ZKGM unexpectedly received the packet")
	}
	senderAfter, escrowAfter, err := r.evm.Balances(ctx, packet.Sender)
	if err != nil {
		return err
	}
	recipientAfter, err := r.gno.VoucherBalance(ctx, packet.Voucher, packet.Recipient)
	if err != nil {
		return err
	}
	deltas, err := classifyBoundaryBalances(false, r.cfg.EVMTestAmount,
		*packet.BalancesBefore,
		state.Balances{
			Sender: senderAfter, Escrow: escrowAfter,
			Recipient: strconv.FormatInt(recipientAfter, 10),
		},
	)
	if err != nil {
		return err
	}
	unpauseTx, err := r.gno.SetZKGMPaused(ctx, false)
	if err != nil {
		return err
	}
	shouldUnpause = false
	if err := r.verifyNoNewFailedWork(ctx); err != nil {
		return err
	}
	r.progressf("scenario evm-to-gno-timeout-refund: timed out (tx=%s); full refund verified; Gno ZKGM unpaused (tx=%s)",
		timedOut.Tx, unpauseTx)
	return r.writeEvidence("evm-to-gno-timeout-refund.json", map[string]any{
		"token": packet.Token, "amount": packet.Amount,
		"packet_hash": packet.PacketHash, "timeout_timestamp_ns": timeoutTimestamp,
		"commitment_cleared": true, "gno_receive_count": receiveCount,
		"transactions": map[string]string{
			"mint": packet.MintTx, "approve": packet.ApproveTx, "send": packet.SendTx,
			"pause_gno": pauseTx, "evm_timeout": timedOut.Tx, "unpause_gno": unpauseTx,
		},
		"balance_deltas": deltas,
	})
}
