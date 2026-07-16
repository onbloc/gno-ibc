// PKGPATH: gno.land/r/onbloc/ibc/scenario/union/events
package events

import (
	"testing"

	"gno.land/p/nt/ufmt/v0"
	"gno.land/p/onbloc/ibc/union/lightclient"
	"gno.land/p/onbloc/ibc/union/types"

	"gno.land/r/onbloc/ibc/union/access"
	"gno.land/r/onbloc/ibc/union/core"
	_ "gno.land/r/onbloc/ibc/union/core/v1"
)

const (
	packetSplitCoreImplPath = "gno.land/r/onbloc/ibc/union/core/v1"

	packetSplitAdminAddr      = address("g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5")
	packetSplitMockClientType = types.ClientType("scenario-packet-split-lc")

	// packetSplitDataLen hex-encodes to 4098 chars ("0x" + 4096 hex digits),
	// two chars over the config's default MaxEventAttrValueLen (4096), so
	// it splits into packet_data[0] (4096 chars) and packet_data[1] (2
	// chars) under the default settings -- no SetMaxEventAttrValueLen
	// override.
	packetSplitDataLen = 2048
)

func main(cur realm) {
	ufmt.Println("[SCENARIO] default event config splits an oversized packet_data attr")

	setupPacketSplitScenario(cur)
	channelId := openPacketSplitChannel(cur)
	sendOversizedPacket(cur, channelId)
}

func setupPacketSplitScenario(cur realm) {
	ufmt.Println("[STEP] bootstrap core proxy")

	testing.SetRealm(testing.NewUserRealm(packetSplitAdminAddr))
	core.UpdateImpl(cross(cur), packetSplitCoreImplPath)
	access.GrantRole(cross(cur), access.RelayerRole, packetSplitAdminAddr)
}

func openPacketSplitChannel(cur realm) types.ChannelId {
	ufmt.Println("[STEP] open packet split channel")

	testing.SetRealm(testing.NewUserRealm(packetSplitAdminAddr))
	core.RegisterClient(cross(cur), packetSplitMockClientType, func(_, _ []byte) (lightclient.Interface, error) {
		return &packetSplitMockLightClient{}, nil
	})
	core.CreateClient(cross(cur), core.NewMsgCreateClient(packetSplitMockClientType, nil, nil))
	clientId := types.ClientId(1)

	core.ConnectionOpenInit(cross(cur), core.NewMsgConnectionOpenInit(clientId, types.ClientId(99)))
	connectionId := types.ConnectionId(1)
	core.ConnectionOpenAck(cross(cur), core.NewMsgConnectionOpenAck(connectionId, types.ConnectionId(77), nil, 1))

	core.RegisterApp(cross(cur), &packetSplitScenarioApp{})
	portId := []byte(cur.PkgPath())
	core.ChannelOpenInit(cross(cur), core.NewMsgChannelOpenInit(portId, portId, connectionId, "packet-split-v1", "g1relayer"))
	channelId := types.ChannelId(1)
	core.ChannelOpenAck(cross(cur), core.NewMsgChannelOpenAck(channelId, "packet-split-v1", types.ChannelId(7), nil, 1, "g1relayer"))

	ufmt.Printf("[INFO] channel_id: %s\n", channelId.String())
	return channelId
}

func sendOversizedPacket(cur realm, channelId types.ChannelId) {
	ufmt.Println("[STEP] send packet with data exceeding the default max event attr value len")

	config := core.GetEventConfig()
	ufmt.Printf("[INFO] split_event_attrs: %t\n", config.SplitEventAttrs)
	ufmt.Printf("[INFO] max_event_attr_value_len: %d\n", config.MaxEventAttrValueLen)

	data := packetSplitLargeData()
	ufmt.Printf("[INFO] packet_data_size: %d\n", len(data)*2+2)

	testing.SetRealm(testing.NewUserRealm(packetSplitAdminAddr))
	core.SendPacket(cross(cur), channelId, types.Timestamp(1), data)
	ufmt.Println("[EXPECTED] PacketSend uses packet_data[0] and packet_data[1]")
}

func packetSplitLargeData() []byte {
	data := make([]byte, packetSplitDataLen)
	for i := range data {
		data[i] = byte(i)
	}
	return data
}

type packetSplitScenarioApp struct{}

func (*packetSplitScenarioApp) OnChannelOpenInit(_ realm, _ types.ConnectionId, _ types.ChannelId, _ string, _ address) {
}

func (*packetSplitScenarioApp) OnChannelOpenTry(_ realm, _ types.ConnectionId, _ types.ChannelId, _ string, _ string, _ address) {
}

func (*packetSplitScenarioApp) OnChannelOpenAck(_ realm, _ types.ChannelId, _ types.ChannelId, _ string, _ address) {
}

