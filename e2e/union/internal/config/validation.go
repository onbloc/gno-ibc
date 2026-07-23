package config

import (
	"fmt"
	"math/big"
	"strings"
)

func (c Config) validate(packet bool) error {
	required := []struct {
		name  string
		value string
	}{
		{"UNION_CHAIN_ID", c.UnionChainID},
		{"EVM_CHAIN_ID", c.EVMChainID},
		{"GNO_CHAIN_ID", c.GnoChainID},
		{"UNION_VOYAGER_DIR", c.UnionVoyagerDir},
		{"UNION_VOYAGER_REVISION", c.UnionVoyagerRevision},
		{"UNION_IBC_HOST_CONTRACT", c.UnionIBCHostContract},
		{"EVM_IBC_HANDLER", c.EVMIBCHandler},
		{"EVM_MULTICALL", c.EVMMulticall},
		{"EVM_COMETBLS_CLIENT_IMPL", c.EVMCometBLSClientImpl},
		{"EVM_PROOF_LENS_CLIENT_IMPL", c.EVMProofLensClientImpl},
		{"GNO_IBC_CORE_REALM", c.GnoIBCCoreRealm},
		{"GNO_ZKGM_PORT", c.GnoZKGMPort},
		{"EVM_ZKGM_CONTRACT", c.EVMZKGMContract},
		{"GALOIS_PROVER_ENDPOINT", c.GaloisProverEndpoint},
		{"UNION_RPC_URL", c.UnionRPCURL},
		{"EVM_RPC_URL", c.EVMRPCURL},
		{"GNO_RPC_URL", c.GnoRPCURL},
		{"GNO_TX_INDEXER_RPC_URL", c.GnoTxIndexerRPCURL},
		{"VOYAGER_DATABASE_URL", c.VoyagerDatabaseURL},
		{"TRUSTED_MPT_PRIVATE_KEY", c.TrustedMPTPrivateKey},
		{"UNION_PRIVATE_KEY", c.UnionPrivateKey},
		{"EVM_PRIVATE_KEY", c.EVMPrivateKey},
		{"GNO_PRIVATE_KEY", c.GnoPrivateKey},
	}

	for _, item := range required {
		if item.value == "" {
			return fmt.Errorf("missing required environment variable: %s", item.name)
		}
	}

	if c.UnionChainID != "union-devnet-1" || c.GnoChainID != "dev.ibc" {
		return fmt.Errorf("UNION_CHAIN_ID and GNO_CHAIN_ID must be union-devnet-1 and dev.ibc")
	}
	if n, ok := new(big.Int).SetString(c.EVMChainID, 10); !ok || n.Sign() <= 0 ||
		strings.HasPrefix(c.EVMChainID, "+") || strings.HasPrefix(c.EVMChainID, "0") {
		return fmt.Errorf("EVM_CHAIN_ID must be a positive decimal integer")
	}
	if !revisionPattern.MatchString(c.UnionVoyagerRevision) {
		return fmt.Errorf("UNION_VOYAGER_REVISION must be a lowercase 40-character commit SHA")
	}
	if c.UnionVoyagerRevision != VoyagerRevision {
		return fmt.Errorf("UNION_VOYAGER_REVISION must match the pinned Voyager revision")
	}
	if !gnoRealmPattern.MatchString(c.GnoZKGMPort) {
		return fmt.Errorf("GNO_ZKGM_PORT must be a gno.land/r/... realm path")
	}

	for _, item := range []struct {
		name  string
		value string
	}{
		{"EVM_IBC_HANDLER", c.EVMIBCHandler},
		{"EVM_MULTICALL", c.EVMMulticall},
		{"EVM_ZKGM_CONTRACT", c.EVMZKGMContract},
		{"EVM_COMETBLS_CLIENT_IMPL", c.EVMCometBLSClientImpl},
		{"EVM_PROOF_LENS_CLIENT_IMPL", c.EVMProofLensClientImpl},
	} {
		if !addressPattern.MatchString(item.value) {
			return fmt.Errorf("%s must be a 20-byte hex address", item.name)
		}
	}
	for _, item := range []struct {
		name  string
		value string
	}{
		{"TRUSTED_MPT_PRIVATE_KEY", c.TrustedMPTPrivateKey},
		{"UNION_PRIVATE_KEY", c.UnionPrivateKey},
		{"EVM_PRIVATE_KEY", c.EVMPrivateKey},
		{"GNO_PRIVATE_KEY", c.GnoPrivateKey},
	} {
		if !privateKeyPattern.MatchString(item.value) {
			return fmt.Errorf("%s must be a 0x-prefixed 32-byte private key", item.name)
		}
	}

	if !packet {
		return nil
	}
	if c.EVMTestERC20 == "" || c.GnoRecipient == "" || c.EVMTestAmount == "" {
		return fmt.Errorf("missing required packet environment variable")
	}
	if !addressPattern.MatchString(c.EVMTestERC20) {
		return fmt.Errorf("EVM_TEST_ERC20 must be a 20-byte hex address")
	}
	if !gnoAddressPattern.MatchString(c.GnoRecipient) {
		return fmt.Errorf("GNO_RECIPIENT must be a Gno bech32 address")
	}
	if _, err := PacketLedgerAmount(c.EVMTestAmount); err != nil {
		return err
	}

	for _, item := range []struct {
		name  string
		value string
	}{
		{"EVM_PACKET_RPC_URL", c.EVMPacketRPCURL},
		{"GNO_PACKET_RPC_URL", c.GnoPacketRPCURL},
		{"GNO_PACKET_INDEXER_RPC_URL", c.GnoPacketIndexerRPCURL},
	} {
		if strings.ContainsAny(item.value, "\n\"\\") {
			return fmt.Errorf("%s contains an unsupported character", item.name)
		}
	}

	return nil
}

// PacketLedgerAmount converts a validated 18-decimal amount to Gno's 6 decimals.
func PacketLedgerAmount(amount string) (int64, error) {
	if len(amount) <= 12 || strings.Trim(amount, "0123456789") != "" ||
		amount[0] == '0' || !strings.HasSuffix(amount, "000000000000") {
		return 0, fmt.Errorf("EVM_TEST_AMOUNT must be positive and divisible by 10^12")
	}

	scaled, ok := new(big.Int).SetString(amount[:len(amount)-12], 10)
	if !ok || !scaled.IsInt64() {
		return 0, fmt.Errorf("EVM_TEST_AMOUNT after 10^12 scaling must fit Gno int64")
	}

	return scaled.Int64(), nil
}
