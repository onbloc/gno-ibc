package unione2e

import "os"

type config struct {
	GNORPC         string
	GnoIndexer     string
	GNOChainID     string
	GNOKeyName     string
	GNOComposeDir  string
	UnionRPC       string
	UnionREST      string
	UnionChainID   string
	EVMRPC         string
	BeaconAPI      string
	PostgresAddr   string
	RunPacketTests bool
}

func loadConfig() config {
	return config{
		GNORPC:         getenv("GNO_RPC", "http://localhost:16657"),
		GnoIndexer:     getenv("GNO_INDEXER", "http://localhost:48546/graphql/query"),
		GNOChainID:     getenv("GNO_CHAIN_ID", "dev"),
		GNOKeyName:     getenv("GNO_KEY_NAME", "relayer"),
		GNOComposeDir:  getenv("GNO_COMPOSE_DIR", "."),
		UnionRPC:       getenv("UNION_RPC", "http://localhost:26657"),
		UnionREST:      getenv("UNION_REST", "http://localhost:1317"),
		UnionChainID:   getenv("UNION_CHAIN_ID", "union-devnet-1"),
		EVMRPC:         getenv("EVM_RPC", "http://localhost:8545"),
		BeaconAPI:      getenv("BEACON_API", "http://localhost:9596"),
		PostgresAddr:   os.Getenv("POSTGRES_ADDR"),
		RunPacketTests: os.Getenv("RUN_PACKET_TESTS") == "1",
	}
}

func getenv(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}
