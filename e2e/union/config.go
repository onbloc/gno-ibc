package unione2e

import "os"

type config struct {
	GNORPC                  string
	GnoIndexer              string
	GNOChainID              string
	GNOKeyName              string
	GNOComposeDir           string
	GnoPacketConnectionID   string
	GnoPacketChannelID      string
	UnionRPC                string
	UnionREST               string
	UnionChainID            string
	UnionContainer          string
	UnionPacketChannelID    string
	UnionPacketConnectionID string
	VoyagerContainer        string
	VoyagerConfig           string
	PostgresContainer       string
	UnionGnoClientID        string
	UnionEVMClientID        string
	UnionCoreContract       string
	UnionZKGMContract       string
	UnionTokenMinter        string
	UnionSignerKey          string
	UnionPacketSignerKey    string
	UnionPacketSender       string
	UnionEVMConnectionID    string
	UnionEVMChannelID       string
	EVMRPC                  string
	EVMChainID              string
	EVMUnionClientID        string
	EVMUnionConnectionID    string
	EVMUnionChannelID       string
	EVMIBCHandler           string
	EVMZKGM                 string
	EVMERC20Impl            string
	EVMManager              string
	EVMRecipient            string
	EVMWrappedToken         string
	BeaconAPI               string
	PostgresAddr            string
	RunPacketTests          bool
}

func loadConfig() config {
	return config{
		GNORPC:                  getenv("GNO_RPC", "http://localhost:16657"),
		GnoIndexer:              getenv("GNO_INDEXER", "http://localhost:48546/graphql/query"),
		GNOChainID:              getenv("GNO_CHAIN_ID", "dev"),
		GNOKeyName:              getenv("GNO_KEY_NAME", "sender"),
		GNOComposeDir:           getenv("GNO_COMPOSE_DIR", "."),
		GnoPacketConnectionID:   getenv("GNO_PACKET_CONNECTION_ID", "5"),
		GnoPacketChannelID:      getenv("GNO_PACKET_CHANNEL_ID", "3"),
		UnionRPC:                getenv("UNION_RPC", "http://localhost:26657"),
		UnionREST:               getenv("UNION_REST", "http://localhost:1317"),
		UnionChainID:            getenv("UNION_CHAIN_ID", "union-devnet-1"),
		UnionContainer:          getenv("UNION_CONTAINER", "full-dev-setup-union-0-1"),
		UnionPacketChannelID:    getenv("UNION_PACKET_CHANNEL_ID", "2"),
		UnionPacketConnectionID: getenv("UNION_PACKET_CONNECTION_ID", "3"),
		VoyagerContainer:        getenv("VOYAGER_CONTAINER", "union-voyager-1"),
		VoyagerConfig:           getenv("VOYAGER_CONFIG_PATH", "/config/voyager-config.gno-union.jsonc"),
		PostgresContainer:       getenv("POSTGRES_CONTAINER", "union-postgres-1"),
		UnionGnoClientID:        getenv("UNION_GNO_CLIENT_ID", "1"),
		UnionEVMClientID:        getenv("UNION_EVM_CLIENT_ID", "7"),
		UnionCoreContract:       getenv("UNION_CORE_CONTRACT", "union1nk3nes4ef6vcjan5tz6stf9g8p08q2kgqysx6q5exxh89zakp0msq5z79t"),
		UnionZKGMContract:       getenv("UNION_ZKGM_CONTRACT", "union1rfz3ytg6l60wxk5rxsk27jvn2907cyav04sz8kde3xhmmf9nplxqr8y05c"),
		UnionTokenMinter:        getenv("UNION_TOKEN_MINTER", "union1tylj088axudzec7jmfenw9n7swhlg9y7h0ctmfnw8j2z0pqkvj2qkajn8m"),
		UnionSignerKey:          getenv("UNION_SIGNER_KEY", "voyager-relayer"),
		UnionPacketSignerKey:    getenv("UNION_PACKET_SIGNER_KEY", "voyager-admin"),
		UnionPacketSender:       getenv("UNION_PACKET_SENDER", "union1jk9psyhvgkrt2cumz8eytll2244m2nnz4yt2g2"),
		UnionEVMConnectionID:    getenv("UNION_EVM_CONNECTION_ID", "6"),
		UnionEVMChannelID:       getenv("UNION_EVM_CHANNEL_ID", "5"),
		EVMRPC:                  getenv("EVM_RPC", "http://localhost:8545"),
		EVMChainID:              getenv("EVM_CHAIN_ID", "32382"),
		EVMUnionClientID:        getenv("EVM_UNION_CLIENT_ID", "1"),
		EVMUnionConnectionID:    getenv("EVM_UNION_CONNECTION_ID", "1"),
		EVMUnionChannelID:       getenv("EVM_UNION_CHANNEL_ID", "1"),
		EVMIBCHandler:           getenv("EVM_IBC_HANDLER", "0xed2af2aD7FE0D92011b26A2e5D1B4dC7D12A47C5"),
		EVMZKGM:                 getenv("EVM_ZKGM", "0x05FD55C1AbE31D3ED09A76216cA8F0372f4B2eC5"),
		EVMERC20Impl:            getenv("EVM_ERC20_IMPL", "0x999709eB04e8A30C7aceD9fd920f7e04EE6B97bA"),
		EVMManager:              getenv("EVM_MANAGER", "0x6C1D11bE06908656D16EBFf5667F1C45372B7c89"),
		EVMRecipient:            getenv("EVM_RECIPIENT", "0xBe68fC2d8249eb60bfCf0e71D5A0d2F2e292c4eD"),
		EVMWrappedToken:         os.Getenv("EVM_WRAPPED_TOKEN"),
		BeaconAPI:               getenv("BEACON_API", "http://localhost:9596"),
		PostgresAddr:            os.Getenv("POSTGRES_ADDR"),
		RunPacketTests:          os.Getenv("RUN_PACKET_TESTS") == "1",
	}
}

func getenv(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}
