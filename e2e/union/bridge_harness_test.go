package unione2e

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"math/big"
	"os/exec"
	"strconv"
	"strings"
	"testing"
	"time"
)

const (
	evmPacketSendTopic = "0x635b5d234fe7abddfb29b6c8498780a3175c9002c537f20a3d1bf9d0e625b5fe"
	evmPacketAckTopic  = "0x41d958a7d93b50b1f7541c6fc345d0c4657b1e83497baa562c866611ac1f69bb"
)

type bridgeHarness struct {
	cfg       config
	evmSender string
}

type tokenMetadata struct {
	name     string
	symbol   string
	decimals uint8
}

type tokenOrder struct {
	Sender, Receiver, BaseToken, QuoteToken, Metadata string
	Amount                                            string
	Kind                                              uint8
}

const (
	tokenOrderKindInitialize uint8 = iota
	tokenOrderKindEscrow
	tokenOrderKindUnescrow
)

func newBridgeHarness(t *testing.T) *bridgeHarness {
	t.Helper()
	cfg := loadConfig()
	if !cfg.RunPackets {
		t.Skip("set RUN_PACKET_TESTS=1 after the direct Gno-EVM topology is open")
	}
	if err := cfg.validatePacket(); err != nil {
		t.Fatal(err)
	}

	checkGnoIndexerReady(t, cfg.Gno)
	checkUnionReady(t, cfg.Union)
	checkEVMReady(t, cfg.EVM)
	checkBeaconReady(t, cfg.EVM)

	return &bridgeHarness{
		cfg:       cfg,
		evmSender: mustCommand(t, "cast", "wallet", "address", "--private-key", cfg.EVM.PrivateKey),
	}
}

func evmMetadata(t *testing.T, cfg evmConfig, metadata tokenMetadata) string {
	t.Helper()
	initializer := mustCommand(t, "cast", "calldata", "initialize(address,address,string,string,uint8)", cfg.Manager, cfg.ZKGM, metadata.name, metadata.symbol, strconv.Itoa(int(metadata.decimals)))
	return encodeMetadata(t, cfg.ERC20Impl, initializer)
}

func gnoMetadata(t *testing.T, metadata tokenMetadata) string {
	t.Helper()
	initializer := mustCommand(t, "cast", "abi-encode", "f(string,string,uint8)", metadata.name, metadata.symbol, strconv.Itoa(int(metadata.decimals)))
	return encodeMetadata(t, asciiHex("grc20"), initializer)
}

func encodeMetadata(t *testing.T, implementation, initializer string) string {
	t.Helper()
	return mustCommand(t, "cast", "abi-encode", "f(bytes,bytes)", implementation, initializer)
}

func encodeTokenOrder(t *testing.T, order tokenOrder) string {
	t.Helper()
	return mustCommand(t, "cast", "abi-encode", "f(bytes,bytes,bytes,uint256,bytes,uint256,uint8,bytes)",
		order.Sender, order.Receiver, order.BaseToken, order.Amount, order.QuoteToken,
		order.Amount, strconv.Itoa(int(order.Kind)), order.Metadata)
}

func TestEncodeTokenOrderIncludesKindAndUint256Amount(t *testing.T) {
	const amount = "9223372036854775808"
	encoded := encodeTokenOrder(t, tokenOrder{
		Sender: "0x01", Receiver: "0x02", BaseToken: "0x03", QuoteToken: "0x04", Metadata: "0x05",
		Amount: amount, Kind: tokenOrderKindUnescrow,
	})
	var decoded []json.RawMessage
	out := mustCommand(t, "cast", "decode-abi", "f()(bytes,bytes,bytes,uint256,bytes,uint256,uint8,bytes)", encoded, "--json")
	if err := json.Unmarshal([]byte(out), &decoded); err != nil {
		t.Fatal(err)
	}
	if len(decoded) != 8 || string(decoded[3]) != amount || string(decoded[5]) != amount || string(decoded[6]) != "2" {
		t.Fatalf("decoded TokenOrder = %v", decoded)
	}
}

