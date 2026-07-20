package unione2e

import (
	"context"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"math"
	"os"
	"os/exec"
	"strconv"
	"strings"
	"testing"
	"time"
)

type forwardFixture struct {
	Path         uint64
	OrderOperand string
	BaseToken    string
	BaseAmount   int64
	QuoteAmount  int64
	Name         string
	Symbol       string
	Decimals     uint64
}

func TestGnoToEthereumForwardInstruction(t *testing.T) {
	cfg := loadConfig()
	operand := os.Getenv("GNO_EVM_FORWARD_OPERAND_HEX")
	if operand == "" || cfg.EVMWrappedToken == "" {
		t.Skip("set GNO_EVM_FORWARD_OPERAND_HEX and EVM_WRAPPED_TOKEN")
	}
	requireGnoEthereumForwardInstruction(t, cfg, operand)
}

func TestGnoToEthereumForwardRelay(t *testing.T) {
	cfg := loadConfig()
	if !cfg.RunPacketTests {
		t.Skip("set RUN_PACKET_TESTS=1 after both live topologies are open")
	}
	operand := os.Getenv("GNO_EVM_FORWARD_OPERAND_HEX")
	sender := os.Getenv("GNO_SENDER_ADDR")
	sendCoins := os.Getenv("GNO_PACKET_SEND_COINS")
	salt := os.Getenv("GNO_PACKET_SALT_HEX")
	if operand == "" || cfg.EVMWrappedToken == "" || sender == "" || sendCoins == "" || salt == "" {
		t.Skip("set GNO_EVM_FORWARD_OPERAND_HEX, EVM_WRAPPED_TOKEN, GNO_SENDER_ADDR, GNO_PACKET_SEND_COINS, and a fresh GNO_PACKET_SALT_HEX")
	}

	requirePacketSetup(t, cfg)
	requireUnionEVMTopology(t, cfg)
	checkEVMReady(t, cfg)
	checkBeaconReady(t, cfg)
	fixture := requireGnoEthereumForwardInstruction(t, cfg, operand)
	if sendCoins != fmt.Sprintf("%d%s", fixture.BaseAmount, fixture.BaseToken) {
		t.Fatalf("GNO_PACKET_SEND_COINS = %q, want exactly %d%s", sendCoins, fixture.BaseAmount, fixture.BaseToken)
	}
	if code, err := queryEVMCode(cfg.EVMRPC, cfg.EVMWrappedToken); err != nil || len(code) != 0 {
		t.Fatalf("predicted wrapped token must not exist before INITIALIZE: code=%x err=%v", code, err)
	}

	baseline := captureVoyagerBaseline(t, cfg)
	evmBaseline, err := queryEVMBlockNumber(cfg.EVMRPC)
	if err != nil {
		t.Fatal(err)
	}
	packetSendBaseline := latestGnoEventHeight(cfg.GnoIndexer, "PacketSend", map[string]string{"source_channel_id": cfg.GnoPacketChannelID})
	senderBefore := queryGnoBalance(t, cfg, sender, fixture.BaseToken)
	recipientBefore := queryERC20Balance(t, cfg, cfg.EVMWrappedToken, cfg.EVMRecipient)

	out := transferOnGno(t, cfg, gnoTransferRequest{
		ChannelID:  cfg.GnoPacketChannelID,
		OperandHex: operand,
		SendCoins:  sendCoins,
		SaltHex:    salt,
		Version:    "0",
		Opcode:     "0",
	})
	t.Logf("Gno Forward SendRaw output:\n%s", out)

	parentSend := waitForNewGnoEvent(t, cfg, "PacketSend", map[string]string{"source_channel_id": cfg.GnoPacketChannelID}, packetSendBaseline, baseline)
	parentHash := txAttr(parentSend, "PacketSend", "packet_hash")
	if parentHash == "" {
		t.Fatalf("parent PacketSend missing packet_hash: %+v", parentSend)
	}
	if got := txAttr(parentSend, "PacketSend", "destination_channel_id"); got != "" && got != cfg.UnionPacketChannelID {
		t.Fatalf("parent destination channel = %s, want live Union channel %s", got, cfg.UnionPacketChannelID)
	}
	enqueueGnoBlock(t, cfg, parentSend.BlockHeight)

	parentRecv := waitForUnionReceive(t, cfg, parentHash, parentSend.BlockHeight, &baseline)
	parentBody := queryUnionTxBody(t, cfg, parentRecv.Hash)
	requireUnionTxEvent(t, parentBody, "wasm-packet_recv", "packet_hash", parentHash)
	if hasUnionTxEvent(parentBody, "wasm-write_ack", "packet_hash", parentHash) {
		t.Fatalf("parent acknowledgement was written synchronously in Union tx %s", parentRecv.Hash)
	}
	childHash := requireUnionTxEvent(t, parentBody, "wasm-packet_send", "packet_hash", "")
	if childHash == parentHash {
		t.Fatal("parent and child packet hashes are equal")
	}
	requireUnionTxEvent(t, parentBody, "wasm-packet_send", "packet_source_channel_id", cfg.UnionEVMChannelID)
	requireUnionTxEvent(t, parentBody, "wasm-packet_send", "packet_destination_channel_id", cfg.EVMUnionChannelID)
	childData := requireUnionTxEvent(t, parentBody, "wasm-packet_send", "packet_data", "")
	requireForwardChildPacket(t, childData, fixture)
	if txs, err := queryUnionTxs(cfg.UnionContainer, "wasm-write_ack", parentHash, 1); err != nil || len(txs) != 0 {
		t.Fatalf("parent write_ack exists before child acknowledgement: %+v err=%v", txs, err)
	}
	t.Logf("Union parent recv and child send tx %s height %d: parent=%s child=%s", parentRecv.Hash, parentRecv.Height, parentHash, childHash)

	enqueueUnionBlock(t, cfg, parentRecv.Height)
	recv := waitForEVMLog(t, cfg, baseline.Failed, cfg.EVMIBCHandler, packetRecvTopic, evmBaseline+1, topicUint32(mustUint32(t, cfg.EVMUnionChannelID)), childHash)
	ack := waitForEVMLog(t, cfg, baseline.Failed, cfg.EVMIBCHandler, writeAckTopic, evmBaseline+1, topicUint32(mustUint32(t, cfg.EVMUnionChannelID)), childHash)
	if recv.TransactionHash != ack.TransactionHash {
		t.Fatalf("EVM PacketRecv tx %s differs from WriteAck tx %s", recv.TransactionHash, ack.TransactionHash)
	}
	receipt, err := queryEVMReceipt(cfg.EVMRPC, recv.TransactionHash)
	if err != nil || receipt.Status != "0x1" {
		t.Fatalf("EVM receipt status = %q: %v", receipt.Status, err)
	}
	ackBytes, err := abiBytes(mustDecodeHex(t, ack.Data), 0)
	if err != nil {
		t.Fatalf("decode EVM WriteAck: %v", err)
	}
	if tag, err := abiUint(ackBytes, 0); err != nil || tag != 1 {
		t.Fatalf("EVM acknowledgement tag = %d, want success: %v", tag, err)
	}
	block, err := strconv.ParseUint(strings.TrimPrefix(ack.BlockNumber, "0x"), 16, 64)
	if err != nil {
		t.Fatal(err)
	}
	if logs, err := queryEVMLogs(cfg.EVMRPC, cfg.EVMIBCHandler, evmBaseline+1, packetRecvTopic, topicUint32(mustUint32(t, cfg.EVMUnionChannelID)), childHash); err != nil || len(logs) != 1 {
		t.Fatalf("EVM PacketRecv count = %d, want 1: %v", len(logs), err)
	}
	if logs, err := queryEVMLogs(cfg.EVMRPC, cfg.EVMIBCHandler, evmBaseline+1, writeAckTopic, topicUint32(mustUint32(t, cfg.EVMUnionChannelID)), childHash); err != nil || len(logs) != 1 {
		t.Fatalf("EVM WriteAck count = %d, want 1: %v", len(logs), err)
	}
	if logs, err := queryEVMLogs(cfg.EVMRPC, cfg.EVMZKGM, evmBaseline+1, createWrappedTokenTopic, topicUint32(mustUint32(t, cfg.EVMUnionChannelID)), topicAddress(cfg.EVMWrappedToken)); err != nil || len(logs) != 1 {
		t.Fatalf("EVM CreateWrappedToken count = %d, want 1: %v", len(logs), err)
	}
	if code, err := queryEVMCode(cfg.EVMRPC, cfg.EVMWrappedToken); err != nil || len(code) == 0 {
		t.Fatalf("wrapped token code is empty: %v", err)
	}
	if got := queryERC20String(t, cfg, cfg.EVMWrappedToken, "0x06fdde03"); got != fixture.Name {
		t.Fatalf("wrapped token name = %q, want %q", got, fixture.Name)
	}
	if got := queryERC20String(t, cfg, cfg.EVMWrappedToken, "0x95d89b41"); got != fixture.Symbol {
		t.Fatalf("wrapped token symbol = %q, want %q", got, fixture.Symbol)
	}
	if got := queryERC20Uint(t, cfg, cfg.EVMWrappedToken, "0x313ce567"); got != fixture.Decimals {
		t.Fatalf("wrapped token decimals = %d, want %d", got, fixture.Decimals)
	}
	if got := queryERC20Uint(t, cfg, cfg.EVMWrappedToken, "0x18160ddd"); got != uint64(fixture.QuoteAmount) {
		t.Fatalf("wrapped token total supply = %d, want %d", got, fixture.QuoteAmount)
	}
	if delta := queryERC20Balance(t, cfg, cfg.EVMWrappedToken, cfg.EVMRecipient) - recipientBefore; delta != fixture.QuoteAmount {
		t.Fatalf("recipient wrapped-token delta = %d, want %d", delta, fixture.QuoteAmount)
	}

	enqueueEVMBlock(t, cfg, block)
	childAck := waitForUnionEvent(t, cfg, "wasm-packet_ack", childHash)
	parentWrite := waitForUnionEvent(t, cfg, "wasm-write_ack", parentHash)
	if childAck.Hash != parentWrite.Hash {
		t.Fatalf("Union child packet_ack tx %s differs from parent write_ack tx %s", childAck.Hash, parentWrite.Hash)
	}
	requireOneUnionEvent(t, cfg, "wasm-packet_ack", childHash)
	requireOneUnionEvent(t, cfg, "wasm-write_ack", parentHash)
	if err := requireUnionEventOrder(cfg.UnionContainer, childAck.Hash, "wasm-packet_ack", "wasm-write_ack"); err != nil {
		t.Fatal(err)
	}
	requireUnionPacketCommitmentRemoved(t, cfg, childHash)

	enqueueUnionBlock(t, cfg, parentWrite.Height)
	parentAck := waitForNewGnoEvent(t, cfg, "PacketAck", map[string]string{"packet_hash": parentHash}, parentSend.BlockHeight, baseline)
	if parentAck.BlockHeight <= parentSend.BlockHeight {
		t.Fatalf("Gno parent PacketAck height %d must be after PacketSend height %d", parentAck.BlockHeight, parentSend.BlockHeight)
	}
	if acks, err := queryGnoEvents(cfg.GnoIndexer, "PacketAck", map[string]string{"packet_hash": parentHash}); err != nil || len(acks) != 1 {
		t.Fatalf("Gno parent PacketAck count = %d, want 1: %v", len(acks), err)
	}
	if after := queryGnoBalance(t, cfg, sender, fixture.BaseToken); after > senderBefore-fixture.BaseAmount {
		t.Fatalf("Gno sender balance did not decrease by sent amount: before=%d after=%d sent=%d%s", senderBefore, after, fixture.BaseAmount, fixture.BaseToken)
	}
	requireNoNewVoyagerFailed(t, cfg, baseline)
	done := voyagerRowsAfter(t, cfg, "done", baseline.Done)
	if !strings.Contains(done, parentHash) || !strings.Contains(done, childHash) {
		t.Fatalf("Voyager done rows do not contain both parent and child hashes:\n%s", done)
	}
	t.Logf("full cycle parent=%s Gno send=%s/%d Union recv+child=%s/%d child=%s EVM recv+ack=%s/%d Union child ack+parent write=%s/%d Gno ack=%s/%d", parentHash, parentSend.Hash, parentSend.BlockHeight, parentRecv.Hash, parentRecv.Height, childHash, recv.TransactionHash, block, childAck.Hash, childAck.Height, parentAck.Hash, parentAck.BlockHeight)
}

