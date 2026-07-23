package scenario

import (
	"context"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"math/big"
	"path/filepath"
	"strconv"
	"strings"

	"github.com/onbloc/gno-ibc/e2e/union/internal/config"
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

func packetOutcomeError(outcome state.PacketOutcome) error {
	switch outcome {
	case state.PacketOutcomeSuccess:
		return nil
	case state.PacketOutcomeFailure:
		return fmt.Errorf("packet failure acknowledgement and escrow refund verified")
	default:
		return fmt.Errorf("completed packet has invalid outcome")
	}
}

func matchingAcknowledgementResult(gno, evm string) (bool, error) {
	gnoSuccess, err := acknowledgementSuccess(gno)
	if err != nil {
		return false, fmt.Errorf("malformed Gno acknowledgement")
	}
	evmSuccess, err := acknowledgementSuccess(evm)
	if err != nil {
		return false, fmt.Errorf("malformed EVM acknowledgement")
	}
	if gnoSuccess != evmSuccess {
		return false, fmt.Errorf("Gno and EVM acknowledgement results differ")
	}
	return gnoSuccess, nil
}

func acknowledgementSuccess(value string) (bool, error) {
	value = strings.TrimPrefix(value, "0x")
	if value == "" || len(value)%2 != 0 {
		return false, fmt.Errorf("malformed acknowledgement")
	}
	decoded, err := hex.DecodeString(value)
	if err != nil || len(decoded) < 96 || len(decoded)%32 != 0 {
		return false, fmt.Errorf("malformed acknowledgement")
	}
	for _, part := range [][]byte{decoded[:31], decoded[32:63]} {
		for _, value := range part {
			if value != 0 {
				return false, fmt.Errorf("malformed acknowledgement")
			}
		}
	}
	if decoded[63] != 64 {
		return false, fmt.Errorf("malformed acknowledgement")
	}
	length := new(big.Int).SetBytes(decoded[64:96])
	available := big.NewInt(int64(len(decoded) - 96))
	if !length.IsInt64() || length.Cmp(available) > 0 {
		return false, fmt.Errorf("malformed acknowledgement")
	}
	payloadLength := int(length.Int64())
	paddedLength := (payloadLength + 31) / 32 * 32
	if len(decoded) != 96+paddedLength {
		return false, fmt.Errorf("malformed acknowledgement")
	}
	for _, value := range decoded[96+payloadLength:] {
		if value != 0 {
			return false, fmt.Errorf("malformed acknowledgement")
		}
	}
	switch decoded[31] {
	case 0:
		return false, nil
	case 1:
		return true, nil
	default:
		return false, fmt.Errorf("malformed acknowledgement")
	}
}

func classifyPacketBalances(
	success bool,
	amount string,
	before, after *state.Balances,
) (state.Balances, error) {
	sender, ok := decimalDifference(before.Sender, after.Sender)
	if !ok {
		return state.Balances{}, fmt.Errorf("ERC20 sender balance increased unexpectedly")
	}
	escrow, ok := decimalDifference(after.Escrow, before.Escrow)
	if !ok {
		return state.Balances{}, fmt.Errorf("ERC20 escrow balance decreased unexpectedly")
	}
	beforeRecipient, err := strconv.ParseInt(before.Recipient, 10, 64)
	if err != nil {
		return state.Balances{}, fmt.Errorf("saved packet recipient balance is malformed")
	}
	afterRecipient, err := strconv.ParseInt(after.Recipient, 10, 64)
	if err != nil || afterRecipient < beforeRecipient {
		return state.Balances{}, fmt.Errorf("Gno voucher balance decreased unexpectedly")
	}
	recipient := afterRecipient - beforeRecipient
	if success {
		expected, err := config.PacketLedgerAmount(amount)
		if err != nil {
			return state.Balances{}, err
		}
		if sender != amount || escrow != amount || recipient != expected {
			return state.Balances{}, fmt.Errorf("packet balance deltas do not match the sent amount")
		}
	} else if sender != "0" || escrow != "0" || recipient != 0 {
		return state.Balances{}, fmt.Errorf("packet failure did not refund the escrowed ERC20")
	}
	return state.Balances{
		Sender: sender, Escrow: escrow, Recipient: strconv.FormatInt(recipient, 10),
	}, nil
}

func decimalDifference(left, right string) (string, bool) {
	a, okA := new(big.Int).SetString(left, 10)
	b, okB := new(big.Int).SetString(right, 10)
	if !okA || !okB || a.Sign() < 0 || b.Sign() < 0 || a.Cmp(b) < 0 {
		return "", false
	}
	return new(big.Int).Sub(a, b).String(), true
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
	data, err := json.MarshalIndent(value, "", "  ")
	if err != nil {
		return fmt.Errorf("cannot encode packet artifact")
	}
	data = append(data, '\n')
	if r.containsSecret(data) {
		return fmt.Errorf("packet artifact secret scan failed")
	}
	return state.SaveArtifact(filepath.Join(r.cfg.ArtifactDir, "packet-summary.json"), data)
}
