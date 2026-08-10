package scenario

import (
	"context"
	"fmt"
	"time"
)

const gnoToEVMTimeout = 3 * time.Minute

type gnoTimeoutResult struct {
	PacketHash       string `json:"packet_hash"`
	SourceTx         string `json:"source_tx"`
	TimeoutTx        string `json:"timeout_tx"`
	PauseTx          string `json:"pause_tx"`
	UnpauseTx        string `json:"unpause_tx"`
	TimeoutTimestamp uint64 `json:"timeout_timestamp"`
	EscrowDelta      int64  `json:"escrow_delta"`
	RefundAmount     string `json:"refund_amount"`
}

// runGnoToEVMTimeoutRefund verifies a real timeout while the destination app is paused.
func (r *Runner) runGnoToEVMTimeoutRefund(ctx context.Context) (runErr error) {
	plan, err := r.evm.PrepareWrappedToken(ctx, r.current.Channels.EVM, "ugnot")
	if err != nil {
		return err
	}
	proxy, err := r.gno.ProxyAddress(ctx)
	if err != nil {
		return err
	}
	proxyBefore, err := r.gno.NativeBalance(ctx, proxy, "ugnot")
	if err != nil {
		return err
	}
	cleanup := true
	defer func() {
		if cleanup {
			r.restoreZKGM(ctx, r.evm.SetZKGMPaused, &runErr)
		}
	}()
	pauseTx, err := r.evm.SetZKGMPaused(ctx, true)
	if err != nil {
		return err
	}
	if pauseTx == "" {
		cleanup = false
		return fmt.Errorf("EVM ZKGM was already paused")
	}

	operand, err := r.encodeNativeTokenOrder(ctx, r.cfg.GnoRecipient, plan, 0)
	if err != nil {
		return err
	}
	timeout := time.Now().Add(gnoToEVMTimeout)
	r.progressf("scenario gno-to-evm-timeout-refund: EVM ZKGM paused tx=%s; sending amount=%sugnot timeout=%s",
		pauseTx, nativeLifecycleAmount, timeout.UTC().Format(time.RFC3339))
	send, err := r.gno.SendRawWithTimeout(
		ctx, r.current.Channels.Gno, operand, nativeLifecycleAmount+"ugnot", timeout,
	)
	if err != nil {
		return err
	}
	proxyEscrowed, err := r.gno.NativeBalance(ctx, proxy, "ugnot")
	if err != nil {
		return err
	}
	if proxyEscrowed-proxyBefore != 1 {
		return fmt.Errorf("Gno timeout send escrow delta=%d, want 1", proxyEscrowed-proxyBefore)
	}
	r.progressf("scenario gno-to-evm-timeout-refund: packet submitted hash=%s tx=%s escrow_delta=1; waiting for timeout",
		send.PacketHash, send.Tx)
	timedOut, err := r.gno.WaitTimeout(ctx, send.PacketHash)
	if err != nil {
		return err
	}
	if timedOut.TimeoutTimestamp != send.TimeoutTimestamp {
		return fmt.Errorf("Gno PacketTimeout timestamp=%d, want %d", timedOut.TimeoutTimestamp, send.TimeoutTimestamp)
	}
	if timedOut.RefundRecipient != r.cfg.GnoRecipient || timedOut.RefundDenom != "ugnot" ||
		timedOut.RefundAmount != nativeLifecycleAmount {
		return fmt.Errorf("Gno timeout native refund does not match the sender, denom, and amount")
	}
	ackCount, err := r.gno.EventCount(ctx, "PacketAck", send.PacketHash)
	if err != nil {
		return err
	}
	if ackCount != 0 {
		return fmt.Errorf("timed-out Gno packet has PacketAck count=%d", ackCount)
	}
	receiveCount, err := r.evm.PacketReceiveCount(ctx, 0, r.current.Channels.EVM, send.PacketHash)
	if err != nil {
		return err
	}
	if receiveCount != 0 {
		return fmt.Errorf("paused EVM ZKGM unexpectedly received the packet")
	}
	if err := r.gno.VerifyCommitmentCleared(ctx, send.PacketHash); err != nil {
		return err
	}
	proxyAfter, err := r.gno.NativeBalance(ctx, proxy, "ugnot")
	if err != nil {
		return err
	}
	if proxyAfter != proxyBefore {
		return fmt.Errorf("timeout refund proxy delta=%d, want 0", proxyAfter-proxyBefore)
	}

	unpauseTx, err := r.evm.SetZKGMPaused(ctx, false)
	if err != nil {
		return err
	}
	cleanup = false
	if unpauseTx == "" {
		return fmt.Errorf("EVM ZKGM unpause did not submit a transaction")
	}
	if err := r.verifyNoNewFailedWork(ctx); err != nil {
		return err
	}
	r.progressf("scenario gno-to-evm-timeout-refund: timeout tx=%s refund=%s%s recipient=%s proxy_delta=0 commitment=cleared; EVM ZKGM unpaused tx=%s",
		timedOut.Tx, timedOut.RefundAmount, timedOut.RefundDenom, timedOut.RefundRecipient, unpauseTx)
	return r.writeEvidence("gno-to-evm-timeout-refund.json", gnoTimeoutResult{
		PacketHash: send.PacketHash, SourceTx: send.Tx, TimeoutTx: timedOut.Tx,
		PauseTx: pauseTx, UnpauseTx: unpauseTx, TimeoutTimestamp: send.TimeoutTimestamp,
		EscrowDelta: proxyEscrowed - proxyBefore, RefundAmount: timedOut.RefundAmount,
	})
}
