package config

import (
	"bytes"
	"encoding/json"
	"fmt"
	"regexp"
)

const voyagerBinDir = "/output/release"

var placeholderPattern = regexp.MustCompile(`__[A-Z0-9_]+__`)

// RenderVoyager renders the pinned Voyager configuration.
func RenderVoyager(template []byte, cfg Config, plain, proof []int64) ([]byte, error) {
	if (len(plain) == 0) != (len(proof) == 0) || overlaps(plain, proof) {
		return nil, fmt.Errorf("Voyager EVM client allowlists are invalid")
	}
	replacements := map[string]any{
		"__UNION_CHAIN_ID__":                cfg.UnionChainID,
		"__EVM_CHAIN_ID__":                  cfg.EVMChainID,
		"__GNO_CHAIN_ID__":                  cfg.GnoChainID,
		"__UNION_IBC_HOST_CONTRACT__":       cfg.UnionIBCHostContract,
		"__EVM_IBC_HANDLER__":               cfg.EVMIBCHandler,
		"__EVM_MULTICALL__":                 cfg.EVMMulticall,
		"__GNO_IBC_CORE_REALM__":            cfg.GnoIBCCoreRealm,
		"__GALOIS_PROVER_ENDPOINT__":        cfg.GaloisProverEndpoint,
		"__UNION_RPC_URL__":                 cfg.UnionRPCURL,
		"__EVM_RPC_URL__":                   cfg.EVMRPCURL,
		"__GNO_RPC_URL__":                   cfg.GnoRPCURL,
		"__GNO_TX_INDEXER_RPC_URL__":        cfg.GnoTxIndexerRPCURL,
		"__VOYAGER_DATABASE_URL__":          cfg.VoyagerDatabaseURL,
		"__TRUSTED_MPT_PRIVATE_KEY__":       cfg.TrustedMPTPrivateKey,
		"__UNION_PRIVATE_KEY__":             cfg.UnionPrivateKey,
		"__EVM_PRIVATE_KEY__":               cfg.EVMPrivateKey,
		"__GNO_PRIVATE_KEY__":               cfg.GnoPrivateKey,
		"__EVM_CLIENT_CONFIGS__":            clientConfigs(plain),
		"__EVM_PROOF_LENS_CLIENT_CONFIGS__": clientConfigs(proof),
	}
	rendered := bytes.ReplaceAll(template, []byte("__VOYAGER_BIN_DIR__"), []byte(voyagerBinDir))
	for placeholder, value := range replacements {
		encoded, err := json.Marshal(value)
		if err != nil {
			return nil, fmt.Errorf("cannot render Voyager config")
		}
		if _, ok := value.(string); ok {
			encoded = encoded[1 : len(encoded)-1]
		}
		rendered = bytes.ReplaceAll(rendered, []byte(placeholder), encoded)
	}
	if placeholderPattern.Match(rendered) {
		return nil, fmt.Errorf("rendered config contains an unresolved placeholder")
	}
	var root any
	if err := json.Unmarshal(rendered, &root); err != nil {
		return nil, fmt.Errorf("cannot parse rendered Voyager config")
	}
	rendered, err := json.MarshalIndent(root, "", "  ")
	return append(rendered, '\n'), err
}

func clientConfigs(ids []int64) []any {
	configs := make([]any, 0, len(ids))
	for _, id := range ids {
		configs = append(configs, map[string]any{
			"client_id":      id,
			"min_batch_size": 1,
			"max_batch_size": 5,
			"max_wait_time":  map[string]any{"nanos": 0, "secs": 10},
		})
	}
	return configs
}

func overlaps(left, right []int64) bool {
	seen := make(map[int64]struct{}, len(left))
	for _, id := range left {
		seen[id] = struct{}{}
	}
	for _, id := range right {
		if _, ok := seen[id]; ok {
			return true
		}
	}
	return false
}