func requireGnoEthereumForwardInstruction(t *testing.T, cfg config, operand string) forwardFixture {
	t.Helper()
	forward := castDecode(t, "f()(uint256,uint64,uint64,(uint8,uint8,bytes))", operand)
	path := mustNumber(t, forward[0])
	wantPath := uint64(mustUint32(t, cfg.UnionPacketChannelID)) | uint64(mustUint32(t, cfg.UnionEVMChannelID))<<32
	if path != wantPath {
		t.Fatalf("Forward path = %d, want [%s,%s] encoded as %d", path, cfg.UnionPacketChannelID, cfg.UnionEVMChannelID, wantPath)
	}
	if mustNumber(t, forward[1]) != 0 {
		t.Fatalf("Forward timeout height = %v, want 0", forward[1])
	}
	timeout := mustNumber(t, forward[2])
	if timeout <= uint64(time.Now().Add(10*time.Minute).UnixNano()) {
		t.Fatalf("Forward timeout timestamp %d is not at least 10 minutes in the future", timeout)
	}
	instruction := mustTuple(t, forward[3])
	if mustNumber(t, instruction[0]) != 2 || mustNumber(t, instruction[1]) != 3 {
		t.Fatalf("forwarded instruction version/opcode = %v/%v, want 2/3", instruction[0], instruction[1])
	}
	orderOperand := instruction[2].(string)
	order := castDecode(t, "f()(bytes,bytes,bytes,uint256,bytes,uint256,uint8,bytes)", orderOperand)
	sender := os.Getenv("GNO_SENDER_ADDR")
	if sender == "" {
		t.Skip("set GNO_SENDER_ADDR to validate TokenOrder sender and balance")
	}
	baseToken := string(mustDecodeHex(t, order[2].(string)))
	baseAmount := mustNumber(t, order[3])
	quoteAmount := mustNumber(t, order[5])
	if baseAmount > math.MaxInt64 || quoteAmount > math.MaxInt64 {
		t.Fatalf("TokenOrder amount exceeds int64 test balance support: base=%d quote=%d", baseAmount, quoteAmount)
	}
	if string(mustDecodeHex(t, order[0].(string))) != sender ||
		!strings.EqualFold(order[1].(string), cfg.EVMRecipient) ||
		baseToken == "" || baseAmount == 0 || quoteAmount != baseAmount ||
		!strings.EqualFold(order[4].(string), cfg.EVMWrappedToken) || mustNumber(t, order[6]) != 0 {
		t.Fatalf("forwarded TokenOrderV2 does not match live fixture: %v", order[:7])
	}
	metadata := castDecode(t, "f()(bytes,bytes)", order[7].(string))
	implementation, initializer := metadata[0].(string), metadata[1].(string)
	if !strings.EqualFold(implementation, cfg.EVMERC20Impl) {
		t.Fatalf("metadata implementation = %s, want %s", implementation, cfg.EVMERC20Impl)
	}
	if !strings.HasPrefix(strings.ToLower(initializer), "0x8420ce99") {
		t.Fatalf("initializer selector = %.10s, want 0x8420ce99", initializer)
	}
	init := castDecodeInput(t, "initialize(address,address,string,string,uint8)()", initializer[10:])
	if !strings.EqualFold(init[0].(string), cfg.EVMManager) || !strings.EqualFold(init[1].(string), cfg.EVMZKGM) || init[2].(string) == "" || init[3].(string) == "" {
		t.Fatalf("initializer does not match live EVM contracts: %v", init)
	}
	predicted := predictWrappedTokenV2(t, cfg, path, baseToken, implementation, initializer)
	if !strings.EqualFold(predicted, cfg.EVMWrappedToken) {
		t.Fatalf("predictWrappedTokenV2 = %s, want %s", predicted, cfg.EVMWrappedToken)
	}
	return forwardFixture{
		Path: path, OrderOperand: orderOperand, BaseToken: baseToken,
		BaseAmount: int64(baseAmount), QuoteAmount: int64(quoteAmount), Name: init[2].(string),
		Symbol: init[3].(string), Decimals: mustNumber(t, init[4]),
	}
}

