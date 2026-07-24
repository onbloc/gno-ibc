package scenario

import (
	"encoding/hex"
	"fmt"
	"math/big"
	"strconv"
	"strings"

	"github.com/onbloc/gno-ibc/e2e/union/internal/config"
	"github.com/onbloc/gno-ibc/e2e/union/internal/state"
)

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

func hexText(value string) string {
	return "0x" + hex.EncodeToString([]byte(value))
}

func joinIDs(ids []int64) string {
	values := make([]string, len(ids))
	for i, id := range ids {
		values[i] = strconv.FormatInt(id, 10)
	}
	return strings.Join(values, ",")
}
