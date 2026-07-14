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
	eventConfigCoreImplPath = "gno.land/r/onbloc/ibc/union/core/v1"

	eventConfigAdminAddr      = address("g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5")
	eventConfigMockClientType = types.ClientType("scenario-event-config-lc")
)

func main(cur realm) {
	ufmt.Println("[SCENARIO] event config drives packet send events")

	setupEventConfigScenario(cur)
	channelId := openEventConfigChannel(cur)
	sendWithSplitEnabled(cur, channelId)
	disableEventConfigSplit(cur)
	sendWithSplitDisabled(cur, channelId)
}

func setupEventConfigScenario(cur realm) {
	ufmt.Println("[STEP] bootstrap core proxy")

	testing.SetRealm(testing.NewUserRealm(eventConfigAdminAddr))
	core.UpdateImpl(cross(cur), eventConfigCoreImplPath)
	access.GrantRole(cross(cur), access.RelayerRole, eventConfigAdminAddr)
}

func openEventConfigChannel(cur realm) types.ChannelId {
	ufmt.Println("[STEP] open event config channel")

	testing.SetRealm(testing.NewUserRealm(eventConfigAdminAddr))
	core.RegisterClient(cross(cur), eventConfigMockClientType, func(_, _ []byte) (lightclient.Interface, error) {
		return &eventConfigMockLightClient{}, nil
	})
	core.CreateClient(cross(cur), core.NewMsgCreateClient(eventConfigMockClientType, nil, nil))
	clientId := types.ClientId(1)

	core.ConnectionOpenInit(cross(cur), core.NewMsgConnectionOpenInit(clientId, types.ClientId(99)))
	connectionId := types.ConnectionId(1)
	core.ConnectionOpenAck(cross(cur), core.NewMsgConnectionOpenAck(connectionId, types.ConnectionId(77), nil, 1))

	core.RegisterApp(cross(cur), &eventConfigScenarioApp{})
	portId := []byte(cur.PkgPath())
	core.ChannelOpenInit(cross(cur), core.NewMsgChannelOpenInit(portId, portId, connectionId, "event-config-v1", "g1relayer"))
	channelId := types.ChannelId(1)
	core.ChannelOpenAck(cross(cur), core.NewMsgChannelOpenAck(channelId, "event-config-v1", types.ChannelId(7), nil, 1, "g1relayer"))

	ufmt.Printf("[INFO] channel_id: %s\n", channelId.String())
	return channelId
}

func sendWithSplitEnabled(cur realm, channelId types.ChannelId) {
	ufmt.Println("[STEP] before config change: split packet_data attrs")

	testing.SetRealm(testing.NewUserRealm(eventConfigAdminAddr))
	core.SetSplitEventAttrs(cross(cur), true)
	core.SetMaxEventAttrValueLen(cross(cur), 4)
	core.SetMaxPacketDataEventColumns(cross(cur), 2)
	config := core.GetEventConfig()
	ufmt.Printf("[INFO] split_event_attrs: %t\n", config.SplitEventAttrs)
	ufmt.Printf("[INFO] max_event_attr_value_len: %d\n", config.MaxEventAttrValueLen)
	ufmt.Printf("[INFO] max_packet_data_event_columns: %d\n", config.MaxPacketDataEventColumns)
	ufmt.Printf("[INFO] packet_data_budget: %d\n", core.MaxPacketDataEventSize())
	ufmt.Printf("[INFO] oversized_packet_rejected: %t\n", !core.IsValidPacketDataSize(make([]byte, 16)))

	packet := core.SendPacket(cross(cur), channelId, types.Timestamp(1), []byte{0xaa, 0xbb, 0xcc})
	ufmt.Printf("[INFO] before_packet_data_size: %d\n", eventConfigHexAttrLen(packet.Data))
	ufmt.Println("[EXPECTED] before PacketSend uses packet_data[0] and packet_data[1]")
}

func disableEventConfigSplit(cur realm) {
	ufmt.Println("[STEP] update event config: disable packet_data attr splitting")

	testing.SetRealm(testing.NewUserRealm(eventConfigAdminAddr))
	core.SetSplitEventAttrs(cross(cur), false)
	config := core.GetEventConfig()
	ufmt.Printf("[INFO] split_event_attrs: %t\n", config.SplitEventAttrs)
	ufmt.Printf("[INFO] max_event_attr_value_len: %d\n", config.MaxEventAttrValueLen)
	ufmt.Printf("[INFO] max_packet_data_event_columns: %d\n", config.MaxPacketDataEventColumns)
	ufmt.Printf("[INFO] packet_data_budget: %d\n", core.MaxPacketDataEventSize())
	ufmt.Printf("[INFO] oversized_packet_allowed: %t\n", core.IsValidPacketDataSize(make([]byte, 16)))
}

func sendWithSplitDisabled(cur realm, channelId types.ChannelId) {
	ufmt.Println("[STEP] after config change: emit packet_data as one attr")

	testing.SetRealm(testing.NewUserRealm(eventConfigAdminAddr))
	packet := core.SendPacket(cross(cur), channelId, types.Timestamp(1), []byte{0xdd, 0xee, 0xff})
	ufmt.Printf("[INFO] after_packet_data_size: %d\n", eventConfigHexAttrLen(packet.Data))
	ufmt.Println("[EXPECTED] after PacketSend uses packet_data")
}

func eventConfigHexAttrLen(b []byte) int {
	return len(b)*2 + 2
}

type eventConfigScenarioApp struct{}

func (*eventConfigScenarioApp) OnChannelOpenInit(_ realm, _ types.ConnectionId, _ types.ChannelId, _ string, _ address) {
}