func requireForwardChildPacket(t *testing.T, packetData string, fixture forwardFixture) {
	t.Helper()
	packet := castDecode(t, "f()(bytes32,uint256,(uint8,uint8,bytes))", packetData)
	if mustNumber(t, packet[1]) != fixture.Path {
		t.Fatalf("child packet path = %v, want %d", packet[1], fixture.Path)
	}
	instruction := mustTuple(t, packet[2])
	if mustNumber(t, instruction[0]) != 2 || mustNumber(t, instruction[1]) != 3 || !strings.EqualFold(instruction[2].(string), fixture.OrderOperand) {
		t.Fatalf("child instruction differs from forwarded TokenOrderV2: %v", instruction[:2])
	}
	salt := mustDecodeHex(t, packet[0].(string))
	magic, _ := hex.DecodeString("c0de00000000000000000000000000000000000000000000000000000000babe")
	for i := range magic {
		if salt[i]&magic[i] != magic[i] {
			t.Fatalf("child packet salt is not forward-tinted: %x", salt)
		}
	}
}

func predictWrappedTokenV2(t *testing.T, cfg config, path uint64, baseToken, implementation, initializer string) string {
	t.Helper()
	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()
	baseHex := "0x" + hex.EncodeToString([]byte(baseToken))
	out, err := exec.CommandContext(ctx, "cast", "call", cfg.EVMZKGM,
		"predictWrappedTokenV2(uint256,uint32,bytes,(bytes,bytes))(address,bytes32)",
		strconv.FormatUint(path, 10), cfg.EVMUnionChannelID, baseHex,
		fmt.Sprintf("(%s,%s)", implementation, initializer), "--rpc-url", cfg.EVMRPC).CombinedOutput()
	if err != nil {
		t.Fatalf("predictWrappedTokenV2: %v\n%s", err, out)
	}
	fields := strings.Fields(string(out))
	if len(fields) == 0 {
		t.Fatalf("predictWrappedTokenV2 returned no address: %s", out)
	}
	return fields[0]
}