func predictEVMWrappedToken(t *testing.T, cfg evmConfig, channel string, base []byte, metadata string) string {
	t.Helper()
	decoded := castDecode(t, "f()(bytes,bytes)", metadata)
	out := mustCommand(t, "cast", "call", cfg.ZKGM,
		"predictWrappedTokenV2(uint256,uint32,bytes,(bytes,bytes))(address,bytes32)", "0", channel, hexBytes(base),
		fmt.Sprintf("(%s,%s)", decoded[0], decoded[1]), "--rpc-url", cfg.RPC)
	return strings.Fields(out)[0]
}

func predictGnoWrappedToken(t *testing.T, channel string, base []byte, metadata string) string {
	t.Helper()
	image := mustCommand(t, "cast", "keccak", metadata)
	encoded := mustCommand(t, "cast", "abi-encode", "f(uint256,uint32,bytes,uint256)", "0", channel, hexBytes(base), image)
	hash := strings.TrimPrefix(mustCommand(t, "cast", "keccak", encoded), "0x")
	return "ibc/" + hash[:40]
}

func queryGnoVoucherBalance(t *testing.T, cfg gnoConfig, denom, owner string) int64 {
	t.Helper()
	expr := fmt.Sprintf("gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm.VoucherBalanceOf(%q,address(%q))", denom, owner)
	out := strings.TrimSpace(queryGnoQEval(t, cfg, expr))
	_, out, _ = strings.Cut(out, "data: ")
	var balance int64
	if _, err := fmt.Sscanf(strings.TrimSpace(out), "(%d int64)", &balance); err != nil {
		t.Fatalf("parse Gno voucher balance %q: %v", out, err)
	}
	return balance
}

func (h *bridgeHarness) deployTestERC20(t *testing.T, metadata tokenMetadata) string {
	t.Helper()
	out := mustCommand(t, "forge", "create", "--root", ".", "--out", t.TempDir(), "--no-cache", "--rpc-url", h.cfg.EVM.RPC,
		"--private-key", h.cfg.EVM.PrivateKey, "--broadcast", "--json",
		"fixtures/TestERC20.sol:TestERC20", "--constructor-args", metadata.name, metadata.symbol, strconv.Itoa(int(metadata.decimals)))
	var response struct {
		DeployedTo string `json:"deployedTo"`
	}
	if err := decodeCommandJSON(out, &response); err != nil || response.DeployedTo == "" {
		t.Fatalf("parse forge create output: %v\n%s", err, out)
	}
	return response.DeployedTo
}

func castSend(t *testing.T, cfg evmConfig, contract, signature string, args ...string) EVMReceipt {
	t.Helper()
	cmdArgs := []string{"send", contract, signature}
	cmdArgs = append(cmdArgs, args...)
	cmdArgs = append(cmdArgs, "--rpc-url", cfg.RPC, "--private-key", cfg.PrivateKey, "--json")
	out := mustCommand(t, "cast", cmdArgs...)
	var receipt EVMReceipt
	if err := decodeCommandJSON(out, &receipt); err != nil || receipt.Status != "0x1" {
		t.Fatalf("cast send failed: %v status=%s\n%s", err, receipt.Status, out)
	}
	return receipt
}

func broadcastEVMPacket(t *testing.T, cfg evmConfig, channel, operand string, timeoutTimestamp int64) EVMReceipt {
	t.Helper()
	return castSend(t, cfg, cfg.ZKGM,
		"send(uint32,uint64,uint64,bytes32,(uint8,uint8,bytes))", channel, "0",
		strconv.FormatInt(timeoutTimestamp, 10), "0x"+randomHex32(t), "(2,3,"+operand+")")
}

