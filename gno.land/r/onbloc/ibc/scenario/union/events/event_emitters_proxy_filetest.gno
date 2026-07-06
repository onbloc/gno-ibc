// PKGPATH: gno.land/r/onbloc/ibc/scenario/union/events
package events

import (
	"testing"

	u256 "gno.land/p/gnoswap/uint256"
	"gno.land/p/nt/ufmt/v0"
	"gno.land/p/onbloc/ibc/union/lightclient"
	"gno.land/p/onbloc/ibc/union/types"
	z "gno.land/p/onbloc/ibc/union/zkgm"

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
	packet1 := core.SendPacket(cross(cur), channelId, types.Timestamp(1), eventPacketData(z.Instruction{
		Version: z.INSTR_VERSION_0,
		Opcode:  z.OP_CALL,
		Operand: []byte("event-call"),
	}))
	packet2 := core.SendPacket(cross(cur), channelId, types.Timestamp(1), eventPacketData(eventTokenOrderInstruction(z.TokenOrderV2{
		Sender:      []byte(eventAdminAddr.String()),
		Receiver:    []byte("0x5fbe74a283f7954f10aa04c2edf55578811aeb03"),
		BaseToken:   []byte("ugnot"),
		BaseAmount:  u256.NewUint(1000000),
		QuoteToken:  []byte("0xD3fCBD2aD2DB9F204f60077F874C6159D77000Df"),
		QuoteAmount: u256.NewUint(1000000),
		Kind:        z.TOKEN_ORDER_KIND_ESCROW,
		Metadata:    []byte("event-solver-metadata"),
	})))
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

func eventTokenOrderInstruction(order z.TokenOrderV2) z.Instruction {
	operand, err := z.EncodeTokenOrderV2(order)
	if err != nil {
		panic(err)
	}
	return z.Instruction{Version: z.INSTR_VERSION_2, Opcode: z.OP_TOKEN_ORDER, Operand: operand}
}

func eventPacketData(instr z.Instruction) []byte {
	data, err := z.EncodeZkgmPacket(z.ZkgmPacket{Path: u256.Zero(), Instruction: instr})
	if err != nil {
		panic(err)
	}
	return data
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
//         "value": "0x78d9f4b7158b264f6ef8f55e9813d031144ff42f65919227c79fb20e1fc2ed70"
//       },
//       {
//         "key": "packet_data",
//         "value": "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAABgAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAABgAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAApldmVudC1jYWxsAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=="
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
//         "value": "0x7a8d7e00a6f9fd5ecd531cfe519b412f070d564624509bf620df6845b1cce967"
//       },
//       {
//         "key": "packet_data",
//         "value": "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAABgAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAIAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAwAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAABgAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAqAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAABAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAFgAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAcAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA9CQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAIAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAPQkAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAJgAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAChnMWpnOG10dXR1OWtoaGZ3YzRueG11aGNwZnRmMHBhamRoZnZzcWY1AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAACoweDVmYmU3NGEyODNmNzk1NGYxMGFhMDRjMmVkZjU1NTc4ODExYWViMDMAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAV1Z25vdAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAqMHhEM2ZDQkQyYUQyREI5RjIwNGY2MDA3N0Y4NzRDNjE1OUQ3NzAwMERmAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAVZXZlbnQtc29sdmVyLW1ldGFkYXRhAAAAAAAAAAAAAAA="
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
//         "value": "0x78d9f4b7158b264f6ef8f55e9813d031144ff42f65919227c79fb20e1fc2ed70"
//       },
//       {
//         "key": "batch_hash",
//         "value": "0x753da5ad680ba08e41e1815b915b37ebc86a879676498df83c9c96931239fd1b"
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
//         "value": "0x7a8d7e00a6f9fd5ecd531cfe519b412f070d564624509bf620df6845b1cce967"
//       },
//       {
//         "key": "batch_hash",
//         "value": "0x753da5ad680ba08e41e1815b915b37ebc86a879676498df83c9c96931239fd1b"
//       }
//     ],
//     "pkg_path": "gno.land/r/onbloc/ibc/union/core"
//   },
//   {
//     "type": "PacketAck",
//     "attrs": [
//       {
//         "key": "packet_hash",
//         "value": "0x78d9f4b7158b264f6ef8f55e9813d031144ff42f65919227c79fb20e1fc2ed70"
//       },
//       {
//         "key": "packet_data",
//         "value": "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAABgAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAABgAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAApldmVudC1jYWxsAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=="
//       },
//       {
//         "key": "source_channel_id",
//         "value": "1"
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
//         "key": "destination_channel_version",
//         "value": "event-v1"
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
//         "value": "YWNrLXNlbmQtMQ=="
//       },
//       {
//         "key": "maker",
//         "value": "g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5"
//       }
//     ],
//     "pkg_path": "gno.land/r/onbloc/ibc/union/core"
//   },
//   {
//     "type": "PacketAck",
//     "attrs": [
//       {
//         "key": "packet_hash",
//         "value": "0x7a8d7e00a6f9fd5ecd531cfe519b412f070d564624509bf620df6845b1cce967"
//       },
//       {
//         "key": "packet_data",
//         "value": "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAABgAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAIAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAwAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAABgAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAqAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAABAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAFgAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAcAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA9CQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAIAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAPQkAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAJgAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAChnMWpnOG10dXR1OWtoaGZ3YzRueG11aGNwZnRmMHBhamRoZnZzcWY1AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAACoweDVmYmU3NGEyODNmNzk1NGYxMGFhMDRjMmVkZjU1NTc4ODExYWViMDMAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAV1Z25vdAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAqMHhEM2ZDQkQyYUQyREI5RjIwNGY2MDA3N0Y4NzRDNjE1OUQ3NzAwMERmAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAVZXZlbnQtc29sdmVyLW1ldGFkYXRhAAAAAAAAAAAAAAA="
//       },
//       {
//         "key": "source_channel_id",
//         "value": "1"
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
//         "key": "destination_channel_version",
//         "value": "event-v1"
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
//         "value": "YWNrLXNlbmQtMg=="
//       },
//       {
//         "key": "maker",
//         "value": "g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5"
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
//         "value": "ZXZlbnQtdGltZW91dA=="
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
//         "value": "ZXZlbnQtdGltZW91dA=="
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
//         "value": "ZXZlbnQtbWVtYmVyc2hpcC1wYXRo"
//       },
//       {
//         "key": "value",
//         "value": "ZXZlbnQtbWVtYmVyc2hpcC12YWx1ZQ=="
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
//         "value": "ZXZlbnQtbm9ubWVtYmVyc2hpcC1wYXRo"
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
//         "value": "ZXZlbnQtcmVjdi0x"
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
//         "value": "YWNrOmV2ZW50LXJlY3YtMQ=="
//       }
//     ],
//     "pkg_path": "gno.land/r/onbloc/ibc/union/core"
//   },
//   {
//     "type": "PacketRecv",
//     "attrs": [
//       {
//         "key": "destination_channel_id",
//         "value": "1"
//       },
//       {
//         "key": "packet_hash",
//         "value": "0x2e925a980b459b69e205479571e2988b99ffb77d7eae552bbe4107b5e2857599"
//       },
//       {
//         "key": "maker",
//         "value": "g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5"
//       },
//       {
//         "key": "maker_msg",
//         "value": "cmVsYXllci1tc2ctMQ=="
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
//         "value": "ZXZlbnQtcmVjdi0y"
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
//         "value": "YWNrOmV2ZW50LXJlY3YtMg=="
//       }
//     ],
//     "pkg_path": "gno.land/r/onbloc/ibc/union/core"
//   },
//   {
//     "type": "PacketRecv",
//     "attrs": [
//       {
//         "key": "destination_channel_id",
//         "value": "1"
//       },
//       {
//         "key": "packet_hash",
//         "value": "0x72e4fcb14058a989cb243a46e9583fe569909b915ffe4edf5f1ca9609db20083"
//       },
//       {
//         "key": "maker",
//         "value": "g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5"
//       },
//       {
//         "key": "maker_msg",
//         "value": "cmVsYXllci1tc2ctMg=="
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
//         "value": "ZXZlbnQtaW50ZW50"
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
//         "value": "YWNrOmV2ZW50LWludGVudA=="
//       }
//     ],
//     "pkg_path": "gno.land/r/onbloc/ibc/union/core"
//   },
//   {
//     "type": "IntentPacketRecv",
//     "attrs": [
//       {
//         "key": "destination_channel_id",
//         "value": "1"
//       },
//       {
//         "key": "packet_hash",
//         "value": "0x5903360eb9bb521e532b827510363708a8e0c10cf58ce5cd331399623ad5c27b"
//       },
//       {
//         "key": "maker",
//         "value": "g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5"
//       },
//       {
//         "key": "maker_msg",
//         "value": "bWFya2V0LW1ha2VyLW1zZw=="
//       }
//     ],
//     "pkg_path": "gno.land/r/onbloc/ibc/union/core"
//   },
//   {
//     "type": "PacketRecv",
//     "attrs": [
//       {
//         "key": "destination_channel_id",
//         "value": "1"
//       },
//       {
//         "key": "packet_hash",
//         "value": "0xa95670a052ae50cb85b4baf83596b9f36ebb5b2026165fbe737db02d8b6462e9"
//       },
//       {
//         "key": "maker",
//         "value": "g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5"
//       },
//       {
//         "key": "maker_msg",
//         "value": "cmVsYXllci1tc2ctYXN5bmM="
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
//         "value": "ZXZlbnQtYXN5bmM="
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
//         "value": "bGF0ZS1hY2s="
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
//         "value": "AQ=="
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
//         "value": "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
//       }
//     ],
//     "pkg_path": "gno.land/r/onbloc/ibc/union/core"
//   },
//   {
//     "type": "PacketRecv",
//     "attrs": [
//       {
//         "key": "destination_channel_id",
//         "value": "3"
//       },
//       {
//         "key": "packet_hash",
//         "value": "0x7bf8b2199e74916681e58171af1e1491c0d3197ab60389fbf8b937906693f75e"
//       },
//       {
//         "key": "maker",
//         "value": "g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5"
//       },
//       {
//         "key": "maker_msg",
//         "value": ""
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
