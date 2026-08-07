package scenario

import (
	"bytes"
	"encoding/base64"
	"encoding/hex"
	"os"
	"path/filepath"
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

func TestPacketResultDoesNotModifyTopologyCheckpoint(t *testing.T) {
	cfg := testConfig(t)
	if err := state.PrepareArtifacts(
		filepath.Dir(filepath.Dir(cfg.ScriptDir)), cfg.ScriptDir, cfg.ArtifactDir, cfg.StateFile,
	); err != nil {
		t.Fatal(err)
	}
	topology := completedState(cfg, 7)
	if err := state.Save(cfg.StateFile, topology); err != nil {
		t.Fatal(err)
	}
	before, err := os.ReadFile(cfg.StateFile)
	if err != nil {
		t.Fatal(err)
	}
	block := uint64(10)
	runner := &Runner{cfg: cfg, current: topology, packet: &state.Packet{
		Token: cfg.EVMTestERC20, Sender: "0x7777777777777777777777777777777777777777",
		Recipient: cfg.GnoRecipient, Amount: cfg.EVMTestAmount, Voucher: "ibc/voucher",
		MintTx: "mint", ApproveTx: "approve", SendTx: "send", PacketHash: "packet",
		BalancesBefore: &state.Balances{}, EVMFromBlock: &block, FailedWorkBaseline: 7,
	}}
	tx := base64.StdEncoding.EncodeToString(make([]byte, 32))
	if err := runner.finishPacket(packetResult{
		GnoReceiveTx: tx, GnoWriteAckTx: tx, EVMAckTx: "ack",
		Outcome:     state.PacketOutcomeSuccess,
		Deltas:      state.Balances{Sender: cfg.EVMTestAmount, Escrow: cfg.EVMTestAmount, Recipient: "1"},
		FailedFinal: 7,
	}); err != nil {
		t.Fatal(err)
	}
	after, err := os.ReadFile(cfg.StateFile)
	if err != nil {
		t.Fatal(err)
	}
	if !bytes.Equal(before, after) {
		t.Fatal("packet result modified topology checkpoint")
	}
}
