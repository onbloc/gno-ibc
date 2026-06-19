package zkgm

import (
	"chain/runtime"
	"encoding/hex"

	types "gno.land/p/onbloc/ibc/union/types"

	rtunsafe "chain/runtime/unsafe"

	z "gno.land/p/onbloc/ibc/union/zkgm"
	core "gno.land/r/onbloc/ibc/union/core"
)

func Send(cur realm, channelId types.ChannelId, timeoutTimestamp types.Timestamp, salt [32]byte, instruction z.Instruction) types.Packet {
	if paused {
		panic("zkgm: paused")
	}
	cacheRealm(cur)
	if impl == nil {
		panic("zkgm: impl not set")
	}

	var sentCoins string
	if cur.Previous().IsUserCall() {
		// SAFE: OriginSend is only trusted for direct EOA calls, where sent
		// coins land in this realm before Send executes.
		sentCoins = rtunsafe.OriginSend().String()
	}

	runtime.AssertOriginCall()
	return sendPacket(cur, channelId, timeoutTimestamp, salt, instruction, cur.Previous().Address().String(), sentCoins)
}

// SendRaw is a gnokey-friendly wrapper around Send. `maketx call` cannot pass
// z.Instruction or [32]byte values directly, so external smoke tests pass those
// fields as primitive hex/string arguments instead.
func SendRaw(cur realm, channelId uint32, timeoutTimestamp uint64, saltHex string, version uint8, opcode uint8, operandHex string) types.Packet {
	if paused {
		panic("zkgm: paused")
	}
	cacheRealm(cur)
	saltBytes := mustDecodeHexArg("salt", saltHex)
	if len(saltBytes) != 32 {
		panic("zkgm: salt must be 32 bytes")
	}
	var salt [32]byte
	copy(salt[:], saltBytes)

	var sentCoins string
	if cur.Previous().IsUserCall() {
		// SAFE: OriginSend is only trusted for direct EOA calls, where sent
		// coins land in this realm before SendRaw executes.
		sentCoins = rtunsafe.OriginSend().String()
	}

	runtime.AssertOriginCall()
	return sendPacket(
		cur,
		types.ChannelId(channelId),
		types.Timestamp(timeoutTimestamp),
		salt,
		z.Instruction{
			Version: version,
			Opcode:  opcode,
			Operand: mustDecodeHexArg("operand", operandHex),
		},
		cur.Previous().Address().String(),
		sentCoins,
	)
}

func sendPacket(cur realm, channelId types.ChannelId, timeoutTimestamp types.Timestamp, salt [32]byte, instruction z.Instruction, sender string, sentCoins string) types.Packet {
	assertNonZeroTimeout(timeoutTimestamp)
	if paused {
		panic("zkgm: paused")
	}
	if impl == nil {
		panic("zkgm: impl not set")
	}

	data, err := impl.Send(cross(cur), NewSendRequest(cur, channelId, timeoutTimestamp, salt, instruction, sender, sentCoins))
	if err != nil {
		panic(err)
	}

	return core.SendPacket(cross(cur), channelId, timeoutTimestamp, data)
}

func assertNonZeroTimeout(timeoutTimestamp types.Timestamp) {
	if timeoutTimestamp == 0 {
		panic("zkgm: timeout timestamp must be non-zero")
	}
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
