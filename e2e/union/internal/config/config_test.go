package config_test

import (
	"bytes"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/onbloc/gno-ibc/e2e/union/internal/config"
)

func TestLoadAppliesPacketRPCFallbacks(t *testing.T) {
	cfg, err := config.Load("/suite", lookup(validEnvironment()), true)
	if err != nil {
		t.Fatal(err)
	}
	if cfg.EVMPacketRPCURL != cfg.EVMRPCURL {
		t.Fatalf("EVM packet RPC = %q, want %q", cfg.EVMPacketRPCURL, cfg.EVMRPCURL)
	}
	if cfg.GnoPacketRPCURL != cfg.GnoRPCURL {
		t.Fatalf("Gno packet RPC = %q, want %q", cfg.GnoPacketRPCURL, cfg.GnoRPCURL)
	}
	if cfg.GnoPacketIndexerRPCURL != cfg.GnoTxIndexerRPCURL {
		t.Fatalf("Gno packet indexer = %q, want %q", cfg.GnoPacketIndexerRPCURL, cfg.GnoTxIndexerRPCURL)
	}
}

func TestLoadRejectsMalformedTrustBoundaryValues(t *testing.T) {
	env := validEnvironment()
	env["EVM_IBC_HANDLER"] = "0x1"
	if _, err := config.Load("/suite", lookup(env), false); err == nil ||
		!strings.Contains(err.Error(), "EVM_IBC_HANDLER") {
		t.Fatalf("error = %v, want EVM_IBC_HANDLER validation", err)
	}
}

func TestLoadRejectsOverflowingCommandTimeout(t *testing.T) {
	env := validEnvironment()
	env["VOYAGER_COMMAND_TIMEOUT_SECONDS"] = "9223372036854775807"
	if _, err := config.Load("/suite", lookup(env), false); err == nil {
		t.Fatal("overflowing command timeout unexpectedly accepted")
	}
}

func TestPacketLedgerAmount(t *testing.T) {
	if got, err := config.PacketLedgerAmount("1000000000000"); err != nil || got != 1 {
		t.Fatalf("amount = %d, %v", got, err)
	}
	for _, amount := range []string{"0", "1", "01000000000000", "9223372036854775808000000000000"} {
		if _, err := config.PacketLedgerAmount(amount); err == nil {
			t.Fatalf("invalid amount %q unexpectedly accepted", amount)
		}
	}
}

func TestTopologyFingerprintMatchesFixedPoint(t *testing.T) {
	cfg, err := config.Load("/suite", lookup(validEnvironment()), false)
	if err != nil {
		t.Fatal(err)
	}
	if got, want := cfg.TopologyFingerprint(), "53b14ed7e73989ece8823a4cf115bf409ef8a046"; got != want {
		t.Fatalf("fingerprint = %q, want %q", got, want)
	}
}

func TestRenderVoyagerConfig(t *testing.T) {
	cfg, err := config.Load("/suite", lookup(validEnvironment()), false)
	if err != nil {
		t.Fatal(err)
	}

	template, err := os.ReadFile(filepath.Join("..", "..", "config.jsonc.template"))
	if err != nil {
		t.Fatal(err)
	}

	rendered, err := config.RenderVoyager(template, cfg, []int64{1, 3}, []int64{2})
	if err != nil {
		t.Fatal(err)
	}

	if strings.Contains(string(rendered), "__EVM_CHAIN_ID__") ||
		!strings.Contains(string(rendered), `"client_id": 3`) {
		t.Fatal("rendered config retained a placeholder or lost the allowlist")
	}
}

func TestRenderVoyagerRejectsChangedStateModuleTopology(t *testing.T) {
	cfg, err := config.Load("/suite", lookup(validEnvironment()), false)
	if err != nil {
		t.Fatal(err)
	}

	template, err := os.ReadFile(filepath.Join("..", "..", "config.jsonc.template"))
	if err != nil {
		t.Fatal(err)
	}

	template = bytes.Replace(template, []byte(`"chain_id":"dev.ibc"`), []byte(`"chain_id":"wrong"`), 1)
	if _, err := config.RenderVoyager(template, cfg, nil, nil); err == nil {
		t.Fatal("changed state-module topology unexpectedly accepted")
	}
}

func validEnvironment() map[string]string {
	return map[string]string{
		"UNION_CHAIN_ID":                  "union-devnet-1",
		"EVM_CHAIN_ID":                    "17000",
		"GNO_CHAIN_ID":                    "dev.ibc",
		"UNION_VOYAGER_DIR":               "/voyager",
		"UNION_VOYAGER_REVISION":          "82c70ec1ff84ec457e976ad94f38a5d5783b7836",
		"UNION_IBC_HOST_CONTRACT":         "union1host",
		"EVM_IBC_HANDLER":                 "0x1111111111111111111111111111111111111111",
		"EVM_MULTICALL":                   "0x2222222222222222222222222222222222222222",
		"EVM_COMETBLS_CLIENT_IMPL":        "0x3333333333333333333333333333333333333333",
		"EVM_PROOF_LENS_CLIENT_IMPL":      "0x4444444444444444444444444444444444444444",
		"GNO_IBC_CORE_REALM":              "gno.land/r/onbloc/ibc/union/core",
		"GNO_ZKGM_PORT":                   "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm",
		"EVM_ZKGM_CONTRACT":               "0x5555555555555555555555555555555555555555",
		"GALOIS_PROVER_ENDPOINT":          "https://galois.example",
		"UNION_RPC_URL":                   "https://union.example",
		"EVM_RPC_URL":                     "https://evm.example",
		"GNO_RPC_URL":                     "https://gno.example",
		"GNO_TX_INDEXER_RPC_URL":          "https://indexer.example",
		"VOYAGER_DATABASE_URL":            "postgres://voyager:" + "password@db/voyager",
		"TRUSTED_MPT_PRIVATE_KEY":         "0x" + strings.Repeat("a", 64),
		"UNION_PRIVATE_KEY":               "0x" + strings.Repeat("b", 64),
		"EVM_PRIVATE_KEY":                 "0x" + strings.Repeat("c", 64),
		"GNO_PRIVATE_KEY":                 "0x" + strings.Repeat("d", 64),
		"EVM_TEST_ERC20":                  "0x6666666666666666666666666666666666666666",
		"GNO_RECIPIENT":                   "g1" + strings.Repeat("a", 38),
		"EVM_TEST_AMOUNT":                 "1000000000000",
		"E2E_ARTIFACT_DIR":                "/suite/artifacts",
		"E2E_STATE_FILE":                  "/suite/artifacts/state.json",
		"VOYAGER_COMMAND_TIMEOUT_SECONDS": "120",
	}
}

func lookup(values map[string]string) func(string) (string, bool) {
	return func(name string) (string, bool) {
		value, ok := values[name]
		return value, ok
	}
}
