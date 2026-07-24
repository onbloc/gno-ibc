package scenario

import (
	"context"
	"fmt"
	"strconv"
	"strings"

	"github.com/onbloc/gno-ibc/e2e/union/internal/state"
)

type packetResult struct {
	GnoReceiveTx  string
	GnoWriteAckTx string
	EVMAckTx      string
	Outcome       state.PacketOutcome
	Deltas        state.Balances
	FailedFinal   int64
}

func (r *Runner) observePacket(ctx context.Context) (packetResult, error) {
	if r.current.Phase != state.PhasePacketSendSubmitted {
		return packetResult{}, fmt.Errorf("unsupported packet phase: %s", r.current.Phase)
	}

	packet := r.current.Packet
	gnoEvents, err := r.gno.WaitPacket(ctx, packet.PacketHash)
	if err != nil {
		return packetResult{}, err
	}
	if err := r.verifyPacketFailedWork(ctx); err != nil {
		return packetResult{}, err
	}

	evmAck, err := r.evm.WaitAcknowledgement(
		ctx, *packet.EVMFromBlock, r.current.Channels.EVM, packet.PacketHash,
	)
	if err != nil {
		return packetResult{}, err
	}

	success, err := matchingAcknowledgementResult(gnoEvents.Acknowledgement, evmAck.Value)
	if err != nil {
		return packetResult{}, err
	}
	if err := r.evm.VerifyCommitmentCleared(ctx, packet.PacketHash); err != nil {
		return packetResult{}, err
	}

	sender, escrow, err := r.evm.Balances(ctx, packet.Sender)
	if err != nil {
		return packetResult{}, err
	}

	recipient, err := r.gno.VoucherBalance(ctx, packet.Voucher, packet.Recipient)
	if err != nil {
		return packetResult{}, err
	}

	deltas, err := classifyPacketBalances(
		success, packet.Amount, packet.BalancesBefore,
		&state.Balances{
			Sender: sender, Escrow: escrow, Recipient: strconv.FormatInt(recipient, 10),
		},
	)
	if err != nil {
		return packetResult{}, err
	}

	if err := r.verifyPacketFailedWork(ctx); err != nil {
		return packetResult{}, err
	}

	outcome := state.PacketOutcomeFailure
	if success {
		outcome = state.PacketOutcomeSuccess
	}

	return packetResult{
		GnoReceiveTx: gnoEvents.ReceiveTx, GnoWriteAckTx: gnoEvents.WriteAckTx,
		EVMAckTx: evmAck.Tx, Outcome: outcome, Deltas: deltas,
		FailedFinal: packet.FailedWorkBaseline,
	}, nil
}

func (r *Runner) verifyPacketFailedWork(ctx context.Context) error {
	packet := r.current.Packet
	latest, err := r.voyager.FailedWorkID(
		ctx, packet.FailedWorkBaseline, r.current.FailedWork.Repaired,
	)
	if err != nil {
		return err
	}
	if latest != packet.FailedWorkBaseline {
		return fmt.Errorf("Voyager recorded new failed work during the ERC20 packet")
	}
	return nil
}

func (r *Runner) finishPacket(result packetResult) error {
	packet := r.current.Packet
	packet.GnoReceiveTx = result.GnoReceiveTx
	packet.GnoWriteAckTx = result.GnoWriteAckTx
	packet.EVMAckTx = result.EVMAckTx
	packet.Outcome = result.Outcome
	packet.CommitmentCleared = true
	packet.BalanceDeltas = &result.Deltas
	packet.FailedWorkFinal = &result.FailedFinal
	r.current.Phase = state.PhasePacketComplete
	packet.Phase = state.PhasePacketComplete
	if err := r.writePacketEvidence(); err != nil {
		return err
	}
	if err := state.Save(r.cfg.StateFile, r.current); err != nil {
		return err
	}
	return packetOutcomeError(result.Outcome)
}

func (r *Runner) writePacketEvidence() error {
	packet := r.current.Packet
	value := map[string]any{
		"phase": packet.Phase, "outcome": packet.Outcome,
		"token": packet.Token, "sender": packet.Sender,
		"escrow":    strings.ToLower(r.cfg.EVMZKGMContract),
		"recipient": packet.Recipient, "voucher": packet.Voucher,
		"packet_hash": packet.PacketHash, "commitment_cleared": packet.CommitmentCleared,
		"transactions": map[string]string{
			"mint": packet.MintTx, "approve": packet.ApproveTx, "send": packet.SendTx,
			"gno_receive": packet.GnoReceiveTx, "gno_write_ack": packet.GnoWriteAckTx,
			"evm_ack": packet.EVMAckTx,
		},
		"channels": map[string]int64{
			"evm": r.current.Channels.EVM, "gno": r.current.Channels.Gno,
		},
		"amounts": map[string]string{
			"sent_18_decimals":           packet.Amount,
			"sender_delta":               packet.BalanceDeltas.Sender,
			"escrow_delta":               packet.BalanceDeltas.Escrow,
			"recipient_delta_6_decimals": packet.BalanceDeltas.Recipient,
		},
		"failed_work": map[string]int64{
			"baseline": packet.FailedWorkBaseline, "final": *packet.FailedWorkFinal,
		},
	}
	return r.writeEvidence("packet-summary.json", value)
}
