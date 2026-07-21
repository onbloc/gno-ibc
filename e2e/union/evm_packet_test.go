package unione2e

import (
	"context"
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
	packetRecvTopic         = "0xe450e03249d131499e278eeafd8e27effcceeb40b0b95628a087aa16b4b101d5"
	writeAckTopic           = "0x488830ba53f27b7033e966a79427476ad47d550358e894bafeef8b97c6559251"
	createWrappedTokenTopic = "0x18469840730c2cbbd67b9f99f6421667b07f0169a795be80a28f182d602daf5b"
)

func TestUnionEVMTopology(t *testing.T) {
	cfg := loadConfig()
	if !cfg.RunPacketTests {
		t.Skip("set RUN_PACKET_TESTS=1 to check the live Union-Ethereum topology")
	}
	requireUnionEVMTopology(t, cfg)
}

func requireUnionEVMTopology(t *testing.T, cfg config) {
	t.Helper()
	var status, clientType string
	clientID := mustUint32(t, cfg.UnionEVMClientID)
	if err := queryUnionCore(cfg.UnionContainer, cfg.UnionCoreContract, map[string]any{"get_client_type": map[string]any{"client_id": clientID}}, &clientType); err != nil || clientType != "trusted/evm/mpt" {
		t.Fatalf("Union EVM client type = %q: %v", clientType, err)
	}
	if err := queryUnionCore(cfg.UnionContainer, cfg.UnionCoreContract, map[string]any{"get_status": map[string]any{"client_id": clientID}}, &status); err != nil || status != "active" {
		t.Fatalf("Union EVM client status = %q: %v", status, err)
	}
	var connection struct {
		State                    string `json:"state"`
		ClientID                 uint32 `json:"client_id"`
		CounterpartyClientID     uint32 `json:"counterparty_client_id"`
		CounterpartyConnectionID uint32 `json:"counterparty_connection_id"`
	}
	if err := queryUnionCore(cfg.UnionContainer, cfg.UnionCoreContract, map[string]any{"get_connection": map[string]any{"connection_id": mustUint32(t, cfg.UnionEVMConnectionID)}}, &connection); err != nil || connection.State != "open" || connection.ClientID != clientID || connection.CounterpartyClientID != mustUint32(t, cfg.EVMUnionClientID) || connection.CounterpartyConnectionID != mustUint32(t, cfg.EVMUnionConnectionID) {
		t.Fatalf("Union EVM connection differs: %+v: %v", connection, err)
	}
	var channel struct {
		State                 string `json:"state"`
		ConnectionID          uint32 `json:"connection_id"`
		CounterpartyChannelID uint32 `json:"counterparty_channel_id"`
		CounterpartyPortID    string `json:"counterparty_port_id"`
		Version               string `json:"version"`
	}
	if err := queryUnionCore(cfg.UnionContainer, cfg.UnionCoreContract, map[string]any{"get_channel": map[string]any{"channel_id": mustUint32(t, cfg.UnionEVMChannelID)}}, &channel); err != nil || channel.State != "open" || channel.ConnectionID != mustUint32(t, cfg.UnionEVMConnectionID) || channel.CounterpartyChannelID != mustUint32(t, cfg.EVMUnionChannelID) || !strings.EqualFold(channel.CounterpartyPortID, cfg.EVMZKGM) || channel.Version != "ucs03-zkgm-0" {
		t.Fatalf("Union EVM channel differs: %+v: %v", channel, err)
	}
	requireEVMTopology(t, cfg)
}

