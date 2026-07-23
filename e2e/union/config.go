package unione2e

import (
	"encoding/hex"
	"fmt"
	"os"
	"strconv"
	"strings"
)

type config struct {
	Gno        gnoConfig
	Union      unionConfig
	EVM        evmConfig
	Voyager    voyagerConfig
	Topology   topologyConfig
	RunPackets bool
}

type gnoConfig struct {
	RPC        string
	Indexer    string
	ChainID    string
	KeyName    string
	ComposeDir string
	Sender     string
}

type unionConfig struct {
	RPC       string
	ChainID   string
	Container string
	Core      string
}

type evmConfig struct {
	RPC        string
	ChainID    string
	IBCHandler string
	ZKGM       string
	ERC20Impl  string
	Manager    string
	Recipient  string
	BeaconAPI  string
	PrivateKey string
}

type voyagerConfig struct {
	Container         string
	ConfigPath        string
	PostgresContainer string
}

type ibcIDs struct {
	ClientID     string
	ConnectionID string
	ChannelID    string
}

type topologyConfig struct {
	Gno      ibcIDs
	UnionGno ibcIDs
	UnionEVM ibcIDs
	EVM      ibcIDs
	GnoEVM   ibcIDs
	EVMGno   ibcIDs
}

func loadConfig() config {
	return config{
		Gno: gnoConfig{
			RPC:        getenv("GNO_RPC", "http://localhost:16657"),
			Indexer:    getenv("GNO_INDEXER", "http://localhost:48546/graphql/query"),
			ChainID:    getenv("GNO_CHAIN_ID", "dev"),
			KeyName:    getenv("GNO_KEY_NAME", "sender"),
			ComposeDir: getenv("GNO_COMPOSE_DIR", "."),
			Sender:     os.Getenv("GNO_SENDER_ADDR"),
		},
		Union: unionConfig{
			RPC:       getenv("UNION_RPC", "http://localhost:26657"),
			ChainID:   getenv("UNION_CHAIN_ID", "union-devnet-1"),
			Container: getenv("UNION_CONTAINER", "full-dev-setup-union-0-1"),
			Core:      getenv("UNION_CORE_CONTRACT", "union1nk3nes4ef6vcjan5tz6stf9g8p08q2kgqysx6q5exxh89zakp0msq5z79t"),
		},
		EVM: evmConfig{
			RPC:        getenv("EVM_RPC", "http://localhost:8545"),
			ChainID:    os.Getenv("EVM_CHAIN_ID"),
			IBCHandler: os.Getenv("EVM_IBC_HANDLER"),
			ZKGM:       os.Getenv("EVM_ZKGM_CONTRACT"),
			ERC20Impl:  os.Getenv("EVM_ERC20_IMPL"),
			Manager:    os.Getenv("EVM_MANAGER"),
			Recipient:  os.Getenv("EVM_RECIPIENT"),
			BeaconAPI:  getenv("BEACON_API", "http://localhost:9596"),
			PrivateKey: os.Getenv("EVM_PRIVATE_KEY"),
		},
		Voyager: voyagerConfig{
			Container:         getenv("VOYAGER_CONTAINER", "union-voyager-1"),
			ConfigPath:        getenv("VOYAGER_CONFIG_PATH", "/config/voyager-config.gno-union.jsonc"),
			PostgresContainer: getenv("POSTGRES_CONTAINER", "union-postgres-1"),
		},
		Topology: topologyConfig{
			Gno: ibcIDs{
				ClientID: os.Getenv("GNO_CLIENT_ID"),
			},
			UnionGno: ibcIDs{
				ClientID: os.Getenv("UNION_GNO_CLIENT_ID"),
			},
			UnionEVM: ibcIDs{
				ClientID: os.Getenv("UNION_EVM_CLIENT_ID"),
			},
			EVM: ibcIDs{
				ClientID: os.Getenv("EVM_UNION_CLIENT_ID"),
			},
			GnoEVM: ibcIDs{
				ClientID:     os.Getenv("GNO_EVM_CLIENT_ID"),
				ConnectionID: os.Getenv("GNO_EVM_CONNECTION_ID"),
				ChannelID:    os.Getenv("GNO_EVM_CHANNEL_ID"),
			},
			EVMGno: ibcIDs{
				ClientID:     os.Getenv("EVM_GNO_CLIENT_ID"),
				ConnectionID: os.Getenv("EVM_GNO_CONNECTION_ID"),
				ChannelID:    os.Getenv("EVM_GNO_CHANNEL_ID"),
			},
		},
		RunPackets: os.Getenv("RUN_PACKET_TESTS") == "1",
	}
}

