package scenario

import (
	"context"
	"fmt"
	"math"
	"strconv"

	"github.com/onbloc/gno-ibc/e2e/union/internal/evm"
	"github.com/onbloc/gno-ibc/e2e/union/internal/state"
)

const (
	maxLedgerAmount      = "9223372036854775807"
	overflowLedgerAmount = "9223372036854775808"
)

type boundaryResult struct {
	Name       string         `json:"name"`
	Token      string         `json:"token"`
	PacketHash string         `json:"packet_hash"`
	MintTx     string         `json:"mint_tx"`
	ApproveTx  string         `json:"approve_tx"`
	SendTx     string         `json:"send_tx"`
	GnoTx      string         `json:"gno_tx"`
	EVMAckTx   string         `json:"evm_ack_tx"`
	Success    bool           `json:"success"`
	Deltas     state.Balances `json:"deltas"`
}

func (r *Runner) runAmountBoundaries(ctx context.Context) error {
	if r.current.Phase != state.PhasePacketComplete ||
		r.current.Packet.Outcome != state.PacketOutcomeSuccess {
		return fmt.Errorf("amount boundaries require a successful ERC20 packet")
	}

	overflowToken, err := r.evm.DeployTestToken(ctx, "Union Overflow", "UOF", 6)
	if err != nil {
		return err
	}
	overflowPlan, err := r.evm.PrepareToken(ctx, overflowToken, 6, r.current.Channels.Gno)
	if err != nil {
		return err
	}
	overflow, err := r.runBoundaryOrder(
		ctx, "max-plus-one-refund", overflowPlan, overflowLedgerAmount, 0, false,
	)
	if err != nil {
		return err
	}

	cumulativeToken, err := r.evm.DeployTestToken(ctx, "Union Cumulative", "UCM", 6)
	if err != nil {
		return err
	}
	cumulativePlan, err := r.evm.PrepareToken(ctx, cumulativeToken, 6, r.current.Channels.Gno)
	if err != nil {
		return err
	}
	maximum, err := r.runBoundaryOrder(
		ctx, "max-succeeds", cumulativePlan, maxLedgerAmount, 0, true,
	)
	if err != nil {
		return err
	}
	cumulativePlan, err = cumulativePlan.WithFreshSalt()
	if err != nil {
		return err
	}
	oneMore, err := r.runBoundaryOrder(
		ctx, "cumulative-overflow-refund", cumulativePlan, "1", 1, false,
	)
	if err != nil {
		return err
	}
	balance, err := r.gno.VoucherBalance(ctx, cumulativePlan.Voucher, r.cfg.GnoRecipient)
	if err != nil {
		return err
	}
	if balance != math.MaxInt64 {
		return fmt.Errorf("cumulative overflow changed the maximum Gno voucher balance")
	}

	return r.writeEvidence("amount-boundaries.json", []boundaryResult{
		overflow, maximum, oneMore,
	})
}

