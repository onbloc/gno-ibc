package scenario

import (
	"context"
	"errors"
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
	plan, err := r.evm.Prepare(ctx, r.current.Channels.Gno)
	if err != nil {
		return err
	}
	mintTx, err := r.evm.Mint(ctx, plan.Sender)
	if err != nil {
		return err
	}
	approveTx, err := r.evm.Approve(ctx)
	if err != nil {
		return err
	}
	before, err := r.evm.Snapshot(ctx, plan.Sender)
	if err != nil {
		return err
	}
	recipientBefore, err := r.gno.VoucherBalance(ctx, plan.Voucher, r.cfg.GnoRecipient)
	if err != nil {
		return err
	}

	shouldUnpause := true
	defer func() {
		if !shouldUnpause {
			return
		}
		cleanupCtx, cancel := context.WithTimeout(context.WithoutCancel(ctx), r.cfg.CleanupTimeout)
		defer cancel()
		_, cleanupErr := r.gno.SetZKGMPaused(cleanupCtx, false)
		runErr = errors.Join(runErr, cleanupErr)
	}()
	pauseTx, err := r.gno.SetZKGMPaused(ctx, true)
	if err != nil {
		return err
	}
	r.progressf("scenario evm-to-gno-timeout-refund: Gno ZKGM paused (tx=%s)", pauseTx)

	timeoutTimestamp := uint64(time.Now().Add(evmToGnoTimeout).UnixNano())
	send, err := r.evm.SendTokenOrderWithTimeout(
		ctx, r.current.Channels.EVM, plan, r.cfg.GnoRecipient,
		r.cfg.EVMTestAmount, 0, timeoutTimestamp,
	)
	if err != nil {
		return err
	}
	r.progressf("scenario evm-to-gno-timeout-refund: packet=%s timeout_ns=%d; waiting for EVM timeout",
		send.PacketHash, timeoutTimestamp)
	timeout, err := r.evm.WaitTimeout(ctx, before.Block, r.current.Channels.EVM, send.PacketHash)
	if err != nil {
		return err
	}
	if err := r.evm.VerifyCommitmentCleared(ctx, send.PacketHash); err != nil {
		return err
	}
	receiveCount, err := r.gno.EventCount(ctx, "PacketRecv", send.PacketHash)
	if err != nil {
		return err
	}
	if receiveCount != 0 {
		return fmt.Errorf("paused Gno ZKGM unexpectedly received the packet")
	}
	senderAfter, escrowAfter, err := r.evm.Balances(ctx, plan.Sender)
	if err != nil {
		return err
	}
	recipientAfter, err := r.gno.VoucherBalance(ctx, plan.Voucher, r.cfg.GnoRecipient)
	if err != nil {
		return err
	}
	deltas, err := classifyBoundaryBalances(false, r.cfg.EVMTestAmount,
		state.Balances{
			Sender: before.Sender, Escrow: before.Escrow,
			Recipient: strconv.FormatInt(recipientBefore, 10),
		},
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
		timeout.Tx, unpauseTx)
	return r.writeEvidence("evm-to-gno-timeout-refund.json", map[string]any{
		"token": plan.Token, "amount": r.cfg.EVMTestAmount,
		"packet_hash": send.PacketHash, "timeout_timestamp_ns": timeoutTimestamp,
		"commitment_cleared": true, "gno_receive_count": receiveCount,
		"transactions": map[string]string{
			"mint": mintTx, "approve": approveTx, "send": send.Tx,
			"pause_gno": pauseTx, "evm_timeout": timeout.Tx, "unpause_gno": unpauseTx,
		},
		"balance_deltas": deltas,
	})
}
