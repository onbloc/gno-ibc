package scenario

import (
	"context"
	"fmt"
	"strconv"
	"strings"

	"github.com/onbloc/gno-ibc/e2e/union/internal/state"
)

// runERC20ToGnoScenario executes the durable packet transitions, then records
// either the successful S3 result or the verified S4 refund before returning.
// A submitting checkpoint has no durable transaction locator; balances and
// allowances cannot identify that exact write, so resume fails as ambiguous.
func (r *Runner) runERC20ToGnoScenario(ctx context.Context) error {
	if r.current.Phase == state.PhasePacketComplete {
		return packetOutcomeError(r.current.Packet.Outcome)
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
	result, err := r.observePacket(ctx)
	if err != nil {
		return err
	}
	return r.finishPacket(result)
}

func (r *Runner) mintERC20(ctx context.Context) error {
	switch r.current.Phase {
	case state.PhaseComplete:
		if r.current.Packet != nil || r.current.Channels == nil || r.current.FailedWork.Final == nil {
			return fmt.Errorf("ERC20 packet requires a verified complete connection/channel state")
		}
		plan, err := r.evm.Prepare(ctx, r.current.Channels.Gno)
		if err != nil {
			return err
		}
		r.current.Packet = &state.Packet{
			Token: strings.ToLower(r.cfg.EVMTestERC20), Sender: plan.Sender,
			Recipient: r.cfg.GnoRecipient, Amount: r.cfg.EVMTestAmount,
			Voucher: plan.Voucher, Salt: plan.Salt, Tag: plan.Tag,
			FailedWorkBaseline: *r.current.FailedWork.Final,
		}
		if err := r.savePacketPhase(state.PhasePacketMintSubmitting); err != nil {
			return err
		}
		tx, err := r.evm.Mint(ctx, plan.Sender)
		if err != nil {
			return err
		}
		r.current.Packet.MintTx = tx
		return r.savePacketPhase(state.PhasePacketMintSubmitted)
	case state.PhasePacketMintSubmitting:
		return fmt.Errorf("ERC20 mint submission is ambiguous; refusing to mint again")
	default:
		return nil
	}
}

func (r *Runner) approveERC20(ctx context.Context) error {
	switch r.current.Phase {
	case state.PhasePacketMintSubmitted:
		if err := r.savePacketPhase(state.PhasePacketApproveSubmitting); err != nil {
			return err
		}
		tx, err := r.evm.Approve(ctx)
		if err != nil {
			return err
		}
		r.current.Packet.ApproveTx = tx
		return r.savePacketPhase(state.PhasePacketApproveSubmitted)
	case state.PhasePacketApproveSubmitting:
		return fmt.Errorf("ERC20 approval submission is ambiguous; refusing to approve again")
	default:
		return nil
	}
}

func (r *Runner) sendTokenOrder(ctx context.Context) error {
	switch r.current.Phase {
	case state.PhasePacketApproveSubmitted:
		packet := r.current.Packet
		snapshot, err := r.evm.Snapshot(ctx, packet.Sender)
		if err != nil {
			return err
		}
		recipient, err := r.gno.VoucherBalance(ctx, packet.Voucher, packet.Recipient)
		if err != nil {
			return err
		}
		packet.BalancesBefore = &state.Balances{
			Sender: snapshot.Sender, Escrow: snapshot.Escrow,
			Recipient: strconv.FormatInt(recipient, 10),
		}
		packet.EVMFromBlock = &snapshot.Block
		if err := r.savePacketPhase(state.PhasePacketSendSubmitting); err != nil {
			return err
		}
		result, err := r.evm.Send(
			ctx, r.current.Channels.EVM, packet.Sender, packet.Recipient,
			packet.Voucher, packet.Salt, packet.Tag,
		)
		if err != nil {
			return err
		}
		packet.SendTx, packet.PacketHash = result.Tx, result.PacketHash
		return r.savePacketPhase(state.PhasePacketSendSubmitted)
	case state.PhasePacketSendSubmitting:
		return fmt.Errorf("ERC20 packet submission is ambiguous; refusing to send again")
	default:
		return nil
	}
}

func (r *Runner) savePacketPhase(phase state.Phase) error {
	r.current.Phase = phase
	r.current.Packet.Phase = phase
	return state.Save(r.cfg.StateFile, r.current)
}
