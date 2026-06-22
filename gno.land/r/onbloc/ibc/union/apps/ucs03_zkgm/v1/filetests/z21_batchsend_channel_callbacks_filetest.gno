// PKGPATH: gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/v1/main
package main

import (
	types "gno.land/p/onbloc/ibc/union/types"
	zkgm "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm"
	impl "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/v1"
)

func main(cur realm) {
	app := impl.NewUCS03ZkgmV1(zkgm.NewStore())

	app.OnChannelOpenInit(0, cur, types.ConnectionId(1), types.ChannelId(1), zkgm.Version, address("g1relayer"))
	app.OnChannelOpenAck(0, cur, types.ChannelId(1), types.ChannelId(2), zkgm.Version, address("g1relayer"))
	app.OnChannelOpenConfirm(0, cur, types.ChannelId(1), address("g1relayer"))

	packet := types.NewPacket(types.ChannelId(1), types.ChannelId(2), []byte("zkgm-packet"), types.Timestamp(3600))
	println("version", zkgm.Version)
	println("source_channel", packet.SourceChannelId.String())
	println("destination_channel", packet.DestinationChannelId.String())
	println("packet_source", packet.SourceChannelId.String())
	println("packet_destination", packet.DestinationChannelId.String())
}

// Output:
// version ucs03-zkgm-0
// source_channel 1
// destination_channel 2
// packet_source 1
// packet_destination 2