func requireEVMTopology(t *testing.T, cfg config) {
	t.Helper()
	clientID := mustUint32(t, cfg.EVMUnionClientID)
	clientTypeData, err := evmCall(cfg.EVMRPC, cfg.EVMIBCHandler, evmUint32CallData("0x1296c148", clientID))
	if err != nil {
		t.Fatal(err)
	}
	clientType, err := abiString(clientTypeData, 0)
	if err != nil || clientType != "cometbls" {
		t.Fatalf("EVM Union client type = %q: %v", clientType, err)
	}
	implData, err := evmCall(cfg.EVMRPC, cfg.EVMIBCHandler, evmUint32CallData("0x5f5d288e", clientID))
	if err != nil {
		t.Fatal(err)
	}
	impl, err := abiAddress(implData, 0)
	if err != nil {
		t.Fatal(err)
	}
	latestData, err := evmCall(cfg.EVMRPC, impl, evmUint32CallData("0x2886a3a3", clientID))
	if err != nil {
		t.Fatal(err)
	}
	latest, err := abiUint(latestData, 0)
	if err != nil || latest == 0 {
		t.Fatalf("EVM Union client latest height = %d: %v", latest, err)
	}
	frozenData, err := evmCall(cfg.EVMRPC, impl, evmUint32CallData("0xb6719c89", clientID))
	if err != nil {
		t.Fatal(err)
	}
	frozen, err := abiUint(frozenData, 0)
	if err != nil || frozen != 0 {
		t.Fatalf("EVM Union client frozen = %d: %v", frozen, err)
	}
	connectionData, err := evmCall(cfg.EVMRPC, cfg.EVMIBCHandler, evmUint32CallData("0xb1892e40", mustUint32(t, cfg.EVMUnionConnectionID)))
	if err != nil {
		t.Fatal(err)
	}
	state, _ := abiUint(connectionData, 0)
	localClient, _ := abiUint(connectionData, 1)
	counterpartyClient, _ := abiUint(connectionData, 2)
	counterpartyConnection, _ := abiUint(connectionData, 3)
	if state != 3 || localClient != uint64(clientID) || counterpartyClient != uint64(mustUint32(t, cfg.UnionEVMClientID)) || counterpartyConnection != uint64(mustUint32(t, cfg.UnionEVMConnectionID)) {
		t.Fatalf("EVM connection differs: state=%d client=%d counterpartyClient=%d counterpartyConnection=%d", state, localClient, counterpartyClient, counterpartyConnection)
	}
	channelID := mustUint32(t, cfg.EVMUnionChannelID)
	channelData, err := evmCall(cfg.EVMRPC, cfg.EVMIBCHandler, evmUint32CallData("0x113a1b70", channelID))
	if err != nil {
		t.Fatal(err)
	}
	channelState, _ := abiUint(channelData, 0)
	connectionID, _ := abiUint(channelData, 1)
	counterpartyChannel, _ := abiUint(channelData, 2)
	counterpartyPort, _ := abiBytes(channelData, 3)
	version, _ := abiString(channelData, 4)
	if channelState != 3 || connectionID != uint64(mustUint32(t, cfg.EVMUnionConnectionID)) || counterpartyChannel != uint64(mustUint32(t, cfg.UnionEVMChannelID)) || string(counterpartyPort) != cfg.UnionZKGMContract || version != "ucs03-zkgm-0" {
		t.Fatalf("EVM channel differs: state=%d connection=%d counterpartyChannel=%d counterpartyPort=%q version=%q", channelState, connectionID, counterpartyChannel, counterpartyPort, version)
	}
	ownerData, err := evmCall(cfg.EVMRPC, cfg.EVMIBCHandler, evmUint32CallData("0xde844ebc", channelID))
	if err != nil {
		t.Fatal(err)
	}
	owner, _ := abiAddress(ownerData, 0)
	if !strings.EqualFold(owner, cfg.EVMZKGM) {
		t.Fatalf("EVM channel owner = %s, want %s", owner, cfg.EVMZKGM)
	}
	for label, address := range map[string]string{"handler": cfg.EVMIBCHandler, "zkgm": cfg.EVMZKGM, "erc20 implementation": cfg.EVMERC20Impl} {
		code, err := queryEVMCode(cfg.EVMRPC, address)
		if err != nil || len(code) == 0 {
			t.Fatalf("%s code is empty: %v", label, err)
		}
	}
}

func castDecode(t *testing.T, signature, value string) []any {
	t.Helper()
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	out, err := exec.CommandContext(ctx, "cast", "decode-abi", signature, value, "--json").CombinedOutput()
	if err != nil {
		t.Fatalf("cast decode-abi: %v\n%s", err, out)
	}
	var decoded []any
	if err := json.Unmarshal(out, &decoded); err != nil {
		t.Fatalf("decode cast output: %v\n%s", err, out)
	}
	return decoded
}

func castDecodeInput(t *testing.T, signature, value string) []any {
	t.Helper()
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	out, err := exec.CommandContext(ctx, "cast", "decode-abi", "--input", signature, value, "--json").CombinedOutput()
	if err != nil {
		t.Fatalf("cast decode-abi input: %v\n%s", err, out)
	}
	var decoded []any
	if err := json.Unmarshal(out, &decoded); err != nil {
		t.Fatalf("decode cast input output: %v\n%s", err, out)
	}
	return decoded
}

