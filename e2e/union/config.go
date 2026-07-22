package unione2e

import (
	"fmt"
	"os"
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
	RPC             string
	ChainID         string
	Container       string
	Core            string
	ZKGM            string
	SignerKey       string
	SignerHome      string
	PacketSignerKey string
	PacketSender    string
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
			RPC:             getenv("UNION_RPC", "http://localhost:26657"),
			ChainID:         getenv("UNION_CHAIN_ID", "union-devnet-1"),
			Container:       getenv("UNION_CONTAINER", "full-dev-setup-union-0-1"),
			Core:            getenv("UNION_CORE_CONTRACT", "union1nk3nes4ef6vcjan5tz6stf9g8p08q2kgqysx6q5exxh89zakp0msq5z79t"),
			ZKGM:            getenv("UNION_ZKGM_CONTRACT", "union1rfz3ytg6l60wxk5rxsk27jvn2907cyav04sz8kde3xhmmf9nplxqr8y05c"),
			SignerKey:       getenv("UNION_SIGNER_KEY", "alice"),
			SignerHome:      getenv("UNION_SIGNER_HOME", "home"),
			PacketSignerKey: getenv("UNION_PACKET_SIGNER_KEY", "alice"),
			PacketSender:    getenv("UNION_PACKET_SENDER", "union1jk9psyhvgkrt2cumz8eytll2244m2nnz4yt2g2"),
		},
		EVM: evmConfig{
			RPC:        getenv("EVM_RPC", "http://localhost:8545"),
			ChainID:    getenv("EVM_CHAIN_ID", "32382"),
			IBCHandler: getenv("EVM_IBC_HANDLER", "0xed2af2aD7FE0D92011b26A2e5D1B4dC7D12A47C5"),
			ZKGM:       getenv("EVM_ZKGM", "0x05FD55C1AbE31D3ED09A76216cA8F0372f4B2eC5"),
			ERC20Impl:  getenv("EVM_ERC20_IMPL", "0x999709eB04e8A30C7aceD9fd920f7e04EE6B97bA"),
			Manager:    getenv("EVM_MANAGER", "0x6C1D11bE06908656D16EBFf5667F1C45372B7c89"),
			Recipient:  getenv("EVM_RECIPIENT", "0xBe68fC2d8249eb60bfCf0e71D5A0d2F2e292c4eD"),
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
				ClientID:     os.Getenv("GNO_CLIENT_ID"),
				ConnectionID: os.Getenv("GNO_PACKET_CONNECTION_ID"),
				ChannelID:    os.Getenv("GNO_PACKET_CHANNEL_ID"),
			},
			UnionGno: ibcIDs{
				ClientID:     os.Getenv("UNION_GNO_CLIENT_ID"),
				ConnectionID: os.Getenv("UNION_PACKET_CONNECTION_ID"),
				ChannelID:    os.Getenv("UNION_PACKET_CHANNEL_ID"),
			},
			UnionEVM: ibcIDs{
				ClientID:     os.Getenv("UNION_EVM_CLIENT_ID"),
				ConnectionID: os.Getenv("UNION_EVM_CONNECTION_ID"),
				ChannelID:    os.Getenv("UNION_EVM_CHANNEL_ID"),
			},
			EVM: ibcIDs{
				ClientID:     os.Getenv("EVM_UNION_CLIENT_ID"),
				ConnectionID: os.Getenv("EVM_UNION_CONNECTION_ID"),
				ChannelID:    os.Getenv("EVM_UNION_CHANNEL_ID"),
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
		{"GNO_PACKET_CONNECTION_ID", c.Topology.Gno.ConnectionID},
		{"GNO_PACKET_CHANNEL_ID", c.Topology.Gno.ChannelID},
		{"UNION_GNO_CLIENT_ID", c.Topology.UnionGno.ClientID},
		{"UNION_PACKET_CONNECTION_ID", c.Topology.UnionGno.ConnectionID},
		{"UNION_PACKET_CHANNEL_ID", c.Topology.UnionGno.ChannelID},
		{"UNION_EVM_CLIENT_ID", c.Topology.UnionEVM.ClientID},
		{"UNION_EVM_CONNECTION_ID", c.Topology.UnionEVM.ConnectionID},
		{"UNION_EVM_CHANNEL_ID", c.Topology.UnionEVM.ChannelID},
		{"EVM_UNION_CLIENT_ID", c.Topology.EVM.ClientID},
		{"EVM_UNION_CONNECTION_ID", c.Topology.EVM.ConnectionID},
		{"EVM_UNION_CHANNEL_ID", c.Topology.EVM.ChannelID},
		{"GNO_EVM_CLIENT_ID", c.Topology.GnoEVM.ClientID},
		{"GNO_EVM_CONNECTION_ID", c.Topology.GnoEVM.ConnectionID},
		{"GNO_EVM_CHANNEL_ID", c.Topology.GnoEVM.ChannelID},
		{"EVM_GNO_CLIENT_ID", c.Topology.EVMGno.ClientID},
		{"EVM_GNO_CONNECTION_ID", c.Topology.EVMGno.ConnectionID},
		{"EVM_GNO_CHANNEL_ID", c.Topology.EVMGno.ChannelID},
		{"GNO_KEY_NAME", c.Gno.KeyName},
		{"GNO_SENDER_ADDR", c.Gno.Sender},
		{"UNION_SIGNER_KEY", c.Union.SignerKey},
		{"UNION_SIGNER_HOME", c.Union.SignerHome},
		{"UNION_PACKET_SIGNER_KEY", c.Union.PacketSignerKey},
		{"UNION_PACKET_SENDER", c.Union.PacketSender},
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
	return nil
}

func getenv(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}