func mustTuple(t *testing.T, value any) []any {
	t.Helper()
	tuple, ok := value.([]any)
	if !ok {
		t.Fatalf("expected tuple, got %T", value)
	}
	return tuple
}

func queryUnionTxBody(t *testing.T, cfg config, hash string) []byte {
	t.Helper()
	out, err := dockerExec(cfg.UnionContainer, "uniond", "query", "tx", hash, "--node", "tcp://localhost:26657", "-o", "json")
	if err != nil {
		t.Fatalf("query Union tx %s: %v\n%s", hash, err, out)
	}
	return []byte(out)
}

func requireUnionTxEvent(t *testing.T, body []byte, eventType, key, want string) string {
	t.Helper()
	values := unionTxEventValues(t, body, eventType, key)
	if len(values) != 1 {
		t.Fatalf("Union tx %s %s count = %d, want 1", eventType, key, len(values))
	}
	if want != "" && values[0] != want {
		t.Fatalf("Union tx %s %s = %s, want %s", eventType, key, values[0], want)
	}
	return values[0]
}

func hasUnionTxEvent(body []byte, eventType, key, value string) bool {
	var tx struct {
		Events []struct {
			Type       string                        `json:"type"`
			Attributes []struct{ Key, Value string } `json:"attributes"`
		} `json:"events"`
	}
	if json.Unmarshal(body, &tx) != nil {
		return false
	}
	for _, event := range tx.Events {
		if event.Type != eventType {
			continue
		}
		for _, attr := range event.Attributes {
			if attr.Key == key && attr.Value == value {
				return true
			}
		}
	}
	return false
}

func unionTxEventValues(t *testing.T, body []byte, eventType, key string) []string {
	t.Helper()
	var tx struct {
		Events []struct {
			Type       string                        `json:"type"`
			Attributes []struct{ Key, Value string } `json:"attributes"`
		} `json:"events"`
	}
	if err := json.Unmarshal(body, &tx); err != nil {
		t.Fatalf("decode Union tx events: %v", err)
	}
	var values []string
	for _, event := range tx.Events {
		if event.Type != eventType {
			continue
		}
		for _, attr := range event.Attributes {
			if attr.Key == key {
				values = append(values, attr.Value)
			}
		}
	}
	return values
}
