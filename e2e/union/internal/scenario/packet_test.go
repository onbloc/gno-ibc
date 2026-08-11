package scenario

import (
	"encoding/hex"
	"strings"
	"testing"

	"github.com/onbloc/gno-ibc/e2e/union/internal/state"
)

func TestAcknowledgementClassification(t *testing.T) {
	success := encodedAcknowledgement(1, []byte{0xab, 0xcd})
	failure := encodedAcknowledgement(0, nil)
	if got, err := matchingAcknowledgementResult(success, success); err != nil || !got {
		t.Fatalf("success = %v, %v", got, err)
	}
	if got, err := matchingAcknowledgementResult(failure, failure); err != nil || got {
		t.Fatalf("failure = %v, %v", got, err)
	}
	if _, err := matchingAcknowledgementResult(success, failure); err == nil {
		t.Fatal("mismatch unexpectedly passed")
	}
}

func encodedAcknowledgement(tag byte, payload []byte) string {
	tagWord, offsetWord, lengthWord := make([]byte, 32), make([]byte, 32), make([]byte, 32)
	tagWord[31], offsetWord[31], lengthWord[31] = tag, 64, byte(len(payload))
	padded := make([]byte, (len(payload)+31)/32*32)
	copy(padded, payload)
	return "0x" + hex.EncodeToString(append(append(append(tagWord, offsetWord...), lengthWord...), padded...))
}

func TestPacketBalanceClassification(t *testing.T) {
	before := state.Balances{Sender: "2000000000000", Escrow: "0", Recipient: "4"}
	after := state.Balances{Sender: "1000000000000", Escrow: "1000000000000", Recipient: "5"}
	if _, err := classifyPacketBalances(true, "1000000000000", &before, &after); err != nil {
		t.Fatal(err)
	}
	after.Escrow = "999999999999"
	if _, err := classifyPacketBalances(true, "1000000000000", &before, &after); err == nil || !strings.Contains(err.Error(), "balance deltas") {
		t.Fatalf("error = %v", err)
	}
}
