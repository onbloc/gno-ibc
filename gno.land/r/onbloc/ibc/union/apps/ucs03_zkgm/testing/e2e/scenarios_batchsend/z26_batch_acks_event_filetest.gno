// PKGPATH: gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/testing/e2e/scenarios_batchsend
package scenarios_batchsend

import (
	types "gno.land/p/onbloc/ibc/union/types"

	e2e "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/testing/e2e"
	core "gno.land/r/onbloc/ibc/union/core"
)

const batchAcksPort = "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/testing/e2e/scenarios_batchsend"

type asyncApp struct{}

func (a *asyncApp) OnChannelOpenInit(cur realm, connectionId types.ConnectionId, channelId types.ChannelId, version string, relayer address) {
}

func (a *asyncApp) OnChannelOpenTry(cur realm, connectionId types.ConnectionId, channelId types.ChannelId, version string, counterpartyVersion string, relayer address) {
}

func (a *asyncApp) OnChannelOpenAck(cur realm, channelId types.ChannelId, counterpartyChannelId types.ChannelId, counterpartyVersion string, relayer address) {
}
func (a *asyncApp) OnChannelOpenConfirm(cur realm, channelId types.ChannelId, relayer address) {}
func (a *asyncApp) OnChannelCloseInit(cur realm, channelId types.ChannelId, relayer address)   {}
func (a *asyncApp) OnChannelCloseConfirm(cur realm, channelId types.ChannelId, relayer address) {
}

func (a *asyncApp) OnRecvPacket(cur realm, packet types.Packet, relayer address, relayerMsg []byte) types.RecvPacketResult {
	return core.NewRecvPacketResult(cross(cur), types.PacketStatusAsync, nil)
}

func (a *asyncApp) OnAcknowledgementPacket(cur realm, packet types.Packet, acknowledgement []byte, relayer address) {
}
func (a *asyncApp) OnTimeoutPacket(cur realm, packet types.Packet, relayer address) {}

func main(cur realm) {
	e2e.RegisterMockLightClient(cross(cur))
	core.RegisterApp(cross(cur), &asyncApp{})

	clientId := core.CreateClient(cross(cur), types.NewMsgCreateClient(e2e.MockClientType, nil, nil))
	connectionId := core.ConnectionOpenInit(cross(cur), types.NewMsgConnectionOpenInit(clientId, types.ClientId(99)))
	core.ConnectionOpenAck(cross(cur), types.NewMsgConnectionOpenAck(connectionId, types.ConnectionId(77), nil, 1))
	channelId := core.ChannelOpenInit(cross(cur), types.NewMsgChannelOpenInit([]byte(batchAcksPort), []byte(batchAcksPort), connectionId, "async-v1"))
	core.ChannelOpenAck(cross(cur), types.NewMsgChannelOpenAck(channelId, "async-v1", types.ChannelId(101), nil, 1))

	packet := core.NewPacket(cross(cur), types.ChannelId(99), channelId, []byte("async-packet"), types.Timestamp(1<<62))
	core.PacketRecv(cross(cur), types.NewMsgPacketRecv([]types.Packet{packet}, [][]byte{nil}, address(""), nil, 1))

	batchHash := core.BatchAcks(cross(cur), types.NewMsgBatchAcks([]types.Packet{packet}, [][]byte{[]byte("ack")}))
	println("batch_acks_hash", batchHash.String())
	println("batch_acks_event", "ok")
}

// Output:
// batch_acks_hash 0xb75079c4d060e9310567dfe8825dcfbbc96c9cd0acfbb443517b61a01faf3c40
// batch_acks_event ok

// Events:
// [
//   {
//     "type": "ClientRegistered",
//     "attrs": [
//       {
//         "key": "client_type",
//         "value": "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/testing/e2e/mock"
//       },
//       {
//         "key": "registrar_pkg_path",
//         "value": "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/testing/e2e"
//       },
//       {
//         "key": "admin_override",
//         "value": "false"
//       }
//     ],
//     "pkg_path": "gno.land/r/onbloc/ibc/union/core"
//   },
//   {
//     "type": "AppRegistered",
//     "attrs": [
//       {
//         "key": "port_id",
//         "value": "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/testing/e2e/scenarios_batchsend"
//       },
//       {
//         "key": "registrar_pkg_path",
//         "value": "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/testing/e2e/scenarios_batchsend"
//       },
//       {
//         "key": "admin_override",
//         "value": "false"
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
//         "value": "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/testing/e2e/mock"
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
//         "value": "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/testing/e2e/scenarios_batchsend"
//       },
//       {
//         "key": "channel_id",
//         "value": "1"
//       },
//       {
//         "key": "counterparty_port_id",
//         "value": "0x676e6f2e6c616e642f722f6f6e626c6f632f6962632f756e696f6e2f617070732f75637330335f7a6b676d2f74657374696e672f6532652f7363656e6172696f735f626174636873656e64"
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
//         "value": "async-v1"
//       }
//     ],
//     "pkg_path": "gno.land/r/onbloc/ibc/union/core"
//   },
//   {
//     "type": "ChannelOpenAck",
//     "attrs": [
//       {
//         "key": "port_id",
//         "value": "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/testing/e2e/scenarios_batchsend"
//       },
//       {
//         "key": "channel_id",
//         "value": "1"
//       },
//       {
//         "key": "counterparty_port_id",
//         "value": "0x676e6f2e6c616e642f722f6f6e626c6f632f6962632f756e696f6e2f617070732f75637330335f7a6b676d2f74657374696e672f6532652f7363656e6172696f735f626174636873656e64"
//       },
//       {
//         "key": "counterparty_channel_id",
//         "value": "101"
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
//         "value": "async-v1"
//       }
//     ],
//     "pkg_path": "gno.land/r/onbloc/ibc/union/core"
//   },
//   {
//     "type": "PacketRecv",
//     "attrs": [
//       {
//         "key": "packet_hash",
//         "value": "0xb75079c4d060e9310567dfe8825dcfbbc96c9cd0acfbb443517b61a01faf3c40"
//       },
//       {
//         "key": "packet_data",
//         "value": "0x6173796e632d7061636b6574"
//       },
//       {
//         "key": "source_channel_id",
//         "value": "99"
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
//         "value": "async-v1"
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
//     "type": "BatchAcks",
//     "attrs": [
//       {
//         "key": "batch_hash",
//         "value": "0xb75079c4d060e9310567dfe8825dcfbbc96c9cd0acfbb443517b61a01faf3c40"
//       },
//       {
//         "key": "ack_hash",
//         "value": "0x01644e63d4e00fb98df51e358ca223c9095b3e27fe19de5647969de2d9f056bd"
//       },
//       {
//         "key": "destination_channel_id",
//         "value": "1"
//       },
//       {
//         "key": "destination_channel_version",
//         "value": "async-v1"
//       },
//       {
//         "key": "destination_connection_id",
//         "value": "1"
//       },
//       {
//         "key": "destination_connection_client_id",
//         "value": "1"
//       }
//     ],
//     "pkg_path": "gno.land/r/onbloc/ibc/union/core"
//   }
// ]
