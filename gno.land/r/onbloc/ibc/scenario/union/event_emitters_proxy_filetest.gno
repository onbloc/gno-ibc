// PKGPATH: gno.land/r/onbloc/ibc/scenario/union
package union

import (
	"testing"

	"gno.land/p/nt/ufmt/v0"
	"gno.land/p/onbloc/ibc/union/lightclient"
	"gno.land/p/onbloc/ibc/union/types"

	"gno.land/r/onbloc/ibc/union/access"
	zkgm "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm"
	_ "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/v1"
	"gno.land/r/onbloc/ibc/union/core"
	_ "gno.land/r/onbloc/ibc/union/core/v1"
)

const (
	eventCoreImplPath = "gno.land/r/onbloc/ibc/union/core/v1"
	eventZkgmImplPath = "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/v1"

	eventAdminAddr      = address("g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5")
	eventMockClientType = types.ClientType("scenario-event-mock-lc")
)

func main(cur realm) {
	ufmt.Println("[SCENARIO] proxy event emitters")

	setupProxyEventEmitters(cur)
	clientId := exerciseClientEventEmitters(cur)
	connectionId := exerciseConnectionEventEmitters(cur, clientId)
	eventChannelId, closeConfirmChannelId := exerciseChannelOpenEventEmitters(cur, connectionId)
	exercisePacketEventEmitters(cur, clientId, eventChannelId)
	exerciseChannelCloseEventEmitters(cur, eventChannelId, closeConfirmChannelId)
	exerciseZkgmRecvErrorEmitter(cur, connectionId)
	exerciseMisbehaviourEmitter(cur, clientId)
}

func setupProxyEventEmitters(cur realm) {
	testing.SetRealm(testing.NewUserRealm(eventAdminAddr))
	core.UpdateImpl(cross(cur), eventCoreImplPath)
	zkgm.UpdateImpl(cross(cur), eventZkgmImplPath)
	access.GrantRole(cross(cur), access.RelayerRole, eventAdminAddr)
}

func exerciseClientEventEmitters(cur realm) types.ClientId {
	core.RegisterClient(cross(cur), eventMockClientType, func(_, _ []byte) (lightclient.Interface, error) {
		return &eventMockLightClient{}, nil
	})
	core.CreateClient(cross(cur), core.NewMsgCreateClient(eventMockClientType, nil, nil))
	clientId := types.ClientId(1)

	core.UpdateClient(cross(cur), types.NewMsgUpdateClient(clientId, []byte("event-update")))
	core.ForceUpdateClient(cross(cur), types.NewMsgForceUpdateClient(clientId, []byte("event-force-client"), []byte("event-force-consensus")))

	return clientId
}

func exerciseMisbehaviourEmitter(cur realm, clientId types.ClientId) {
	core.Misbehaviour(cross(cur), types.NewMsgMisbehaviour(clientId, []byte("event-misbehaviour"), "g1relayer"))
}

func exerciseConnectionEventEmitters(cur realm, clientId types.ClientId) types.ConnectionId {
	core.ConnectionOpenInit(cross(cur), core.NewMsgConnectionOpenInit(clientId, types.ClientId(99)))
	core.ConnectionOpenTry(cross(cur), types.NewMsgConnectionOpenTry(clientId, types.ClientId(98), types.ConnectionId(88), nil, 1))

	openConnectionId := types.ConnectionId(1)
	core.ConnectionOpenAck(cross(cur), core.NewMsgConnectionOpenAck(openConnectionId, types.ConnectionId(77), nil, 1))
	core.ConnectionOpenConfirm(cross(cur), types.NewMsgConnectionOpenConfirm(types.ConnectionId(2), nil, 1))

	return openConnectionId
}

func exerciseChannelOpenEventEmitters(cur realm, connectionId types.ConnectionId) (types.ChannelId, types.ChannelId) {
	core.RegisterApp(cross(cur), &eventScenarioApp{})

	portId := []byte(cur.PkgPath())
	version := "event-v1"

	core.ChannelOpenInit(cross(cur), core.NewMsgChannelOpenInit(portId, portId, connectionId, version, "g1relayer"))

	tryChannel := core.NewChannel(
		types.ChannelStateTryOpen,
		connectionId,
		types.ChannelId(8),
		types.Bytes(portId),
		version,
	)
	core.ChannelOpenTry(cross(cur), core.NewMsgChannelOpenTry(portId, tryChannel, version, nil, 1, "g1relayer"))

	openChannelId := types.ChannelId(1)
	confirmChannelId := types.ChannelId(2)
	core.ChannelOpenAck(cross(cur), core.NewMsgChannelOpenAck(openChannelId, version, types.ChannelId(7), nil, 1, "g1relayer"))
	core.ChannelOpenConfirm(cross(cur), types.NewMsgChannelOpenConfirm(confirmChannelId, nil, 1, "g1relayer"))

	return openChannelId, confirmChannelId
}