func (c config) validatePacket() error {
	required := []struct{ name, value string }{
		{"GNO_CLIENT_ID", c.Topology.Gno.ClientID},
		{"UNION_GNO_CLIENT_ID", c.Topology.UnionGno.ClientID},
		{"UNION_EVM_CLIENT_ID", c.Topology.UnionEVM.ClientID},
		{"EVM_UNION_CLIENT_ID", c.Topology.EVM.ClientID},
		{"GNO_EVM_CLIENT_ID", c.Topology.GnoEVM.ClientID},
		{"GNO_EVM_CONNECTION_ID", c.Topology.GnoEVM.ConnectionID},
		{"GNO_EVM_CHANNEL_ID", c.Topology.GnoEVM.ChannelID},
		{"EVM_GNO_CLIENT_ID", c.Topology.EVMGno.ClientID},
		{"EVM_GNO_CONNECTION_ID", c.Topology.EVMGno.ConnectionID},
		{"EVM_GNO_CHANNEL_ID", c.Topology.EVMGno.ChannelID},
		{"GNO_KEY_NAME", c.Gno.KeyName},
		{"GNO_SENDER_ADDR", c.Gno.Sender},
		{"EVM_CHAIN_ID", c.EVM.ChainID},
		{"EVM_IBC_HANDLER", c.EVM.IBCHandler},
		{"EVM_ZKGM_CONTRACT", c.EVM.ZKGM},
		{"EVM_ERC20_IMPL", c.EVM.ERC20Impl},
		{"EVM_MANAGER", c.EVM.Manager},
		{"EVM_PRIVATE_KEY", c.EVM.PrivateKey},
		{"EVM_RECIPIENT", c.EVM.Recipient},
	}
	var missing []string
	for _, setting := range required {
		if setting.value == "" {
			missing = append(missing, setting.name)
		}
	}
	if len(missing) != 0 {
		return fmt.Errorf("missing required packet settings: %s", strings.Join(missing, ", "))
	}

	var invalid []string
	decimalSettings := []struct {
		name  string
		value string
		bits  int
	}{
		{"EVM_CHAIN_ID", c.EVM.ChainID, 64},
		{"GNO_CLIENT_ID", c.Topology.Gno.ClientID, 32},
		{"UNION_GNO_CLIENT_ID", c.Topology.UnionGno.ClientID, 32},
		{"UNION_EVM_CLIENT_ID", c.Topology.UnionEVM.ClientID, 32},
		{"EVM_UNION_CLIENT_ID", c.Topology.EVM.ClientID, 32},
		{"GNO_EVM_CLIENT_ID", c.Topology.GnoEVM.ClientID, 32},
		{"GNO_EVM_CONNECTION_ID", c.Topology.GnoEVM.ConnectionID, 32},
		{"GNO_EVM_CHANNEL_ID", c.Topology.GnoEVM.ChannelID, 32},
		{"EVM_GNO_CLIENT_ID", c.Topology.EVMGno.ClientID, 32},
		{"EVM_GNO_CONNECTION_ID", c.Topology.EVMGno.ConnectionID, 32},
		{"EVM_GNO_CHANNEL_ID", c.Topology.EVMGno.ChannelID, 32},
	}
	for _, setting := range decimalSettings {
		value, err := strconv.ParseUint(setting.value, 10, setting.bits)
		if err != nil || value == 0 {
			invalid = append(invalid, setting.name)
		}
	}
	for _, setting := range []struct{ name, value string }{
		{"EVM_IBC_HANDLER", c.EVM.IBCHandler},
		{"EVM_ZKGM_CONTRACT", c.EVM.ZKGM},
		{"EVM_ERC20_IMPL", c.EVM.ERC20Impl},
		{"EVM_MANAGER", c.EVM.Manager},
		{"EVM_RECIPIENT", c.EVM.Recipient},
	} {
		if !validHex(setting.value, 20) {
			invalid = append(invalid, setting.name)
		}
	}
	if !validHex(c.EVM.PrivateKey, 32) {
		invalid = append(invalid, "EVM_PRIVATE_KEY")
	}
	if len(invalid) != 0 {
		return fmt.Errorf("invalid packet settings: %s", strings.Join(invalid, ", "))
	}
	return nil
}

func validHex(value string, bytes int) bool {
	if len(value) != 2+bytes*2 || !strings.HasPrefix(value, "0x") {
		return false
	}
	_, err := hex.DecodeString(value[2:])
	return err == nil
}

func getenv(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}
