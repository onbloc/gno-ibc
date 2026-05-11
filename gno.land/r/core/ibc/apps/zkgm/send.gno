package zkgm

import (
	"chain/banker"
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
	// Note: an intermediate realm (or `maketx run`) can attach
	// -send to the outer tx but spend it elsewhere, so OriginSend only
	// reflects coins that landed here when the caller is the EOA.
	var sentCoins string
	if runtime.PreviousRealm().IsUserCall() {
		sentCoins = banker.OriginSend().String()
	}
	req := SendRequest{
		ChannelID:        channelID,
		TimeoutTimestamp: timeoutTimestamp,
		Salt:             salt,
		Instruction:      instruction,
		Sender:           runtime.OriginCaller().String(),
		SentCoins:        sentCoins,
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