func requireUnionPacketCommitmentRemoved(t *testing.T, cfg config, packetHash string) {
	t.Helper()
	encoded, err := exec.Command("cast", "abi-encode", "f(uint256,bytes32)", "4", packetHash).Output()
	if err != nil {
		t.Fatal(err)
	}
	key, err := exec.Command("cast", "keccak", strings.TrimSpace(string(encoded))).Output()
	if err != nil {
		t.Fatal(err)
	}
	out, err := dockerExec(cfg.UnionContainer,
		"uniond", "query", "wasm", "contract-state", "raw", cfg.UnionCoreContract,
		strings.TrimPrefix(strings.TrimSpace(string(key)), "0x"),
		"--node", "tcp://localhost:26657", "-o", "json",
	)
	if err != nil {
		t.Fatalf("query Union packet commitment: %v\n%s", err, out)
	}
	var response struct {
		Data json.RawMessage `json:"data"`
	}
	if err := json.Unmarshal([]byte(out), &response); err != nil || string(response.Data) != "null" {
		t.Fatalf("Union packet commitment still exists: %s: %v", out, err)
	}
}

func unionEvent(t *testing.T, body []byte, eventType string) (string, int64, string) {
	t.Helper()
	var tx struct {
		Height string `json:"height"`
		TxHash string `json:"txhash"`
		Events []struct {
			Type       string `json:"type"`
			Attributes []struct {
				Key   string `json:"key"`
				Value string `json:"value"`
			} `json:"attributes"`
		} `json:"events"`
	}
	if err := json.Unmarshal(body, &tx); err != nil {
		t.Fatal(err)
	}
	height, err := strconv.ParseInt(tx.Height, 10, 64)
	if err != nil {
		t.Fatal(err)
	}
	for _, event := range tx.Events {
		if event.Type != eventType {
			continue
		}
		for _, attr := range event.Attributes {
			if attr.Key == "packet_hash" {
				return attr.Value, height, tx.TxHash
			}
		}
	}
	t.Fatalf("%s missing packet_hash:\n%s", eventType, body)
	return "", 0, ""
}

func waitForEVMLog(t *testing.T, cfg config, failedBaseline int64, address, eventTopic string, from uint64, topics ...string) EVMLog {
	t.Helper()
	deadline := time.Now().Add(2 * time.Minute)
	for time.Now().Before(deadline) {
		logs, err := queryEVMLogs(cfg.EVMRPC, address, from, append([]string{eventTopic}, topics...)...)
		if err == nil && len(logs) > 0 {
			return logs[0]
		}
		if rows := voyagerRowsAfter(t, cfg, "failed", failedBaseline); rows != "" {
			t.Fatalf("new Voyager failed rows:\n%s", rows)
		}
		time.Sleep(time.Second)
	}
	t.Fatalf("EVM log %s not found\nqueue:\n%s\nfailed:\n%s", eventTopic, voyagerQueueStats(t, cfg), voyagerQueryFailed(t, cfg))
	return EVMLog{}
}

func queryERC20Balance(t *testing.T, cfg config, token, owner string) int64 {
	t.Helper()
	code, err := queryEVMCode(cfg.EVMRPC, token)
	if err != nil {
		t.Fatal(err)
	}
	if len(code) == 0 {
		return 0
	}
	data, err := evmAddressCallData("0x70a08231", owner)
	if err != nil {
		t.Fatal(err)
	}
	out, err := evmCall(cfg.EVMRPC, token, data)
	if err != nil {
		t.Fatal(err)
	}
	value, err := abiUint(out, 0)
	if err != nil {
		t.Fatal(err)
	}
	return int64(value)
}

func queryERC20String(t *testing.T, cfg config, token, selector string) string {
	t.Helper()
	out, err := evmCall(cfg.EVMRPC, token, selector)
	if err != nil {
		t.Fatal(err)
	}
	value, err := abiString(out, 0)
	if err != nil {
		t.Fatal(err)
	}
	return value
}

func queryERC20Uint(t *testing.T, cfg config, token, selector string) uint64 {
	t.Helper()
	out, err := evmCall(cfg.EVMRPC, token, selector)
	if err != nil {
		t.Fatal(err)
	}
	value, err := abiUint(out, 0)
	if err != nil {
		t.Fatal(err)
	}
	return value
}

func topicUint32(value uint32) string {
	return fmt.Sprintf("0x%064x", value)
}

func topicAddress(value string) string {
	return "0x" + strings.Repeat("0", 24) + strings.ToLower(strings.TrimPrefix(value, "0x"))
}

func mustDecodeHex(t *testing.T, value string) []byte {
	t.Helper()
	out, err := hex.DecodeString(strings.TrimPrefix(value, "0x"))
	if err != nil {
		t.Fatal(err)
	}
	return out
}

func mustNumber(t *testing.T, value any) uint64 {
	t.Helper()
	switch value := value.(type) {
	case float64:
		return uint64(value)
	case string:
		n, err := strconv.ParseUint(value, 10, 64)
		if err != nil {
			t.Fatal(err)
		}
		return n
	}
	t.Fatalf("expected number, got %T", value)
	return 0
}