func (*packetSplitScenarioApp) OnChannelOpenConfirm(_ realm, _ types.ChannelId, _ address) {
}

func (*packetSplitScenarioApp) OnChannelCloseInit(_ realm, _ types.ChannelId, _ address) {
}

func (*packetSplitScenarioApp) OnChannelCloseConfirm(_ realm, _ types.ChannelId, _ address) {
}

func (*packetSplitScenarioApp) OnRecvPacket(_ realm, _ types.Packet, _ address, _ []byte) types.RecvPacketResult {
	return core.NewRecvPacketResult(types.PacketStatusSuccess, nil)
}

func (*packetSplitScenarioApp) OnIntentRecvPacket(_ realm, _ types.Packet, _ address, _ []byte) types.RecvPacketResult {
	return core.NewRecvPacketResult(types.PacketStatusSuccess, nil)
}

func (*packetSplitScenarioApp) OnAcknowledgementPacket(_ realm, _ types.Packet, _ []byte, _ address) {
}

func (*packetSplitScenarioApp) OnTimeoutPacket(_ realm, _ types.Packet, _ address) {
}

type packetSplitMockLightClient struct{}

func (m *packetSplitMockLightClient) VerifyMembership(uint64, []byte, []byte, []byte) error {
	return nil
}

func (m *packetSplitMockLightClient) VerifyNonMembership(uint64, []byte, []byte) error {
	return nil
}

func (m *packetSplitMockLightClient) GetTimestamp() types.Timestamp {
	return types.Timestamp(1)
}

func (m *packetSplitMockLightClient) GetTimestampAtHeight(uint64) (types.Timestamp, error) {
	return types.Timestamp(1), nil
}

func (m *packetSplitMockLightClient) GetLatestHeight() uint64 {
	return 1
}

func (m *packetSplitMockLightClient) GetCounterpartyChainID() string {
	return "mock-chain"
}

func (m *packetSplitMockLightClient) Status() lightclient.Status {
	return lightclient.Active
}

func (m *packetSplitMockLightClient) VerifyHeader(_ address, header []byte, _ address) (types.StateUpdate, error) {
	return types.StateUpdate{Height: 1, ClientStateBytes: header, ConsensusStateBytes: header}, nil
}

func (m *packetSplitMockLightClient) VerifyCreation(address, address) (types.ClientCreationResult, error) {
	return types.ClientCreationResult{}, nil
}

func (m *packetSplitMockLightClient) Misbehaviour(address, []byte, address) ([]byte, error) {
	return nil, errPacketSplitMisbehaviourUnsupported
}

var errPacketSplitMisbehaviourUnsupported = packetSplitMockError("mock: misbehaviour unsupported")

type packetSplitMockError string

func (e packetSplitMockError) Error() string {
	return string(e)
}

// Output:
// [SCENARIO] default event config splits an oversized packet_data attr
// [STEP] bootstrap core proxy
// [STEP] open packet split channel
// [INFO] channel_id: 1
// [STEP] send packet with data exceeding the default max event attr value len
// [INFO] split_event_attrs: true
// [INFO] max_event_attr_value_len: 4096
// [INFO] packet_data_size: 4098
// [EXPECTED] PacketSend uses packet_data[0] and packet_data[1]