func exerciseChannelCloseEventEmitters(cur realm, closeInitChannelId types.ChannelId, closeConfirmChannelId types.ChannelId) {
	core.ChannelCloseInit(cross(cur), types.NewMsgChannelCloseInit(closeInitChannelId, "g1relayer"))
	core.ChannelCloseConfirm(cross(cur), types.NewMsgChannelCloseConfirm(closeConfirmChannelId, nil, 1, "g1relayer"))
}

func exercisePacketEventEmitters(cur realm, clientId types.ClientId, channelId types.ChannelId) {
	packet1 := core.SendPacket(cross(cur), channelId, types.Timestamp(1), []byte("event-send-1"))
	packet2 := core.SendPacket(cross(cur), channelId, types.Timestamp(1), []byte("event-send-2"))
	core.BatchSend(cross(cur), types.NewMsgBatchSend([]types.Packet{packet1, packet2}))
	core.PacketAcknowledgement(cross(cur), core.NewMsgPacketAcknowledgement(
		[]types.Packet{packet1, packet2},
		[][]byte{[]byte("ack-send-1"), []byte("ack-send-2")},
		nil,
		1,
	))

	timeoutPacket := core.SendPacket(cross(cur), channelId, types.Timestamp(1), []byte("event-timeout"))
	core.PacketTimeout(cross(cur), types.NewMsgPacketTimeout(timeoutPacket, nil, 1))

	core.CommitMembershipProof(cross(cur), types.NewMsgCommitMembershipProof(clientId, 1, nil, []byte("event-membership-path"), []byte("event-membership-value")))
	core.CommitNonMembershipProof(cross(cur), types.NewMsgCommitNonMembershipProof(clientId, 1, nil, []byte("event-nonmembership-path")))

	recvPacket1 := core.NewPacket(types.ChannelId(90), channelId, []byte("event-recv-1"), types.Timestamp(1<<62))
	recvPacket2 := core.NewPacket(types.ChannelId(90), channelId, []byte("event-recv-2"), types.Timestamp(1<<62))
	recvAck1 := eventAck(recvPacket1)
	recvAck2 := eventAck(recvPacket2)
	core.PacketRecv(cross(cur), core.NewMsgPacketRecv(
		[]types.Packet{recvPacket1, recvPacket2},
		[][]byte{[]byte("relayer-msg-1"), []byte("relayer-msg-2")},
		nil,
		1,
	))
	core.BatchAcks(cross(cur), types.NewMsgBatchAcks([]types.Packet{recvPacket1, recvPacket2}, [][]byte{recvAck1, recvAck2}))

	intentPacket := core.NewPacket(types.ChannelId(91), channelId, []byte("event-intent"), types.Timestamp(1<<62))
	core.IntentPacketRecv(cross(cur), types.NewMsgIntentPacketRecv([]types.Packet{intentPacket}, [][]byte{[]byte("market-maker-msg")}))

	asyncPacket := core.NewPacket(types.ChannelId(92), channelId, []byte("event-async"), types.Timestamp(1<<62))
	core.PacketRecv(cross(cur), core.NewMsgPacketRecv([]types.Packet{asyncPacket}, [][]byte{[]byte("relayer-msg-async")}, nil, 1))
	core.WriteAcknowledgement(cross(cur), types.NewMsgWriteAcknowledgement(asyncPacket, []byte("late-ack")))
}

func exerciseZkgmRecvErrorEmitter(cur realm, connectionId types.ConnectionId) {
	zkgm.RegisterCoreApp(cross(cur))

	portId := []byte(zkgm.ProxyPkgPath())
	core.ChannelOpenInit(cross(cur), core.NewMsgChannelOpenInit(portId, portId, connectionId, zkgm.Version, "g1relayer"))
	channelId := types.ChannelId(3)
	core.ChannelOpenAck(cross(cur), core.NewMsgChannelOpenAck(channelId, zkgm.Version, types.ChannelId(22), nil, 1, "g1relayer"))

	malformedPacket := core.NewPacket(types.ChannelId(22), channelId, []byte{0x01}, types.Timestamp(1<<62))
	core.PacketRecv(cross(cur), core.NewMsgPacketRecv([]types.Packet{malformedPacket}, [][]byte{nil}, nil, 1))
}

type eventScenarioApp struct{}

func (*eventScenarioApp) OnChannelOpenInit(_ realm, _ types.ConnectionId, _ types.ChannelId, _ string, _ address) {
}