func requireEVMReceiveAndAck(t *testing.T, cfg config, from uint64, channel, hash string, recv, write EVMLog) {
	t.Helper()
	if recv.TransactionHash != write.TransactionHash {
		t.Fatalf("EVM PacketRecv tx %s differs from WriteAck tx %s", recv.TransactionHash, write.TransactionHash)
	}
	receipt, err := queryEVMReceipt(cfg.EVM.RPC, recv.TransactionHash)
	if err != nil || receipt.Status != "0x1" {
		t.Fatalf("EVM receive receipt status=%q: %v", receipt.Status, err)
	}
	ack, err := abiBytes(mustDecodeHex(t, write.Data), 0)
	if err != nil || ackTag(ack) != 1 {
		t.Fatalf("EVM WriteAck is not success: %v", err)
	}
	for label, topic := range map[string]string{"PacketRecv": packetRecvTopic, "WriteAck": writeAckTopic} {
		logs, err := queryEVMLogs(cfg.EVM.RPC, cfg.EVM.IBCHandler, from, topic, topicUint32(mustUint32(t, channel)), hash)
		if err != nil || len(logs) != 1 {
			t.Fatalf("EVM %s count = %d, want 1: %v", label, len(logs), err)
		}
	}
}

func requireOneGnoEvent(t *testing.T, cfg gnoConfig, eventType, hash string) {
	t.Helper()
	events, err := queryGnoEvents(cfg.Indexer, eventType, map[string]string{"packet_hash": hash})
	if err != nil || len(events) != 1 {
		t.Fatalf("Gno %s count = %d, want 1: %v", eventType, len(events), err)
	}
}

func requireGnoPacketAcknowledged(t *testing.T, cfg gnoConfig, hash string) {
	t.Helper()
	batchHash := strings.TrimPrefix(hash, "0x")
	if b, err := hex.DecodeString(batchHash); err != nil || len(b) != 32 {
		t.Fatalf("invalid packet hash %q", hash)
	}
	expr := fmt.Sprintf("gno.land/r/onbloc/ibc/union/testing/e2e_setup.QueryBatchPacketCommitment(%q)", batchHash)
	want := "0x02" + strings.Repeat("00", 31)
	if out := queryGnoQEval(t, cfg, expr); !strings.Contains(out, want) {
		t.Fatalf("Gno packet commitment is not acknowledged: got %s want %s", out, want)
	}
}

func requireEVMPacketInactive(t *testing.T, cfg evmConfig, hash string) {
	t.Helper()
	path := mustCommand(t, "cast", "abi-encode", "f(uint256,bytes32)", "4", hash)
	key := mustCommand(t, "cast", "keccak", path)
	commitment := mustCommand(t, "cast", "call", cfg.IBCHandler, "commitments(bytes32)(bytes32)", key, "--rpc-url", cfg.RPC)
	want := "0x02" + strings.Repeat("0", 62)
	if !strings.EqualFold(commitment, want) {
		t.Fatalf("EVM packet commitment is still active: %s", commitment)
	}
}

func requirePacketVoyagerSuccess(t *testing.T, cfg voyagerConfig, baseline voyagerBaseline, hash string) {
	t.Helper()
	requireNoNewVoyagerFailed(t, cfg, baseline)
	if done := voyagerRowsAfter(t, cfg, "done", baseline.Done); !strings.Contains(strings.ToLower(done), strings.ToLower(hash)) {
		t.Fatalf("Voyager done rows do not contain packet %s:\n%s", hash, done)
	}
}

