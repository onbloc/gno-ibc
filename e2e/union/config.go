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
	UnionCoreContract       string
	UnionSignerKey          string
	EVMRPC                  string
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
		UnionGnoClientID:        getenv("UNION_GNO_CLIENT_ID", "4"),
		UnionCoreContract:       getenv("UNION_CORE_CONTRACT", "union1nk3nes4ef6vcjan5tz6stf9g8p08q2kgqysx6q5exxh89zakp0msq5z79t"),
		UnionSignerKey:          getenv("UNION_SIGNER_KEY", "voyager-relayer"),
		EVMRPC:                  getenv("EVM_RPC", "http://localhost:8545"),
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
