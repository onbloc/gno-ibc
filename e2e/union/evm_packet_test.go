package unione2e

import (
	"encoding/hex"
	"encoding/json"
	"fmt"
	"math/big"
	"strings"
	"testing"
	"time"
)

const (
	packetRecvTopic         = "0xe450e03249d131499e278eeafd8e27effcceeb40b0b95628a087aa16b4b101d5"
	writeAckTopic           = "0x488830ba53f27b7033e966a79427476ad47d550358e894bafeef8b97c6559251"
	createWrappedTokenTopic = "0x18469840730c2cbbd67b9f99f6421667b07f0169a795be80a28f182d602daf5b"
)

func castDecode(t *testing.T, signature, value string) []any {
	t.Helper()
	out := mustCommand(t, "cast", "decode-abi", signature, value, "--json")
	var decoded []any
	if err := json.Unmarshal([]byte(out), &decoded); err != nil {
		t.Fatalf("decode cast output: %v\n%s", err, out)
	}
	return decoded
}

func waitForEVMLog(t *testing.T, cfg config, failedBaseline int64, address, eventTopic string, from uint64, topics ...string) EVMLog {
	t.Helper()
	deadline := time.Now().Add(2 * time.Minute)
	for time.Now().Before(deadline) {
		logs, err := queryEVMLogs(cfg.EVM.RPC, address, from, append([]string{eventTopic}, topics...)...)
		if err == nil && len(logs) > 0 {
			return logs[0]
		}
		if rows := voyagerRowsAfter(t, cfg.Voyager, "failed", failedBaseline); rows != "" {
			t.Fatalf("new Voyager failed rows:\n%s", rows)
		}
		time.Sleep(time.Second)
	}
	t.Fatalf("EVM log %s not found\nqueue:\n%s\nfailed:\n%s", eventTopic, voyagerQueueStats(t, cfg.Voyager), voyagerQueryFailed(t, cfg.Voyager))
	return EVMLog{}
}

func queryERC20Balance(t *testing.T, cfg evmConfig, token, owner string) *big.Int {
	t.Helper()
	code, err := queryEVMCode(cfg.RPC, token)
	code = must(t, code, err)
	if len(code) == 0 {
		return new(big.Int)
	}
	data, err := evmAddressCallData("0x70a08231", owner)
	data = must(t, data, err)
	out, err := evmCall(cfg.RPC, token, data)
	out = must(t, out, err)
	value, err := abiWord(out, 0)
	return new(big.Int).SetBytes(must(t, value, err))
}

func queryERC20TotalSupply(t *testing.T, cfg evmConfig, token string) *big.Int {
	t.Helper()
	out, err := evmCall(cfg.RPC, token, "0x18160ddd")
	out = must(t, out, err)
	value, err := abiWord(out, 0)
	return new(big.Int).SetBytes(must(t, value, err))
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
	return must(t, out, err)
}

func must[T any](t *testing.T, value T, err error) T {
	t.Helper()
	if err != nil {
		t.Fatal(err)
	}
	return value
}