func (*eventScenarioApp) OnChannelOpenTry(_ realm, _ types.ConnectionId, _ types.ChannelId, _ string, _ string, _ address) {
}

func (*eventScenarioApp) OnChannelOpenAck(_ realm, _ types.ChannelId, _ types.ChannelId, _ string, _ address) {
}

func (*eventScenarioApp) OnChannelOpenConfirm(_ realm, _ types.ChannelId, _ address) {
}

func (*eventScenarioApp) OnChannelCloseInit(_ realm, _ types.ChannelId, _ address) {
}

func (*eventScenarioApp) OnChannelCloseConfirm(_ realm, _ types.ChannelId, _ address) {
}

func (*eventScenarioApp) OnRecvPacket(_ realm, packet types.Packet, _ address, _ []byte) types.RecvPacketResult {
	if string(packet.Data) == "event-async" {
		return core.NewRecvPacketResult(types.PacketStatusAsync, nil)
	}

	return core.NewRecvPacketResult(types.PacketStatusSuccess, eventAck(packet))
}

func (*eventScenarioApp) OnIntentRecvPacket(_ realm, packet types.Packet, _ address, _ []byte) types.RecvPacketResult {
	return core.NewRecvPacketResult(types.PacketStatusSuccess, eventAck(packet))
}

func (*eventScenarioApp) OnAcknowledgementPacket(_ realm, _ types.Packet, _ []byte, _ address) {
}

func (*eventScenarioApp) OnTimeoutPacket(_ realm, _ types.Packet, _ address) {
}

func eventAck(packet types.Packet) []byte {
	return []byte("ack:" + string(packet.Data))
}

type eventMockLightClient struct{}

func (m *eventMockLightClient) VerifyMembership(uint64, []byte, []byte, []byte) error { return nil }
func (m *eventMockLightClient) VerifyNonMembership(uint64, []byte, []byte) error      { return nil }
func (m *eventMockLightClient) GetTimestamp() types.Timestamp                         { return types.Timestamp(1) }

func (m *eventMockLightClient) GetTimestampAtHeight(uint64) (types.Timestamp, error) {
	return types.Timestamp(1), nil
}
func (m *eventMockLightClient) GetLatestHeight() uint64        { return 1 }
func (m *eventMockLightClient) GetCounterpartyChainID() string { return "mock-chain" }
func (m *eventMockLightClient) Status() lightclient.Status     { return lightclient.Active }

func (m *eventMockLightClient) VerifyHeader(_ address, header []byte, _ address) (types.StateUpdate, error) {
	return types.StateUpdate{Height: 1, ClientStateBytes: header, ConsensusStateBytes: header}, nil
}

func (m *eventMockLightClient) VerifyCreation(address, address) (types.ClientCreationResult, error) {
	return types.ClientCreationResult{}, nil
}

func (m *eventMockLightClient) Misbehaviour(address, []byte, address) ([]byte, error) {
	return []byte("event-frozen-client"), nil
}

