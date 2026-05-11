package zkgm

import (
	"chain/banker"
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
	// An intermediate realm (or `maketx run`) can attach -send to the outer tx
	// but spend it elsewhere, so OriginSend only reflects coins that landed
	// here when the caller is the EOA.
	var sentCoins string
	if runtime.PreviousRealm().IsUserCall() {
		sentCoins = banker.OriginSend().String()
	}
	packet, err := impl.Send(SendRequest{
		ChannelId:        channelId,
		TimeoutTimestamp: timeoutTimestamp,
		Salt:             salt,
		Instruction:      instruction,
		Sender:           runtime.OriginCaller().String(),
		SentCoins:        sentCoins,
	})
	if err != nil {
		panic(err)
	}
	return packet
}
