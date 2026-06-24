// PKGPATH: gno.land/r/onbloc/ibc/scenario/union
package union

import (
	"testing"

	"gno.land/p/nt/ufmt/v0"
	"gno.land/p/onbloc/ibc/union/lightclient"
	types "gno.land/p/onbloc/ibc/union/types"

	"gno.land/r/onbloc/ibc/union/access"
	zkgm "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm"
	_ "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/v1"
	core "gno.land/r/onbloc/ibc/union/core"
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

	testing.SetRealm(testing.NewUserRealm(eventAdminAddr))
	core.UpdateImpl(cross(cur), eventCoreImplPath)
	zkgm.UpdateImpl(cross(cur), eventZkgmImplPath)
	zkgm.RegisterCoreApp(cross(cur))
	access.GrantRole(cross(cur), access.RelayerRole, eventAdminAddr)

	core.RegisterClient(cross(cur), eventMockClientType, func(_, _ []byte) (lightclient.Interface, error) {
		return &eventMockLightClient{}, nil
	})
	core.CreateClient(cross(cur), core.NewMsgCreateClient(eventMockClientType, nil, nil))
	clientId := types.ClientId(1)

	core.ConnectionOpenInit(cross(cur), core.NewMsgConnectionOpenInit(clientId, types.ClientId(99)))
	connectionId := types.ConnectionId(1)
	core.ConnectionOpenAck(cross(cur), core.NewMsgConnectionOpenAck(connectionId, types.ConnectionId(77), nil, 1))

	portId := []byte(zkgm.ProxyPkgPath())
	core.ChannelOpenInit(cross(cur), core.NewMsgChannelOpenInit(portId, portId, connectionId, zkgm.Version, "g1relayer"))
	channelId := types.ChannelId(1)
	core.ChannelOpenAck(cross(cur), core.NewMsgChannelOpenAck(channelId, zkgm.Version, types.ChannelId(2), nil, 1, "g1relayer"))

	malformedPacket := core.NewPacket(types.ChannelId(2), channelId, []byte{0x01}, types.Timestamp(1<<62))
	core.PacketRecv(cross(cur), core.NewMsgPacketRecv([]types.Packet{malformedPacket}, [][]byte{nil}, nil, 1))

	ufmt.Println("[INFO] malformed recv completed with failure ack")
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
	return nil, eventErrMisbehaviourUnsupported
}

var eventErrMisbehaviourUnsupported = eventMockError("mock: misbehaviour unsupported")

type eventMockError string

func (e eventMockError) Error() string { return string(e) }

// Output:
// [SCENARIO] proxy event emitters
// [INFO] malformed recv completed with failure ack

// Events:
// [
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
//     "type": "ChannelOpenInit",
//     "attrs": [
//       {
//         "key": "port_id",
//         "value": "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm"
//       },
//       {
//         "key": "channel_id",
//         "value": "1"
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
//         "value": "1"
//       },
//       {
//         "key": "counterparty_port_id",
//         "value": "0x676e6f2e6c616e642f722f6f6e626c6f632f6962632f756e696f6e2f617070732f75637330335f7a6b676d"
//       },
//       {
//         "key": "counterparty_channel_id",
//         "value": "2"
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
//         "value": "2"
//       },
//       {
//         "key": "destination_channel",
//         "value": "1"
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
//         "key": "channel_id",
//         "value": "1"
//       },
//       {
//         "key": "packet_hash",
//         "value": "0xe5865ea306619a2ef35bf19947fb268fd14f49f865bf6fb6e4376ae49a04b5da"
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
//         "value": "0xe5865ea306619a2ef35bf19947fb268fd14f49f865bf6fb6e4376ae49a04b5da"
//       },
//       {
//         "key": "packet_data",
//         "value": "0x01"
//       },
//       {
//         "key": "source_channel_id",
//         "value": "2"
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
//   }
// ]