// Output:
// [SCENARIO] proxy event emitters

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
//         "value": "scenario-event-mock-lc"
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
//         "value": "scenario-event-mock-lc"
//       },
//       {
//         "key": "counterparty_chain_id",
//         "value": "mock-chain"
//       }
//     ],
//     "pkg_path": "gno.land/r/onbloc/ibc/union/core"
//   },
//   {
//     "type": "UpdateClient",
//     "attrs": [
//       {
//         "key": "client_id",
//         "value": "1"
//       },
//       {
//         "key": "height",
//         "value": "1"
//       }
//     ],
//     "pkg_path": "gno.land/r/onbloc/ibc/union/core"
//   },
//   {
//     "type": "ForceUpdateClient",
//     "attrs": [
//       {
//         "key": "client_id",
//         "value": "1"
//       },
//       {
//         "key": "height",
//         "value": "1"
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
//     "type": "ConnectionOpenTry",
//     "attrs": [
//       {
//         "key": "connection_id",
//         "value": "2"
//       },
//       {
//         "key": "client_id",
//         "value": "1"
//       },
//       {
//         "key": "counterparty_client_id",
//         "value": "98"
//       },
//       {
//         "key": "counterparty_connection_id",
//         "value": "88"
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
//     "type": "ConnectionOpenConfirm",
//     "attrs": [
//       {
//         "key": "connection_id",
//         "value": "2"
//       },
//       {
//         "key": "client_id",
//         "value": "1"
//       },
//       {
//         "key": "counterparty_client_id",
//         "value": "98"
//       },
//       {
//         "key": "counterparty_connection_id",
//         "value": "88"
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
//         "value": "event-v1"
//       }
//     ],
//     "pkg_path": "gno.land/r/onbloc/ibc/union/core"
//   },
//   {
//     "type": "ChannelOpenTry",
//     "attrs": [
//       {
//         "key": "port_id",
//         "value": ""
//       },
//       {
//         "key": "channel_id",
//         "value": "2"
//       },
//       {
//         "key": "counterparty_port_id",
//         "value": "0x"
//       },
//       {
//         "key": "counterparty_channel_id",
//         "value": "8"
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
//         "value": "event-v1"
//       },
//       {
//         "key": "counterparty_version",
//         "value": "event-v1"
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
//         "value": "event-v1"
//       }
//     ],
//     "pkg_path": "gno.land/r/onbloc/ibc/union/core"
//   },
//   {
//     "type": "ChannelOpenConfirm",
//     "attrs": [
//       {
//         "key": "port_id",
//         "value": ""
//       },
//       {
//         "key": "channel_id",
//         "value": "2"
//       },
//       {
//         "key": "counterparty_port_id",
//         "value": "0x"
//       },
//       {
//         "key": "counterparty_channel_id",
//         "value": "8"
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
//         "value": "event-v1"
//       }
//     ],
//     "pkg_path": "gno.land/r/onbloc/ibc/union/core"
//   },
//   {
//     "type": "PacketSend",
//     "attrs": [
//       {
//         "key": "packet_hash",
//         "value": "0xa4f450f6aa596f24eb8ba0111a29220f0067ca4c0ca7da1ac49b3e7bea451281"
//       },
//       {
//         "key": "packet_data",
//         "value": "0x6576656e742d73656e642d31"
//       },
//       {
//         "key": "source_channel_id",
//         "value": "1"
//       },
//       {
//         "key": "source_channel_version",
//         "value": "event-v1"
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
//       }
//     ],
//     "pkg_path": "gno.land/r/onbloc/ibc/union/core"
//   },
//   {
//     "type": "PacketSend",
//     "attrs": [
//       {
//         "key": "packet_hash",
//         "value": "0x83a818960d38afa4b1392d9f08fcc6711a99ec1a63279d8f6378c10b31885643"
//       },
//       {
//         "key": "packet_data",
//         "value": "0x6576656e742d73656e642d32"
//       },
//       {
//         "key": "source_channel_id",
//         "value": "1"
//       },
//       {
//         "key": "source_channel_version",
//         "value": "event-v1"
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
//       }
//     ],
//     "pkg_path": "gno.land/r/onbloc/ibc/union/core"
//   },
//   {
//     "type": "BatchSend",
//     "attrs": [
//       {
//         "key": "channel_id",
//         "value": "1"
//       },
//       {
//         "key": "packet_hash",
//         "value": "0xa4f450f6aa596f24eb8ba0111a29220f0067ca4c0ca7da1ac49b3e7bea451281"
//       },
//       {
//         "key": "batch_hash",
//         "value": "0xc56ff839a5b77ab1bb140ebc1ef9780daefa9c20abf07672a5a76527977e6f92"
//       }
//     ],
//     "pkg_path": "gno.land/r/onbloc/ibc/union/core"
//   },
//   {
//     "type": "BatchSend",
//     "attrs": [
//       {
//         "key": "channel_id",
//         "value": "1"
//       },
//       {
//         "key": "packet_hash",
//         "value": "0x83a818960d38afa4b1392d9f08fcc6711a99ec1a63279d8f6378c10b31885643"
//       },
//       {
//         "key": "batch_hash",
//         "value": "0xc56ff839a5b77ab1bb140ebc1ef9780daefa9c20abf07672a5a76527977e6f92"
//       }
//     ],
//     "pkg_path": "gno.land/r/onbloc/ibc/union/core"
//   },
//   {
//     "type": "PacketAck",
//     "attrs": [
//       {
//         "key": "packet_hash",
//         "value": "0xa4f450f6aa596f24eb8ba0111a29220f0067ca4c0ca7da1ac49b3e7bea451281"
//       },
//       {
//         "key": "packet_data",
//         "value": "0x6576656e742d73656e642d31"
//       },
//       {
//         "key": "source_channel_id",
//         "value": "1"
//       },
//       {
//         "key": "source_channel_version",
//         "value": "event-v1"
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
//         "key": "acknowledgement",
//         "value": "0x61636b2d73656e642d31"
//       }
//     ],
//     "pkg_path": "gno.land/r/onbloc/ibc/union/core"
//   },
//   {
//     "type": "PacketAck",
//     "attrs": [
//       {
//         "key": "packet_hash",
//         "value": "0x83a818960d38afa4b1392d9f08fcc6711a99ec1a63279d8f6378c10b31885643"
//       },
//       {
//         "key": "packet_data",
//         "value": "0x6576656e742d73656e642d32"
//       },
//       {
//         "key": "source_channel_id",
//         "value": "1"
//       },
//       {
//         "key": "source_channel_version",
//         "value": "event-v1"
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
//         "key": "acknowledgement",
//         "value": "0x61636b2d73656e642d32"
//       }
//     ],
//     "pkg_path": "gno.land/r/onbloc/ibc/union/core"
//   },
//   {
//     "type": "PacketSend",
//     "attrs": [
//       {
//         "key": "packet_hash",
//         "value": "0x52124a68f538d0aa1ece014bcb45fab024e3af6a8e277cfa56adaad68be2c357"
//       },
//       {
//         "key": "packet_data",
//         "value": "0x6576656e742d74696d656f7574"
//       },
//       {
//         "key": "source_channel_id",
//         "value": "1"
//       },
//       {
//         "key": "source_channel_version",
//         "value": "event-v1"
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
//       }
//     ],
//     "pkg_path": "gno.land/r/onbloc/ibc/union/core"
//   },
//   {
//     "type": "PacketTimeout",
//     "attrs": [
//       {
//         "key": "packet_hash",
//         "value": "0x52124a68f538d0aa1ece014bcb45fab024e3af6a8e277cfa56adaad68be2c357"
//       },
//       {
//         "key": "packet_data",
//         "value": "0x6576656e742d74696d656f7574"
//       },
//       {
//         "key": "source_channel_id",
//         "value": "1"
//       },
//       {
//         "key": "source_channel_version",
//         "value": "event-v1"
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
//       }
//     ],
//     "pkg_path": "gno.land/r/onbloc/ibc/union/core"
//   },
//   {
//     "type": "CommitMembershipProof",
//     "attrs": [
//       {
//         "key": "client_id",
//         "value": "1"
//       },
//       {
//         "key": "proof_height",
//         "value": "1"
//       },
//       {
//         "key": "path",
//         "value": "0x6576656e742d6d656d626572736869702d70617468"
//       },
//       {
//         "key": "value",
//         "value": "0x6576656e742d6d656d626572736869702d76616c7565"
//       }
//     ],
//     "pkg_path": "gno.land/r/onbloc/ibc/union/core"
//   },
//   {
//     "type": "CommitNonMembershipProof",
//     "attrs": [
//       {
//         "key": "client_id",
//         "value": "1"
//       },
//       {
//         "key": "proof_height",
//         "value": "1"
//       },
//       {
//         "key": "path",
//         "value": "0x6576656e742d6e6f6e6d656d626572736869702d70617468"
//       }
//     ],
//     "pkg_path": "gno.land/r/onbloc/ibc/union/core"
//   },
//   {
//     "type": "WriteAck",
//     "attrs": [
//       {
//         "key": "packet_hash",
//         "value": "0x2e925a980b459b69e205479571e2988b99ffb77d7eae552bbe4107b5e2857599"
//       },
//       {
//         "key": "packet_data",
//         "value": "0x6576656e742d726563762d31"
//       },
//       {
//         "key": "source_channel_id",
//         "value": "90"
//       },
//       {
//         "key": "source_connection_id",
//         "value": "77"
//       },
//       {
//         "key": "source_connection_client_id",
//         "value": "99"
//       },
//       {
//         "key": "destination_channel_id",
//         "value": "1"
//       },
//       {
//         "key": "destination_channel_version",
//         "value": "event-v1"
//       },
//       {
//         "key": "destination_connection_id",
//         "value": "1"
//       },
//       {
//         "key": "destination_connection_client_id",
//         "value": "1"
//       },
//       {
//         "key": "timeout_timestamp",
//         "value": "4611686018427387904"
//       },
//       {
//         "key": "acknowledgement",
//         "value": "0x61636b3a6576656e742d726563762d31"
//       }
//     ],
//     "pkg_path": "gno.land/r/onbloc/ibc/union/core"
//   },
//   {
//     "type": "PacketRecv",
//     "attrs": [
//       {
//         "key": "packet_hash",
//         "value": "0x2e925a980b459b69e205479571e2988b99ffb77d7eae552bbe4107b5e2857599"
//       },
//       {
//         "key": "packet_data",
//         "value": "0x6576656e742d726563762d31"
//       },
//       {
//         "key": "source_channel_id",
//         "value": "90"
//       },
//       {
//         "key": "source_connection_id",
//         "value": "77"
//       },
//       {
//         "key": "source_connection_client_id",
//         "value": "99"
//       },
//       {
//         "key": "destination_channel_id",
//         "value": "1"
//       },
//       {
//         "key": "destination_channel_version",
//         "value": "event-v1"
//       },
//       {
//         "key": "destination_connection_id",
//         "value": "1"
//       },
//       {
//         "key": "destination_connection_client_id",
//         "value": "1"
//       },
//       {
//         "key": "timeout_timestamp",
//         "value": "4611686018427387904"
//       },
//       {
//         "key": "maker_msg",
//         "value": "0x72656c617965722d6d73672d31"
//       }
//     ],
//     "pkg_path": "gno.land/r/onbloc/ibc/union/core"
//   },
//   {
//     "type": "WriteAck",
//     "attrs": [
//       {
//         "key": "packet_hash",
//         "value": "0x72e4fcb14058a989cb243a46e9583fe569909b915ffe4edf5f1ca9609db20083"
//       },
//       {
//         "key": "packet_data",
//         "value": "0x6576656e742d726563762d32"
//       },
//       {
//         "key": "source_channel_id",
//         "value": "90"
//       },
//       {
//         "key": "source_connection_id",
//         "value": "77"
//       },
//       {
//         "key": "source_connection_client_id",
//         "value": "99"
//       },
//       {
//         "key": "destination_channel_id",
//         "value": "1"
//       },
//       {
//         "key": "destination_channel_version",
//         "value": "event-v1"
//       },
//       {
//         "key": "destination_connection_id",
//         "value": "1"
//       },
//       {
//         "key": "destination_connection_client_id",
//         "value": "1"
//       },
//       {
//         "key": "timeout_timestamp",
//         "value": "4611686018427387904"
//       },
//       {
//         "key": "acknowledgement",
//         "value": "0x61636b3a6576656e742d726563762d32"
//       }
//     ],
//     "pkg_path": "gno.land/r/onbloc/ibc/union/core"
//   },
//   {
//     "type": "PacketRecv",
//     "attrs": [
//       {
//         "key": "packet_hash",
//         "value": "0x72e4fcb14058a989cb243a46e9583fe569909b915ffe4edf5f1ca9609db20083"
//       },
//       {
//         "key": "packet_data",
//         "value": "0x6576656e742d726563762d32"
//       },
//       {
//         "key": "source_channel_id",
//         "value": "90"
//       },
//       {
//         "key": "source_connection_id",
//         "value": "77"
//       },
//       {
//         "key": "source_connection_client_id",
//         "value": "99"
//       },
//       {
//         "key": "destination_channel_id",
//         "value": "1"
//       },
//       {
//         "key": "destination_channel_version",
//         "value": "event-v1"
//       },
//       {
//         "key": "destination_connection_id",
//         "value": "1"
//       },
//       {
//         "key": "destination_connection_client_id",
//         "value": "1"
//       },
//       {
//         "key": "timeout_timestamp",
//         "value": "4611686018427387904"
//       },
//       {
//         "key": "maker_msg",
//         "value": "0x72656c617965722d6d73672d32"
//       }
//     ],
//     "pkg_path": "gno.land/r/onbloc/ibc/union/core"
//   },
//   {
//     "type": "BatchAcks",
//     "attrs": [
//       {
//         "key": "channel_id",
//         "value": "1"
//       },
//       {
//         "key": "packet_hash",
//         "value": "0x2e925a980b459b69e205479571e2988b99ffb77d7eae552bbe4107b5e2857599"
//       },
//       {
//         "key": "batch_hash",
//         "value": "0xeaa48d794635818b774f29cef37d0fddde0c6edbd4fd480dc357359f495eae71"
//       }
//     ],
//     "pkg_path": "gno.land/r/onbloc/ibc/union/core"
//   },
//   {
//     "type": "BatchAcks",
//     "attrs": [
//       {
//         "key": "channel_id",
//         "value": "1"
//       },
//       {
//         "key": "packet_hash",
//         "value": "0x72e4fcb14058a989cb243a46e9583fe569909b915ffe4edf5f1ca9609db20083"
//       },
//       {
//         "key": "batch_hash",
//         "value": "0xeaa48d794635818b774f29cef37d0fddde0c6edbd4fd480dc357359f495eae71"
//       }
//     ],
//     "pkg_path": "gno.land/r/onbloc/ibc/union/core"
//   },
//   {
//     "type": "WriteAck",
//     "attrs": [
//       {
//         "key": "packet_hash",
//         "value": "0x5903360eb9bb521e532b827510363708a8e0c10cf58ce5cd331399623ad5c27b"
//       },
//       {
//         "key": "packet_data",
//         "value": "0x6576656e742d696e74656e74"
//       },
//       {
//         "key": "source_channel_id",
//         "value": "91"
//       },
//       {
//         "key": "source_connection_id",
//         "value": "77"
//       },
//       {
//         "key": "source_connection_client_id",
//         "value": "99"
//       },
//       {
//         "key": "destination_channel_id",
//         "value": "1"
//       },
//       {
//         "key": "destination_channel_version",
//         "value": "event-v1"
//       },
//       {
//         "key": "destination_connection_id",
//         "value": "1"
//       },
//       {
//         "key": "destination_connection_client_id",
//         "value": "1"
//       },
//       {
//         "key": "timeout_timestamp",
//         "value": "4611686018427387904"
//       },
//       {
//         "key": "acknowledgement",
//         "value": "0x61636b3a6576656e742d696e74656e74"
//       }
//     ],
//     "pkg_path": "gno.land/r/onbloc/ibc/union/core"
//   },
//   {
//     "type": "IntentPacketRecv",
//     "attrs": [
//       {
//         "key": "packet_hash",
//         "value": "0x5903360eb9bb521e532b827510363708a8e0c10cf58ce5cd331399623ad5c27b"
//       },
//       {
//         "key": "packet_data",
//         "value": "0x6576656e742d696e74656e74"
//       },
//       {
//         "key": "source_channel_id",
//         "value": "91"
//       },
//       {
//         "key": "source_connection_id",
//         "value": "77"
//       },
//       {
//         "key": "source_connection_client_id",
//         "value": "99"
//       },
//       {
//         "key": "destination_channel_id",
//         "value": "1"
//       },
//       {
//         "key": "destination_channel_version",
//         "value": "event-v1"
//       },
//       {
//         "key": "destination_connection_id",
//         "value": "1"
//       },
//       {
//         "key": "destination_connection_client_id",
//         "value": "1"
//       },
//       {
//         "key": "timeout_timestamp",
//         "value": "4611686018427387904"
//       },
//       {
//         "key": "market_maker_msg",
//         "value": "0x6d61726b65742d6d616b65722d6d7367"
//       }
//     ],
//     "pkg_path": "gno.land/r/onbloc/ibc/union/core"
//   },
//   {
//     "type": "PacketRecv",
//     "attrs": [
//       {
//         "key": "packet_hash",
//         "value": "0xa95670a052ae50cb85b4baf83596b9f36ebb5b2026165fbe737db02d8b6462e9"
//       },
//       {
//         "key": "packet_data",
//         "value": "0x6576656e742d6173796e63"
//       },
//       {
//         "key": "source_channel_id",
//         "value": "92"
//       },
//       {
//         "key": "source_connection_id",
//         "value": "77"
//       },
//       {
//         "key": "source_connection_client_id",
//         "value": "99"
//       },
//       {
//         "key": "destination_channel_id",
//         "value": "1"
//       },
//       {
//         "key": "destination_channel_version",
//         "value": "event-v1"
//       },
//       {
//         "key": "destination_connection_id",
//         "value": "1"
//       },
//       {
//         "key": "destination_connection_client_id",
//         "value": "1"
//       },
//       {
//         "key": "timeout_timestamp",
//         "value": "4611686018427387904"
//       },
//       {
//         "key": "maker_msg",
//         "value": "0x72656c617965722d6d73672d6173796e63"
//       }
//     ],
//     "pkg_path": "gno.land/r/onbloc/ibc/union/core"
//   },
//   {
//     "type": "WriteAck",
//     "attrs": [
//       {
//         "key": "packet_hash",
//         "value": "0xa95670a052ae50cb85b4baf83596b9f36ebb5b2026165fbe737db02d8b6462e9"
//       },
//       {
//         "key": "packet_data",
//         "value": "0x6576656e742d6173796e63"
//       },
//       {
//         "key": "source_channel_id",
//         "value": "92"
//       },
//       {
//         "key": "source_connection_id",
//         "value": "77"
//       },
//       {
//         "key": "source_connection_client_id",
//         "value": "99"
//       },
//       {
//         "key": "destination_channel_id",
//         "value": "1"
//       },
//       {
//         "key": "destination_channel_version",
//         "value": "event-v1"
//       },
//       {
//         "key": "destination_connection_id",
//         "value": "1"
//       },
//       {
//         "key": "destination_connection_client_id",
//         "value": "1"
//       },
//       {
//         "key": "timeout_timestamp",
//         "value": "4611686018427387904"
//       },
//       {
//         "key": "acknowledgement",
//         "value": "0x6c6174652d61636b"
//       }
//     ],
//     "pkg_path": "gno.land/r/onbloc/ibc/union/core"
//   },
//   {
//     "type": "ChannelCloseInit",
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
//         "value": "event-v1"
//       }
//     ],
//     "pkg_path": "gno.land/r/onbloc/ibc/union/core"
//   },
//   {
//     "type": "ChannelCloseConfirm",
//     "attrs": [
//       {
//         "key": "port_id",
//         "value": ""
//       },
//       {
//         "key": "channel_id",
//         "value": "2"
//       },
//       {
//         "key": "counterparty_port_id",
//         "value": "0x"
//       },
//       {
//         "key": "counterparty_channel_id",
//         "value": "8"
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
//         "value": "event-v1"
//       }
//     ],
//     "pkg_path": "gno.land/r/onbloc/ibc/union/core"
//   },
//   {
//     "type": "AppRegistered",
//     "attrs": [
//       {
//         "key": "port_id",
//         "value": "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm"
//       },
//       {
//         "key": "registrar_pkg_path",
//         "value": "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm"
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
//         "value": "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm"
//       },
//       {
//         "key": "channel_id",
//         "value": "3"
//       },
//       {
//         "key": "counterparty_port_id",
//         "value": "0x676e6f2e6c616e642f722f6f6e626c6f632f6962632f756e696f6e2f617070732f75637330335f7a6b676d"
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
//         "value": "ucs03-zkgm-0"
//       }
//     ],
//     "pkg_path": "gno.land/r/onbloc/ibc/union/core"
//   },
//   {
//     "type": "ChannelOpenAck",
//     "attrs": [
//       {
//         "key": "port_id",
//         "value": "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm"
//       },
//       {
//         "key": "channel_id",
//         "value": "3"
//       },
//       {
//         "key": "counterparty_port_id",
//         "value": "0x676e6f2e6c616e642f722f6f6e626c6f632f6962632f756e696f6e2f617070732f75637330335f7a6b676d"
//       },
//       {
//         "key": "counterparty_channel_id",
//         "value": "22"
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
//         "value": "ucs03-zkgm-0"
//       }
//     ],
//     "pkg_path": "gno.land/r/onbloc/ibc/union/core"
//   },
//   {
//     "type": "ZkgmRecvError",
//     "attrs": [
//       {
//         "key": "source_channel",
//         "value": "22"
//       },
//       {
//         "key": "destination_channel",
//         "value": "3"
//       },
//       {
//         "key": "reason",
//         "value": "abi: invalid data"
//       }
//     ],
//     "pkg_path": "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm"
//   },
//   {
//     "type": "WriteAck",
//     "attrs": [
//       {
//         "key": "packet_hash",
//         "value": "0x7bf8b2199e74916681e58171af1e1491c0d3197ab60389fbf8b937906693f75e"
//       },
//       {
//         "key": "packet_data",
//         "value": "0x01"
//       },
//       {
//         "key": "source_channel_id",
//         "value": "22"
//       },
//       {
//         "key": "source_connection_id",
//         "value": "77"
//       },
//       {
//         "key": "source_connection_client_id",
//         "value": "99"
//       },
//       {
//         "key": "destination_channel_id",
//         "value": "3"
//       },
//       {
//         "key": "destination_channel_version",
//         "value": "ucs03-zkgm-0"
//       },
//       {
//         "key": "destination_connection_id",
//         "value": "1"
//       },
//       {
//         "key": "destination_connection_client_id",
//         "value": "1"
//       },
//       {
//         "key": "timeout_timestamp",
//         "value": "4611686018427387904"
//       },
//       {
//         "key": "acknowledgement",
//         "value": "0x000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000400000000000000000000000000000000000000000000000000000000000000000"
//       }
//     ],
//     "pkg_path": "gno.land/r/onbloc/ibc/union/core"
//   },
//   {
//     "type": "PacketRecv",
//     "attrs": [
//       {
//         "key": "packet_hash",
//         "value": "0x7bf8b2199e74916681e58171af1e1491c0d3197ab60389fbf8b937906693f75e"
//       },
//       {
//         "key": "packet_data",
//         "value": "0x01"
//       },
//       {
//         "key": "source_channel_id",
//         "value": "22"
//       },
//       {
//         "key": "source_connection_id",
//         "value": "77"
//       },
//       {
//         "key": "source_connection_client_id",
//         "value": "99"
//       },
//       {
//         "key": "destination_channel_id",
//         "value": "3"
//       },
//       {
//         "key": "destination_channel_version",
//         "value": "ucs03-zkgm-0"
//       },
//       {
//         "key": "destination_connection_id",
//         "value": "1"
//       },
//       {
//         "key": "destination_connection_client_id",
//         "value": "1"
//       },
//       {
//         "key": "timeout_timestamp",
//         "value": "4611686018427387904"
//       },
//       {
//         "key": "maker_msg",
//         "value": "0x"
//       }
//     ],
//     "pkg_path": "gno.land/r/onbloc/ibc/union/core"
//   },
//   {
//     "type": "Misbehaviour",
//     "attrs": [
//       {
//         "key": "client_id",
//         "value": "1"
//       }
//     ],
//     "pkg_path": "gno.land/r/onbloc/ibc/union/core"
//   }
// ]
