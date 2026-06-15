// PKGPATH: gno.land/r/onbloc/ibc/apps/ucs03_zkgm/testing/e2e/scenarios_batchsend
package scenarios_batchsend

import (
	e2e "gno.land/r/onbloc/ibc/apps/ucs03_zkgm/testing/e2e"
	core "gno.land/r/onbloc/ibc/core"
)

const batchAcksPort = "gno.land/r/onbloc/ibc/apps/ucs03_zkgm/testing/e2e/scenarios_batchsend"

type asyncApp struct{}

func (a *asyncApp) OnChannelOpenInit(cur realm, connectionId core.ConnectionId, channelId core.ChannelId, version string, relayer address) {
}

func (a *asyncApp) OnChannelOpenTry(cur realm, connectionId core.ConnectionId, channelId core.ChannelId, version string, counterpartyVersion string, relayer address) {
}

func (a *asyncApp) OnChannelOpenAck(cur realm, channelId core.ChannelId, counterpartyChannelId core.ChannelId, counterpartyVersion string, relayer address) {
}
func (a *asyncApp) OnChannelOpenConfirm(cur realm, channelId core.ChannelId, relayer address) {}
func (a *asyncApp) OnChannelCloseInit(cur realm, channelId core.ChannelId, relayer address)   {}
func (a *asyncApp) OnChannelCloseConfirm(cur realm, channelId core.ChannelId, relayer address) {
}

func (a *asyncApp) OnRecvPacket(cur realm, packet core.Packet, relayer address, relayerMsg []byte) core.RecvPacketResult {
	return core.NewRecvPacketResult(cross(cur), core.PacketStatusAsync, nil)
}

func (a *asyncApp) OnAcknowledgementPacket(cur realm, packet core.Packet, acknowledgement []byte, relayer address) {
}
func (a *asyncApp) OnTimeoutPacket(cur realm, packet core.Packet, relayer address) {}

func main(cur realm) {
	e2e.RegisterMockLightClient(cross(cur))
	core.RegisterApp(cross(cur), &asyncApp{})

	clientId := core.CreateClient(cross(cur), core.NewMsgCreateClient(cross(cur), e2e.MockClientType, nil, nil))
	connectionId := core.ConnectionOpenInit(cross(cur), core.NewMsgConnectionOpenInit(cross(cur), clientId, core.ClientId(99)))
	core.ConnectionOpenAck(cross(cur), core.NewMsgConnectionOpenAck(cross(cur), connectionId, core.ConnectionId(77), nil, core.Height(1)))
	channelId := core.ChannelOpenInit(cross(cur), core.NewMsgChannelOpenInit(cross(cur), []byte(batchAcksPort), []byte(batchAcksPort), connectionId, "async-v1"))
	core.ChannelOpenAck(cross(cur), core.NewMsgChannelOpenAck(cross(cur), channelId, "async-v1", core.ChannelId(101), nil, core.Height(1)))

	packet := core.NewPacket(cross(cur), core.ChannelId(99), channelId, []byte("async-packet"), 0, core.Timestamp(1<<62))
	core.PacketRecv(cross(cur), core.NewMsgPacketRecv(cross(cur), []core.Packet{packet}, nil, nil, core.Height(1)))

	batchHash := core.BatchAcks(cross(cur), core.NewMsgBatchAcks(cross(cur), []core.Packet{packet}, [][]byte{[]byte("ack")}))
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
//         "value": "gno.land/r/onbloc/ibc/apps/ucs03_zkgm/testing/e2e/mock"
//       },
//       {
//         "key": "registrar_pkg_path",
//         "value": "gno.land/r/onbloc/ibc/apps/ucs03_zkgm/testing/e2e"
//       },
//       {
//         "key": "admin_override",
//         "value": "false"
//       }
//     ],
//     "pkg_path": "gno.land/r/onbloc/ibc/core"
//   },
//   {
//     "type": "AppRegistered",
//     "attrs": [
//       {
//         "key": "port_id",
//         "value": "gno.land/r/onbloc/ibc/apps/ucs03_zkgm/testing/e2e/scenarios_batchsend"
//       },
//       {
//         "key": "registrar_pkg_path",
//         "value": "gno.land/r/onbloc/ibc/apps/ucs03_zkgm/testing/e2e/scenarios_batchsend"
//       },
//       {
//         "key": "admin_override",
//         "value": "false"
//       }
//     ],
//     "pkg_path": "gno.land/r/onbloc/ibc/core"
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
//         "value": "gno.land/r/onbloc/ibc/apps/ucs03_zkgm/testing/e2e/mock"
//       }
//     ],
//     "pkg_path": "gno.land/r/onbloc/ibc/core"
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
//     "pkg_path": "gno.land/r/onbloc/ibc/core"
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
//     "pkg_path": "gno.land/r/onbloc/ibc/core"
//   },
//   {
//     "type": "ChannelOpenInit",
//     "attrs": [
//       {
//         "key": "port_id",
//         "value": "gno.land/r/onbloc/ibc/apps/ucs03_zkgm/testing/e2e/scenarios_batchsend"
//       },
//       {
//         "key": "channel_id",
//         "value": "1"
//       },
//       {
//         "key": "counterparty_port_id",
//         "value": "0x676e6f2e6c616e642f722f6f6e626c6f632f756e696f6e6962632f76312f617070732f7a6b676d2f74657374696e672f6532652f7363656e6172696f735f626174636873656e64"
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
//     "pkg_path": "gno.land/r/onbloc/ibc/core"
//   },
//   {
//     "type": "ChannelOpenAck",
//     "attrs": [
//       {
//         "key": "port_id",
//         "value": "gno.land/r/onbloc/ibc/apps/ucs03_zkgm/testing/e2e/scenarios_batchsend"
//       },
//       {
//         "key": "channel_id",
//         "value": "1"
//       },
//       {
//         "key": "counterparty_port_id",
//         "value": "0x676e6f2e6c616e642f722f6f6e626c6f632f756e696f6e6962632f76312f617070732f7a6b676d2f74657374696e672f6532652f7363656e6172696f735f626174636873656e64"
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
//     "pkg_path": "gno.land/r/onbloc/ibc/core"
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
//     "pkg_path": "gno.land/r/onbloc/ibc/core"
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
//     "pkg_path": "gno.land/r/onbloc/ibc/core"
//   }
// ]
