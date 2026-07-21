package unione2e

import "testing"

func TestLoadConfig(t *testing.T) {
	for key, value := range map[string]string{
		"GNO_RPC":                 "gno-rpc",
		"GNO_SENDER_ADDR":         "gno-sender",
		"UNION_CORE_CONTRACT":     "union-core",
		"UNION_PACKET_SENDER":     "union-sender",
		"EVM_IBC_HANDLER":         "evm-handler",
		"EVM_PRIVATE_KEY":         "evm-key",
		"VOYAGER_CONTAINER":       "voyager",
		"POSTGRES_CONTAINER":      "postgres",
		"GNO_PACKET_CHANNEL_ID":   "gno-channel",
		"UNION_GNO_CLIENT_ID":     "union-gno-client",
		"UNION_EVM_CONNECTION_ID": "union-evm-connection",
		"EVM_UNION_CHANNEL_ID":    "evm-channel",
		"RUN_PACKET_TESTS":        "1",
	} {
		t.Setenv(key, value)
	}

	cfg := loadConfig()
	checks := map[string][2]string{
		"Gno.RPC":                        {cfg.Gno.RPC, "gno-rpc"},
		"Gno.Sender":                     {cfg.Gno.Sender, "gno-sender"},
		"Union.Core":                     {cfg.Union.Core, "union-core"},
		"Union.PacketSender":             {cfg.Union.PacketSender, "union-sender"},
		"EVM.IBCHandler":                 {cfg.EVM.IBCHandler, "evm-handler"},
		"EVM.PrivateKey":                 {cfg.EVM.PrivateKey, "evm-key"},
		"Voyager.Container":              {cfg.Voyager.Container, "voyager"},
		"Voyager.PostgresContainer":      {cfg.Voyager.PostgresContainer, "postgres"},
		"Topology.Gno.ChannelID":         {cfg.Topology.Gno.ChannelID, "gno-channel"},
		"Topology.UnionGno.ClientID":     {cfg.Topology.UnionGno.ClientID, "union-gno-client"},
		"Topology.UnionEVM.ConnectionID": {cfg.Topology.UnionEVM.ConnectionID, "union-evm-connection"},
		"Topology.EVM.ChannelID":         {cfg.Topology.EVM.ChannelID, "evm-channel"},
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
		Gno:   gnoConfig{KeyName: "sender", Sender: "g1sender"},
		Union: unionConfig{SignerKey: "alice", SignerHome: "home", PacketSignerKey: "alice", PacketSender: "union1sender"},
		EVM:   evmConfig{PrivateKey: "key", Recipient: "0xrecipient"},
		Topology: topologyConfig{
			Gno:      ibcIDs{ClientID: "1", ChannelID: "2"},
			UnionGno: ibcIDs{ClientID: "3", ConnectionID: "4", ChannelID: "5"},
			UnionEVM: ibcIDs{ClientID: "6", ConnectionID: "7"},
			EVM:      ibcIDs{ClientID: "8", ConnectionID: "9", ChannelID: "10"},
		},
	}

	err := cfg.validatePacket()
	if err == nil {
		t.Fatal("validatePacket() succeeded with missing settings")
	}
	if got, want := err.Error(), "missing required packet settings: GNO_PACKET_CONNECTION_ID, UNION_EVM_CHANNEL_ID"; got != want {
		t.Fatalf("validatePacket() = %q, want %q", got, want)
	}
}