func (r *Runner) runBoundaryOrder(
	ctx context.Context,
	name string,
	plan evm.Plan,
	amount string,
	kind uint8,
	wantSuccess bool,
) (boundaryResult, error) {
	mintTx, err := r.evm.MintToken(ctx, plan.Token, plan.Sender, amount)
	if err != nil {
		return boundaryResult{}, err
	}
	approveTx, err := r.evm.ApproveToken(ctx, plan.Token, amount)
	if err != nil {
		return boundaryResult{}, err
	}
	before, err := r.evm.SnapshotToken(ctx, plan.Token, plan.Sender)
	if err != nil {
		return boundaryResult{}, err
	}
	recipientBefore, err := r.gno.VoucherBalance(ctx, plan.Voucher, r.cfg.GnoRecipient)
	if err != nil {
		return boundaryResult{}, err
	}
	send, err := r.evm.SendTokenOrder(
		ctx, r.current.Channels.EVM, plan, r.cfg.GnoRecipient, amount, kind,
	)
	if err != nil {
		return boundaryResult{}, err
	}
	gnoEvents, err := r.gno.WaitPacket(ctx, send.PacketHash)
	if err != nil {
		return boundaryResult{}, err
	}
	evmAck, err := r.evm.WaitAcknowledgement(
		ctx, before.Block, r.current.Channels.EVM, send.PacketHash,
	)
	if err != nil {
		return boundaryResult{}, err
	}
	success, err := matchingAcknowledgementResult(gnoEvents.Acknowledgement, evmAck.Value)
	if err != nil {
		return boundaryResult{}, err
	}
	if success != wantSuccess {
		return boundaryResult{}, fmt.Errorf("%s acknowledgement success=%t, want %t", name, success, wantSuccess)
	}
	if err := r.evm.VerifyCommitmentCleared(ctx, send.PacketHash); err != nil {
		return boundaryResult{}, err
	}
	if err := r.verifyBoundaryFailedWork(ctx); err != nil {
		return boundaryResult{}, err
	}
	senderAfter, escrowAfter, err := r.evm.TokenBalances(ctx, plan.Token, plan.Sender)
	if err != nil {
		return boundaryResult{}, err
	}
	recipientAfter, err := r.gno.VoucherBalance(ctx, plan.Voucher, r.cfg.GnoRecipient)
	if err != nil {
		return boundaryResult{}, err
	}
	deltas, err := classifyBoundaryBalances(
		success, amount,
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
		return boundaryResult{}, fmt.Errorf("%s: %w", name, err)
	}
	return boundaryResult{
		Name: name, Token: plan.Token, PacketHash: send.PacketHash,
		MintTx: mintTx, ApproveTx: approveTx, SendTx: send.Tx,
		GnoTx: gnoEvents.ReceiveTx, EVMAckTx: evmAck.Tx,
		Success: success, Deltas: deltas,
	}, nil
}

func (r *Runner) verifyBoundaryFailedWork(ctx context.Context) error {
	baseline := *r.current.FailedWork.Final
	latest, err := r.voyager.FailedWorkID(ctx, baseline, r.current.FailedWork.Repaired)
	if err != nil {
		return err
	}
	if latest != baseline {
		return fmt.Errorf("Voyager recorded new failed work during an amount boundary packet")
	}
	return nil
}

func classifyBoundaryBalances(
	success bool,
	amount string,
	before, after state.Balances,
) (state.Balances, error) {
	sender, ok := decimalDifference(before.Sender, after.Sender)
	if !ok {
		return state.Balances{}, fmt.Errorf("ERC20 sender balance increased unexpectedly")
	}
	escrow, ok := decimalDifference(after.Escrow, before.Escrow)
	if !ok {
		return state.Balances{}, fmt.Errorf("ERC20 escrow balance decreased unexpectedly")
	}
	recipientBefore, err := strconv.ParseInt(before.Recipient, 10, 64)
	if err != nil {
		return state.Balances{}, fmt.Errorf("Gno voucher balance is malformed")
	}
	recipientAfter, err := strconv.ParseInt(after.Recipient, 10, 64)
	if err != nil || recipientAfter < recipientBefore {
		return state.Balances{}, fmt.Errorf("Gno voucher balance decreased unexpectedly")
	}
	recipient := recipientAfter - recipientBefore
	if success {
		expected, err := strconv.ParseInt(amount, 10, 64)
		if err != nil || sender != amount || escrow != amount || recipient != expected {
			return state.Balances{}, fmt.Errorf("successful boundary packet has incorrect balance deltas")
		}
	} else if sender != "0" || escrow != "0" || recipient != 0 {
		return state.Balances{}, fmt.Errorf("failed boundary packet was not fully refunded")
	}
	return state.Balances{
		Sender: sender, Escrow: escrow, Recipient: strconv.FormatInt(recipient, 10),
	}, nil
}
