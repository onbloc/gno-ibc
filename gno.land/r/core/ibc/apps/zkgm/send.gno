package zkgm

import (
	"chain/runtime"

	z "gno.land/p/gnoswap/ibc/zkgm"
)

func Send(cur realm, channelID string, timeoutTimestamp uint64, salt [32]byte, instruction z.Instruction) (uint64, [32]byte) {
	if paused {
		panic("zkgm: paused")
	}
	if impl == nil {
		panic("zkgm: impl not set")
	}
	req := SendRequest{
		ChannelID:        channelID,
		TimeoutTimestamp: timeoutTimestamp,
		Salt:             salt,
		Instruction:      instruction,
		Sender:           runtime.OriginCaller().String(),
		SentCoins:        cur.SentCoins().String(),
	}
	if err := impl.PreSend(req); err != nil {
		panic(err)
	}
	res, err := impl.Send(req)
	if err != nil {
		panic(err)
	}
	impl.PostSend(req, res)
	return res.PacketSequence, res.PacketHash
}