// Events:
// [
//   {
//     "type": "RoleGranted",
//     "attrs": [
//       {
//         "key": "role_id",
//         "value": "1"
//       },
//       {
//         "key": "account",
//         "value": "g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5"
//       },
//       {
//         "key": "since",
//         "value": "1234567890"
//       },
//       {
//         "key": "new_member",
//         "value": "true"
//       }
//     ],
//     "pkg_path": "gno.land/r/onbloc/ibc/union/access"
//   },
//   {
//     "type": "RegisterClient",
//     "attrs": [
//       {
//         "key": "client_type",
//         "value": "scenario-packet-split-lc"
//       }
//     ],
//     "pkg_path": "gno.land/r/onbloc/ibc/union/core"
//   },
//   {
//     "type": "CreateClient",
//     "attrs": [
//       {
//         "key": "client_id",
//         "value": "1"
//       },
//       {
//         "key": "client_type",
//         "value": "scenario-packet-split-lc"
//       },
//       {
//         "key": "counterparty_chain_id",
//         "value": "mock-chain"
//       }
//     ],
//     "pkg_path": "gno.land/r/onbloc/ibc/union/core"
//   },
//   {
//     "type": "ConnectionOpenInit",
//     "attrs": [
//       {
//         "key": "connection_id",
//         "value": "1"
//       },
//       {
//         "key": "client_id",
//         "value": "1"
//       },
//       {
//         "key": "counterparty_client_id",
//         "value": "99"
//       }
//     ],
//     "pkg_path": "gno.land/r/onbloc/ibc/union/core"
//   },
//   {
//     "type": "ConnectionOpenAck",
//     "attrs": [
//       {
//         "key": "connection_id",
//         "value": "1"
//       },
//       {
//         "key": "client_id",
//         "value": "1"
//       },
//       {
//         "key": "counterparty_client_id",
//         "value": "99"
//       },
//       {
//         "key": "counterparty_connection_id",
//         "value": "77"
//       }
//     ],
//     "pkg_path": "gno.land/r/onbloc/ibc/union/core"
//   },
//   {
//     "type": "AppRegistered",
//     "attrs": [
//       {
//         "key": "port_id",
//         "value": ""
//       },
//       {
//         "key": "registrar_pkg_path",
//         "value": ""
//       },
//       {
//         "key": "admin_override",
//         "value": "false"
//       }
//     ],
//     "pkg_path": "gno.land/r/onbloc/ibc/union/core"
//   },
//   {
//     "type": "ChannelOpenInit",
//     "attrs": [
//       {
//         "key": "port_id",
//         "value": ""
//       },
//       {
//         "key": "channel_id",
//         "value": "1"
//       },
//       {
//         "key": "counterparty_port_id",
//         "value": "0x"
//       },
//       {
//         "key": "connection_id",
//         "value": "1"
//       },
//       {
//         "key": "connection_client_id",
//         "value": "1"
//       },
//       {
//         "key": "connection_counterparty_client_id",
//         "value": "99"
//       },
//       {
//         "key": "connection_counterparty_connection_id",
//         "value": "77"
//       },
//       {
//         "key": "version",
//         "value": "packet-split-v1"
//       }
//     ],
//     "pkg_path": "gno.land/r/onbloc/ibc/union/core"
//   },
//   {
//     "type": "ChannelOpenAck",
//     "attrs": [
//       {
//         "key": "port_id",
//         "value": ""
//       },
//       {
//         "key": "channel_id",
//         "value": "1"
//       },
//       {
//         "key": "counterparty_port_id",
//         "value": "0x"
//       },
//       {
//         "key": "counterparty_channel_id",
//         "value": "7"
//       },
//       {
//         "key": "connection_id",
//         "value": "1"
//       },
//       {
//         "key": "connection_client_id",
//         "value": "1"
//       },
//       {
//         "key": "connection_counterparty_client_id",
//         "value": "99"
//       },
//       {
//         "key": "connection_counterparty_connection_id",
//         "value": "77"
//       },
//       {
//         "key": "version",
//         "value": "packet-split-v1"
//       }
//     ],
//     "pkg_path": "gno.land/r/onbloc/ibc/union/core"
//   },
//   {
//     "type": "PacketSend",
//     "attrs": [
//       {
//         "key": "packet_hash",
//         "value": "0x402e500b97fe954d7f7a5689b627053880c5674c7debb308b5d1d341fbedcddf"
//       },
//       {
//         "key": "source_channel_id",
//         "value": "1"
//       },
//       {
//         "key": "source_channel_version",
//         "value": "packet-split-v1"
//       },
//       {
//         "key": "source_connection_id",
//         "value": "1"
//       },
//       {
//         "key": "source_connection_client_id",
//         "value": "1"
//       },
//       {
//         "key": "destination_channel_id",
//         "value": "7"
//       },
//       {
//         "key": "destination_connection_id",
//         "value": "77"
//       },
//       {
//         "key": "destination_connection_client_id",
//         "value": "99"
//       },
//       {
//         "key": "timeout_timestamp",
//         "value": "1"
//       },
//       {
//         "key": "packet_data_size",
//         "value": "4098"
//       },
//       {
//         "key": "packet_data[0]",
//         "value": "0x000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f404142434445464748494a4b4c4d4e4f505152535455565758595a5b5c5d5e5f606162636465666768696a6b6c6d6e6f707172737475767778797a7b7c7d7e7f808182838485868788898a8b8c8d8e8f909192939495969798999a9b9c9d9e9fa0a1a2a3a4a5a6a7a8a9aaabacadaeafb0b1b2b3b4b5b6b7b8b9babbbcbdbebfc0c1c2c3c4c5c6c7c8c9cacbcccdcecfd0d1d2d3d4d5d6d7d8d9dadbdcdddedfe0e1e2e3e4e5e6e7e8e9eaebecedeeeff0f1f2f3f4f5f6f7f8f9fafbfcfdfeff000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f404142434445464748494a4b4c4d4e4f505152535455565758595a5b5c5d5e5f606162636465666768696a6b6c6d6e6f707172737475767778797a7b7c7d7e7f808182838485868788898a8b8c8d8e8f909192939495969798999a9b9c9d9e9fa0a1a2a3a4a5a6a7a8a9aaabacadaeafb0b1b2b3b4b5b6b7b8b9babbbcbdbebfc0c1c2c3c4c5c6c7c8c9cacbcccdcecfd0d1d2d3d4d5d6d7d8d9dadbdcdddedfe0e1e2e3e4e5e6e7e8e9eaebecedeeeff0f1f2f3f4f5f6f7f8f9fafbfcfdfeff000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f404142434445464748494a4b4c4d4e4f505152535455565758595a5b5c5d5e5f606162636465666768696a6b6c6d6e6f707172737475767778797a7b7c7d7e7f808182838485868788898a8b8c8d8e8f909192939495969798999a9b9c9d9e9fa0a1a2a3a4a5a6a7a8a9aaabacadaeafb0b1b2b3b4b5b6b7b8b9babbbcbdbebfc0c1c2c3c4c5c6c7c8c9cacbcccdcecfd0d1d2d3d4d5d6d7d8d9dadbdcdddedfe0e1e2e3e4e5e6e7e8e9eaebecedeeeff0f1f2f3f4f5f6f7f8f9fafbfcfdfeff000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f404142434445464748494a4b4c4d4e4f505152535455565758595a5b5c5d5e5f606162636465666768696a6b6c6d6e6f707172737475767778797a7b7c7d7e7f808182838485868788898a8b8c8d8e8f909192939495969798999a9b9c9d9e9fa0a1a2a3a4a5a6a7a8a9aaabacadaeafb0b1b2b3b4b5b6b7b8b9babbbcbdbebfc0c1c2c3c4c5c6c7c8c9cacbcccdcecfd0d1d2d3d4d5d6d7d8d9dadbdcdddedfe0e1e2e3e4e5e6e7e8e9eaebecedeeeff0f1f2f3f4f5f6f7f8f9fafbfcfdfeff000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f404142434445464748494a4b4c4d4e4f505152535455565758595a5b5c5d5e5f606162636465666768696a6b6c6d6e6f707172737475767778797a7b7c7d7e7f808182838485868788898a8b8c8d8e8f909192939495969798999a9b9c9d9e9fa0a1a2a3a4a5a6a7a8a9aaabacadaeafb0b1b2b3b4b5b6b7b8b9babbbcbdbebfc0c1c2c3c4c5c6c7c8c9cacbcccdcecfd0d1d2d3d4d5d6d7d8d9dadbdcdddedfe0e1e2e3e4e5e6e7e8e9eaebecedeeeff0f1f2f3f4f5f6f7f8f9fafbfcfdfeff000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f404142434445464748494a4b4c4d4e4f505152535455565758595a5b5c5d5e5f606162636465666768696a6b6c6d6e6f707172737475767778797a7b7c7d7e7f808182838485868788898a8b8c8d8e8f909192939495969798999a9b9c9d9e9fa0a1a2a3a4a5a6a7a8a9aaabacadaeafb0b1b2b3b4b5b6b7b8b9babbbcbdbebfc0c1c2c3c4c5c6c7c8c9cacbcccdcecfd0d1d2d3d4d5d6d7d8d9dadbdcdddedfe0e1e2e3e4e5e6e7e8e9eaebecedeeeff0f1f2f3f4f5f6f7f8f9fafbfcfdfeff000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f404142434445464748494a4b4c4d4e4f505152535455565758595a5b5c5d5e5f606162636465666768696a6b6c6d6e6f707172737475767778797a7b7c7d7e7f808182838485868788898a8b8c8d8e8f909192939495969798999a9b9c9d9e9fa0a1a2a3a4a5a6a7a8a9aaabacadaeafb0b1b2b3b4b5b6b7b8b9babbbcbdbebfc0c1c2c3c4c5c6c7c8c9cacbcccdcecfd0d1d2d3d4d5d6d7d8d9dadbdcdddedfe0e1e2e3e4e5e6e7e8e9eaebecedeeeff0f1f2f3f4f5f6f7f8f9fafbfcfdfeff000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f404142434445464748494a4b4c4d4e4f505152535455565758595a5b5c5d5e5f606162636465666768696a6b6c6d6e6f707172737475767778797a7b7c7d7e7f808182838485868788898a8b8c8d8e8f909192939495969798999a9b9c9d9e9fa0a1a2a3a4a5a6a7a8a9aaabacadaeafb0b1b2b3b4b5b6b7b8b9babbbcbdbebfc0c1c2c3c4c5c6c7c8c9cacbcccdcecfd0d1d2d3d4d5d6d7d8d9dadbdcdddedfe0e1e2e3e4e5e6e7e8e9eaebecedeeeff0f1f2f3f4f5f6f7f8f9fafbfcfdfe"
//       },
//       {
//         "key": "packet_data[1]",
//         "value": "ff"
//       }
//     ],
//     "pkg_path": "gno.land/r/onbloc/ibc/union/core"
//   }
// ]
