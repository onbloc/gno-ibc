package zkgm

import (
	"encoding/hex"

	types "gno.land/p/onbloc/ibc/union/types"

	z "gno.land/p/onbloc/ibc/union/zkgm"
)

func Send(cur realm, channelId types.ChannelId, timeoutTimestamp types.Timestamp, salt [32]byte, instruction z.Instruction) types.Packet {
	return mustGetImpl().Send(0, cur, channelId, timeoutTimestamp, salt, instruction)
}

func SendRaw(cur realm, channelId uint32, timeoutTimestamp uint64, saltHex string, version uint8, opcode uint8, operandHex string) types.Packet {
	saltBytes, err := parseHex(saltHex)
	if err != nil {
		panic(err)
	}

	if len(saltBytes) != 32 {
		panic(ErrInvalidSaltLength)
	}

	var salt [32]byte

	copy(salt[:], saltBytes)

	operandBytes, err := parseHex(operandHex)
	if err != nil {
		panic(err)
	}

	instruction := z.Instruction{
		Version: version,
		Opcode:  opcode,
		Operand: operandBytes,
	}

	return mustGetImpl().Send(0, cur, types.ChannelId(channelId), types.Timestamp(timeoutTimestamp), salt, instruction)
}

func parseHex(s string) ([]byte, error) {
	if len(s) >= 2 && s[0] == '0' && (s[1] == 'x' || s[1] == 'X') {
		s = s[2:]
	}

	bz, err := hex.DecodeString(s)
	if err != nil {
		return nil, err
	}

	return bz, nil
}