func (*eventConfigScenarioApp) OnChannelOpenTry(_ realm, _ types.ConnectionId, _ types.ChannelId, _ string, _ string, _ address) {
}

func (*eventConfigScenarioApp) OnChannelOpenAck(_ realm, _ types.ChannelId, _ types.ChannelId, _ string, _ address) {
}

func (*eventConfigScenarioApp) OnChannelOpenConfirm(_ realm, _ types.ChannelId, _ address) {
}

func (*eventConfigScenarioApp) OnChannelCloseInit(_ realm, _ types.ChannelId, _ address) {
}

func (*eventConfigScenarioApp) OnChannelCloseConfirm(_ realm, _ types.ChannelId, _ address) {
}

func (*eventConfigScenarioApp) OnRecvPacket(_ realm, _ types.Packet, _ address, _ []byte) types.RecvPacketResult {
	return core.NewRecvPacketResult(types.PacketStatusSuccess, nil)
}

func (*eventConfigScenarioApp) OnIntentRecvPacket(_ realm, _ types.Packet, _ address, _ []byte) types.RecvPacketResult {
	return core.NewRecvPacketResult(types.PacketStatusSuccess, nil)
}

func (*eventConfigScenarioApp) OnAcknowledgementPacket(_ realm, _ types.Packet, _ []byte, _ address) {
}

func (*eventConfigScenarioApp) OnTimeoutPacket(_ realm, _ types.Packet, _ address) {
}

type eventConfigMockLightClient struct{}

func (m *eventConfigMockLightClient) VerifyMembership(uint64, []byte, []byte, []byte) error {
	return nil
}

func (m *eventConfigMockLightClient) VerifyNonMembership(uint64, []byte, []byte) error {
	return nil
}

func (m *eventConfigMockLightClient) GetTimestamp() types.Timestamp {
	return types.Timestamp(1)
}

func (m *eventConfigMockLightClient) GetTimestampAtHeight(uint64) (types.Timestamp, error) {
	return types.Timestamp(1), nil
}

func (m *eventConfigMockLightClient) GetLatestHeight() uint64 {
	return 1
}

func (m *eventConfigMockLightClient) GetCounterpartyChainID() string {
	return "mock-chain"
}

func (m *eventConfigMockLightClient) Status() lightclient.Status {
	return lightclient.Active
}

func (m *eventConfigMockLightClient) VerifyHeader(_ address, header []byte, _ address) (types.StateUpdate, error) {
	return types.StateUpdate{Height: 1, ClientStateBytes: header, ConsensusStateBytes: header}, nil
}

func (m *eventConfigMockLightClient) VerifyCreation(address, address) (types.ClientCreationResult, error) {
	return types.ClientCreationResult{}, nil
}

func (m *eventConfigMockLightClient) Misbehaviour(address, []byte, address) ([]byte, error) {
	return nil, errEventConfigMisbehaviourUnsupported
}

var errEventConfigMisbehaviourUnsupported = eventConfigMockError("mock: misbehaviour unsupported")

type eventConfigMockError string

func (e eventConfigMockError) Error() string {
	return string(e)
}

// Output:
// [SCENARIO] event config drives packet send events
// [STEP] bootstrap core proxy
// [STEP] open event config channel
// [INFO] channel_id: 1
// [STEP] before config change: split packet_data attrs
// [INFO] split_event_attrs: true
// [INFO] max_event_attr_value_len: 4
// [INFO] max_packet_data_event_columns: 2
// [INFO] packet_data_budget: 8
// [INFO] oversized_packet_rejected: true
// [INFO] before_packet_data_size: 8
// [EXPECTED] before PacketSend uses packet_data[0] and packet_data[1]
// [STEP] update event config: disable packet_data attr splitting
// [INFO] split_event_attrs: false
// [INFO] max_event_attr_value_len: 4
// [INFO] max_packet_data_event_columns: 2
// [INFO] packet_data_budget: 8
// [INFO] oversized_packet_allowed: true
// [STEP] after config change: emit packet_data as one attr
// [INFO] after_packet_data_size: 8
// [EXPECTED] after PacketSend uses packet_data

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
//         "value": "scenario-event-config-lc"
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
//         "value": "scenario-event-config-lc"
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
//         "value": "event-config-v1"
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
//         "value": "event-config-v1"
//       }
//     ],
//     "pkg_path": "gno.land/r/onbloc/ibc/union/core"
//   },
//   {
//     "type": "PacketSend",
//     "attrs": [
//       {
//         "key": "packet_hash",
//         "value": "0x11ee731648e2573710d3a4843567d7c9de8f17acc1d9aa1f5c1a1e4338809bf8"
//       },
//       {
//         "key": "source_channel_id",
//         "value": "1"
//       },
//       {
//         "key": "source_channel_version",
//         "value": "event-config-v1"
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
//         "value": "8"
//       },
//       {
//         "key": "packet_data[0]",
//         "value": "0xaa"
//       },
//       {
//         "key": "packet_data[1]",
//         "value": "bbcc"
//       }
//     ],
//     "pkg_path": "gno.land/r/onbloc/ibc/union/core"
//   },
//   {
//     "type": "PacketSend",
//     "attrs": [
//       {
//         "key": "packet_hash",
//         "value": "0x0b0fcb42acf152d766f6b174a40dfc7092feace9ee143387a094dbaab326c7ac"
//       },
//       {
//         "key": "source_channel_id",
//         "value": "1"
//       },
//       {
//         "key": "source_channel_version",
//         "value": "event-config-v1"
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
//         "key": "packet_data",
//         "value": "0xddeeff"
//       }
//     ],
//     "pkg_path": "gno.land/r/onbloc/ibc/union/core"
//   }
// ]
