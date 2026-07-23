package config

import (
	"encoding/json"
	"fmt"
	"regexp"
	"slices"
	"strings"
)

const voyagerBinDir = "/output/release"

var placeholderPattern = regexp.MustCompile(`__[A-Z0-9_]+__`)

// RenderVoyager renders and validates the pinned Voyager configuration.
func RenderVoyager(template []byte, cfg Config, plain, proof []int64) ([]byte, error) {
	var root any
	if err := json.Unmarshal(template, &root); err != nil {
		return nil, fmt.Errorf("cannot parse Voyager config template")
	}
	replacements := map[string]string{
		"__EVM_CHAIN_ID__":            cfg.EVMChainID,
		"__UNION_IBC_HOST_CONTRACT__": cfg.UnionIBCHostContract,
		"__EVM_IBC_HANDLER__":         cfg.EVMIBCHandler,
		"__EVM_MULTICALL__":           cfg.EVMMulticall,
		"__GNO_IBC_CORE_REALM__":      cfg.GnoIBCCoreRealm,
		"__GALOIS_PROVER_ENDPOINT__":  cfg.GaloisProverEndpoint,
		"__UNION_RPC_URL__":           cfg.UnionRPCURL,
		"__EVM_RPC_URL__":             cfg.EVMRPCURL,
		"__GNO_RPC_URL__":             cfg.GnoRPCURL,
		"__GNO_TX_INDEXER_RPC_URL__":  cfg.GnoTxIndexerRPCURL,
		"__VOYAGER_DATABASE_URL__":    cfg.VoyagerDatabaseURL,
		"__TRUSTED_MPT_PRIVATE_KEY__": cfg.TrustedMPTPrivateKey,
		"__UNION_PRIVATE_KEY__":       cfg.UnionPrivateKey,
		"__EVM_PRIVATE_KEY__":         cfg.EVMPrivateKey,
		"__GNO_PRIVATE_KEY__":         cfg.GnoPrivateKey,
	}
	root = walkStrings(root, func(value string) string {
		value = strings.Replace(value, "__VOYAGER_BIN_DIR__", voyagerBinDir, 1)
		if replacement, ok := replacements[value]; ok {
			return replacement
		}
		return value
	})
	object, ok := root.(map[string]any)
	if !ok {
		return nil, fmt.Errorf("Voyager config template must be an object")
	}
	modules, ok := object["modules"].(map[string]any)
	if !ok {
		return nil, fmt.Errorf("Voyager config template has no modules")
	}
	if err := validateClientModules(modules); err != nil {
		return nil, err
	}
	if err := validateStateModules(modules, cfg); err != nil {
		return nil, err
	}
	plugins, ok := object["plugins"].([]any)
	if !ok {
		return nil, fmt.Errorf("Voyager config template has no plugins")
	}
	plainSet, proofSet := false, false
	for _, raw := range plugins {
		plugin, ok := raw.(map[string]any)
		if !ok {
			return nil, fmt.Errorf("Voyager config template has malformed plugins")
		}
		path, _ := plugin["path"].(string)
		pluginConfig, ok := plugin["config"].(map[string]any)
		if !ok {
			return nil, fmt.Errorf("Voyager config template has malformed plugins")
		}
		chain, _ := pluginConfig["chain_id"].(string)
		switch {
		case strings.HasSuffix(path, "voyager-plugin-transaction-batch") && chain == cfg.EVMChainID:
			pluginConfig["client_configs"] = clientConfigs(plain)
			plainSet = true
		case strings.HasSuffix(path, "voyager-plugin-transaction-batch-proof-lens") && chain == cfg.EVMChainID:
			pluginConfig["client_configs"] = clientConfigs(proof)
			proofSet = true
		}
	}
	if !plainSet || !proofSet || (len(plain) == 0) != (len(proof) == 0) || overlaps(plain, proof) {
		return nil, fmt.Errorf("Voyager EVM client allowlists are invalid")
	}
	rendered, err := json.MarshalIndent(root, "", "  ")
	if err != nil {
		return nil, fmt.Errorf("cannot render Voyager config")
	}
	if placeholderPattern.Match(rendered) {
		return nil, fmt.Errorf("rendered config contains an unresolved placeholder")
	}
	return append(rendered, '\n'), nil
}

func validateStateModules(modules map[string]any, cfg Config) error {
	raw, ok := modules["state"].([]any)
	if !ok {
		return fmt.Errorf("Voyager config template has no state modules")
	}
	got := make([]string, 0, len(raw))
	for _, item := range raw {
		module, _ := item.(map[string]any)
		info, _ := module["info"].(map[string]any)
		chain, _ := info["chain_id"].(string)
		got = append(got, chain)
	}
	slices.Sort(got)
	want := []string{cfg.UnionChainID, cfg.EVMChainID, cfg.GnoChainID}
	slices.Sort(want)
	if !slices.Equal(got, want) {
		return fmt.Errorf("Voyager state module set changed")
	}
	return nil
}

func walkStrings(value any, replace func(string) string) any {
	switch value := value.(type) {
	case string:
		return replace(value)
	case []any:
		for index := range value {
			value[index] = walkStrings(value[index], replace)
		}
	case map[string]any:
		for key := range value {
			value[key] = walkStrings(value[key], replace)
		}
	}
	return value
}

func validateClientModules(modules map[string]any) error {
	raw, ok := modules["client"].([]any)
	if !ok {
		return fmt.Errorf("Voyager config template has no client modules")
	}
	got := make([]string, 0, len(raw))
	for _, item := range raw {
		module, _ := item.(map[string]any)
		info, _ := module["info"].(map[string]any)
		got = append(got, fmt.Sprint(info["client_type"], "/", info["ibc_interface"]))
	}
	slices.Sort(got)
	want := []string{
		"cometbls/ibc-gno",
		"cometbls/ibc-solidity",
		"gno/ibc-cosmwasm",
		"proof-lens/ibc-solidity",
		"state-lens/ics23/mpt/ibc-gno",
		"trusted/evm/mpt/ibc-cosmwasm",
	}
	slices.Sort(want)
	if !slices.Equal(got, want) {
		return fmt.Errorf("Voyager client module set changed")
	}
	return nil
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