func requireEVMToGnoFailureAckRefund(t *testing.T, h *bridgeHarness, baseline voyagerBaseline, from uint64, hash, token string, senderBefore, escrowBefore *big.Int) {
	t.Helper()
	recv := waitForGnoEvent(t, h.cfg.Gno.Indexer, "PacketRecv", map[string]string{"packet_hash": hash})
	write := waitForGnoEvent(t, h.cfg.Gno.Indexer, "WriteAck", map[string]string{"packet_hash": hash})
	requireOneGnoEvent(t, h.cfg.Gno, "PacketRecv", hash)
	requireOneGnoEvent(t, h.cfg.Gno, "WriteAck", hash)
	ack := mustDecodeHex(t, txEncodedAttr(write, "WriteAck", "acknowledgement"))
	if recv.Hash != write.Hash || len(ack) < 32 || ackTag(ack) != 0 {
		t.Fatalf("Gno failure acknowledgement differs: recv=%s write=%s ack=%x", recv.Hash, write.Hash, ack)
	}

	sourceAck := waitForEVMLog(t, h.cfg, baseline.Failed, h.cfg.EVM.IBCHandler, evmPacketAckTopic, from, topicUint32(mustUint32(t, h.cfg.Topology.EVMGno.ChannelID)), hash)
	ack, err := abiBytes(mustDecodeHex(t, sourceAck.Data), 0)
	if err != nil || len(ack) < 32 || ackTag(ack) != 0 {
		t.Fatalf("EVM PacketAck is not failure: %v", err)
	}
	if logs, err := queryEVMLogs(h.cfg.EVM.RPC, h.cfg.EVM.IBCHandler, from, evmPacketAckTopic, topicUint32(mustUint32(t, h.cfg.Topology.EVMGno.ChannelID)), hash); err != nil || len(logs) != 1 {
		t.Fatalf("EVM PacketAck count = %d, want 1: %v", len(logs), err)
	}
	requireEVMPacketInactive(t, h.cfg.EVM, hash)
	if senderAfter, escrowAfter := queryERC20Balance(t, h.cfg.EVM, token, h.evmSender), queryERC20Balance(t, h.cfg.EVM, token, h.cfg.EVM.ZKGM); senderAfter.Cmp(senderBefore) != 0 || escrowAfter.Cmp(escrowBefore) != 0 {
		t.Fatalf("EVM refund balances sender=%s escrow=%s, want %s/%s", senderAfter, escrowAfter, senderBefore, escrowBefore)
	}
	if failed := voyagerRowsAfter(t, h.cfg.Voyager, "failed", baseline.Failed); strings.Contains(strings.ToLower(failed), strings.ToLower(hash)) {
		t.Fatalf("packet %s remains failed in Voyager:\n%s", hash, failed)
	}
}

func txEncodedAttr(tx indexedTx, eventType, key string) string {
	if value := txAttr(tx, eventType, key); value != "" {
		return value
	}
	var parts []string
	for i := 0; ; i++ {
		part := txAttr(tx, eventType, fmt.Sprintf("%s[%d]", key, i))
		if part == "" {
			break
		}
		parts = append(parts, part)
	}
	return strings.Join(parts, "")
}

func ackTag(ack []byte) uint64 {
	if len(ack) < 32 {
		return 0
	}
	return uint64(ack[31])
}

func mustHexUint64(t *testing.T, value string) uint64 {
	t.Helper()
	n, err := strconv.ParseUint(strings.TrimPrefix(value, "0x"), 16, 64)
	return must(t, n, err)
}

func mustCommand(t *testing.T, name string, args ...string) string {
	t.Helper()
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Minute)
	defer cancel()
	out, err := exec.CommandContext(ctx, name, args...).CombinedOutput()
	if err != nil {
		t.Fatalf("%s failed: %v\n%s", name, err, out)
	}
	return strings.TrimSpace(string(out))
}

func decodeCommandJSON(out string, result any) error {
	start, end := strings.Index(out, "{"), strings.LastIndex(out, "}")
	if start < 0 || end < start {
		return fmt.Errorf("JSON object not found")
	}
	return json.Unmarshal([]byte(out[start:end+1]), result)
}

func randomHex32(t *testing.T) string {
	t.Helper()
	b := make([]byte, 32)
	if _, err := rand.Read(b); err != nil {
		t.Fatal(err)
	}
	return hex.EncodeToString(b)
}

func asciiHex(value string) string { return hexBytes([]byte(value)) }

func hexBytes(value []byte) string { return "0x" + hex.EncodeToString(value) }
