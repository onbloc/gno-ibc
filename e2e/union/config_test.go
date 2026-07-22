package unione2e

import "testing"

func TestLoadConfig(t *testing.T) {
	for key, value := range map[string]string{
		"GNO_RPC":               "gno-rpc",
		"GNO_SENDER_ADDR":       "gno-sender",
		"UNION_CORE_CONTRACT":   "union-core",
		"EVM_IBC_HANDLER":       "evm-handler",
		"EVM_PRIVATE_KEY":       "evm-key",
		"VOYAGER_CONTAINER":     "voyager",
		"POSTGRES_CONTAINER":    "postgres",
		"GNO_CLIENT_ID":         "gno-client",
		"UNION_GNO_CLIENT_ID":   "union-gno-client",
		"UNION_EVM_CLIENT_ID":   "union-evm-client",
		"EVM_UNION_CLIENT_ID":   "evm-union-client",
		"GNO_EVM_CLIENT_ID":     "gno-evm-client",
		"GNO_EVM_CONNECTION_ID": "gno-evm-connection",
		"GNO_EVM_CHANNEL_ID":    "gno-evm-channel",
		"EVM_GNO_CLIENT_ID":     "evm-gno-client",
		"EVM_GNO_CONNECTION_ID": "evm-gno-connection",
		"EVM_GNO_CHANNEL_ID":    "evm-gno-channel",
		"RUN_PACKET_TESTS":      "1",
	} {
		t.Setenv(key, value)
	}

	cfg := loadConfig()
	checks := map[string][2]string{
		"Gno.RPC":                      {cfg.Gno.RPC, "gno-rpc"},
		"Gno.Sender":                   {cfg.Gno.Sender, "gno-sender"},
		"Union.Core":                   {cfg.Union.Core, "union-core"},
		"EVM.IBCHandler":               {cfg.EVM.IBCHandler, "evm-handler"},
		"EVM.PrivateKey":               {cfg.EVM.PrivateKey, "evm-key"},
		"Voyager.Container":            {cfg.Voyager.Container, "voyager"},
		"Voyager.PostgresContainer":    {cfg.Voyager.PostgresContainer, "postgres"},
		"Topology.Gno.ClientID":        {cfg.Topology.Gno.ClientID, "gno-client"},
		"Topology.UnionGno.ClientID":   {cfg.Topology.UnionGno.ClientID, "union-gno-client"},
		"Topology.UnionEVM.ClientID":   {cfg.Topology.UnionEVM.ClientID, "union-evm-client"},
		"Topology.EVM.ClientID":        {cfg.Topology.EVM.ClientID, "evm-union-client"},
		"Topology.GnoEVM.ClientID":     {cfg.Topology.GnoEVM.ClientID, "gno-evm-client"},
		"Topology.GnoEVM.ConnectionID": {cfg.Topology.GnoEVM.ConnectionID, "gno-evm-connection"},
		"Topology.GnoEVM.ChannelID":    {cfg.Topology.GnoEVM.ChannelID, "gno-evm-channel"},
		"Topology.EVMGno.ClientID":     {cfg.Topology.EVMGno.ClientID, "evm-gno-client"},
		"Topology.EVMGno.ConnectionID": {cfg.Topology.EVMGno.ConnectionID, "evm-gno-connection"},
		"Topology.EVMGno.ChannelID":    {cfg.Topology.EVMGno.ChannelID, "evm-gno-channel"},
	}
	for field, values := range checks {
		if got, want := values[0], values[1]; got != want {
			t.Errorf("%s = %q, want %q", field, got, want)
		}
	}
	if !cfg.RunPackets {
		t.Error("RunPackets was not loaded")
	}
}

func TestValidatePacketReportsAllMissingSettings(t *testing.T) {
	cfg := config{
		Gno: gnoConfig{KeyName: "sender", Sender: "g1sender"},
		EVM: evmConfig{PrivateKey: "key", Recipient: "0xrecipient"},
		Topology: topologyConfig{
			Gno:      ibcIDs{ClientID: "1"},
			UnionGno: ibcIDs{ClientID: "2"},
			UnionEVM: ibcIDs{ClientID: "3"},
			EVM:      ibcIDs{ClientID: "4"},
			GnoEVM:   ibcIDs{ClientID: "5", ConnectionID: "6"},
			EVMGno:   ibcIDs{ClientID: "7", ConnectionID: "8", ChannelID: "9"},
		},
	}

	err := cfg.validatePacket()
	if err == nil {
		t.Fatal("validatePacket() succeeded with missing settings")
	}
	if got, want := err.Error(), "missing required packet settings: GNO_EVM_CHANNEL_ID"; got != want {
		t.Fatalf("validatePacket() = %q, want %q", got, want)
	}
}
