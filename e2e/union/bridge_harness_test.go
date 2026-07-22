package unione2e

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"fmt"
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
	Amount                                            int64
}

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
		order.Sender, order.Receiver, order.BaseToken, strconv.FormatInt(order.Amount, 10), order.QuoteToken,
		strconv.FormatInt(order.Amount, 10), "0", order.Metadata)
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
