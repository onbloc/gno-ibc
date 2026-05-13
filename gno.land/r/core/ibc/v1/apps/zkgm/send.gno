package zkgm

import (
	"chain/banker"
	"chain/runtime"
	"encoding/hex"

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

	return sendPacket(channelId, timeoutTimestamp, salt, instruction, sentCoins)
}

// SendRaw is a gnokey-friendly wrapper around Send. `maketx call` cannot pass
// z.Instruction or [32]byte values directly, so external smoke tests pass those
// fields as primitive hex/string arguments instead.
func SendRaw(cur realm, channelId uint32, timeoutTimestamp uint64, saltHex string, version uint8, opcode uint8, operandHex string) core.Packet {
	saltBytes := mustDecodeHexArg("salt", saltHex)
	if len(saltBytes) != 32 {
		panic("zkgm: salt must be 32 bytes")
	}
	var salt [32]byte
	copy(salt[:], saltBytes)

	var sentCoins string
	if runtime.PreviousRealm().IsUserCall() {
		sentCoins = banker.OriginSend().String()
	}

	return sendPacket(
		core.ChannelId(channelId),
		core.Timestamp(timeoutTimestamp),
		salt,
		z.Instruction{
			Version: version,
			Opcode:  opcode,
			Operand: mustDecodeHexArg("operand", operandHex),
		},
		sentCoins,
	)
}

func sendPacket(channelId core.ChannelId, timeoutTimestamp core.Timestamp, salt [32]byte, instruction z.Instruction, sentCoins string) core.Packet {
	if paused {
		panic("zkgm: paused")
	}
	if impl == nil {
		panic("zkgm: impl not set")
	}

	data, err := impl.Send(SendRequest{
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

	return core.PacketSend(cross, channelId, 0, timeoutTimestamp, data)
}

func mustDecodeHexArg(name string, s string) []byte {
	if len(s) >= 2 && s[0] == '0' && (s[1] == 'x' || s[1] == 'X') {
		s = s[2:]
	}
	bz, err := hex.DecodeString(s)
	if err != nil {
		panic("zkgm: invalid " + name + " hex")
	}
	return bz
}
