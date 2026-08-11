package scenario

import (
	"context"
	"fmt"
	"strconv"
	"strings"
	"time"

	"github.com/onbloc/gno-ibc/e2e/union/internal/evm"
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

func (r *Runner) submitERC20Packet(ctx context.Context, timeout time.Duration) (*state.Packet, uint64, error) {
	if r.current.Channels == nil || r.current.FailedWork.Final == nil {
		return nil, 0, fmt.Errorf("ERC20 packet requires a verified complete connection/channel state")
	}
	plan, err := r.evm.Prepare(ctx, r.current.Channels.Gno)
	if err != nil {
		return nil, 0, err
	}
	packet := &state.Packet{
		Token: strings.ToLower(r.cfg.EVMTestERC20), Sender: plan.Sender,
		Recipient: r.cfg.GnoRecipient, Amount: r.cfg.EVMTestAmount,
		Voucher: plan.Voucher, Salt: plan.Salt, Tag: plan.Tag,
		FailedWorkBaseline: *r.current.FailedWork.Final,
	}
	packet.MintTx, err = r.evm.Mint(ctx, plan.Sender)
	if err != nil {
		return nil, 0, err
	}
	packet.ApproveTx, err = r.evm.Approve(ctx)
	if err != nil {
		return nil, 0, err
	}
	snapshot, err := r.evm.Snapshot(ctx, packet.Sender)
	if err != nil {
		return nil, 0, err
	}
	recipient, err := r.gno.VoucherBalance(ctx, packet.Voucher, packet.Recipient)
	if err != nil {
		return nil, 0, err
	}
	packet.BalancesBefore = &state.Balances{
		Sender: snapshot.Sender, Escrow: snapshot.Escrow,
		Recipient: strconv.FormatInt(recipient, 10),
	}
	packet.EVMFromBlock = &snapshot.Block
	var sent evm.SendResult
	var timeoutTimestamp uint64
	if timeout == 0 {
		sent, err = r.evm.SendTokenOrder(ctx, r.current.Channels.EVM, plan, packet.Recipient, packet.Amount, 0)
	} else {
		timeoutTimestamp = uint64(time.Now().Add(timeout).UnixNano())
		sent, err = r.evm.SendTokenOrderWithTimeout(
			ctx, r.current.Channels.EVM, plan, packet.Recipient, packet.Amount, 0, timeoutTimestamp,
		)
	}
	if err != nil {
		return nil, 0, err
	}
	packet.SendTx, packet.PacketHash = sent.Tx, sent.PacketHash
	r.progressf("ERC20 packet: submitted hash=%s tx=%s", packet.PacketHash, packet.SendTx)
	return packet, timeoutTimestamp, nil
}

func (r *Runner) observePacket(ctx context.Context) (packetResult, error) {
	packet := r.packet
	gnoEvents, err := r.gno.WaitPacket(ctx, packet.PacketHash)
	if err != nil {
		return packetResult{}, err
	}
	r.progressf("scenario erc20-to-gno: Gno received packet (tx=%s); waiting for EVM acknowledgement",
		gnoEvents.ReceiveTx)
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
	r.progressf("scenario erc20-to-gno: acknowledgement success=%t (tx=%s); commitment cleared",
		success, evmAck.Tx)

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
	r.progressf("scenario erc20-to-gno: balance deltas sender=%s escrow=%s recipient=%s",
		deltas.Sender, deltas.Escrow, deltas.Recipient)

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
	packet := r.packet
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
	packet := r.packet
	packet.GnoReceiveTx = result.GnoReceiveTx
	packet.GnoWriteAckTx = result.GnoWriteAckTx
	packet.EVMAckTx = result.EVMAckTx
	packet.Outcome = result.Outcome
	packet.CommitmentCleared = true
	packet.BalanceDeltas = &result.Deltas
	packet.FailedWorkFinal = &result.FailedFinal
	if err := r.writePacketEvidence(); err != nil {
		return err
	}
	return packetOutcomeError(result.Outcome)
}

func (r *Runner) writePacketEvidence() error {
	packet := r.packet
	value := map[string]any{
		"outcome": packet.Outcome,
		"token":   packet.Token, "sender": packet.Sender,
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
