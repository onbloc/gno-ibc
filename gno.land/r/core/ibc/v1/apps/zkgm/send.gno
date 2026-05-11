package zkgm

import (
	"chain/runtime"

	z "gno.land/p/gnoswap/ibc/zkgm"
	core "gno.land/r/core/ibc/v1/core"
)

func Send(cur realm, channelId core.ChannelId, timeoutTimestamp core.Timestamp, salt [32]byte, instruction z.Instruction) core.Packet {
	if paused {
		panic("zkgm: paused")
	}
	if impl == nil {
		panic("zkgm: impl not set")
	}
	data, err := z.EncodeZkgmPacket(z.ZkgmPacket{
		Salt:        salt,
		Path:        nil,
		Instruction: instruction,
	})
	if err != nil {
		panic(err)
	}
	packet, err := impl.Send(channelId, core.Bytes(data), timeoutTimestamp)
	if err != nil {
		panic(err)
	}
	_ = runtime.OriginCaller()
	return packet
}
