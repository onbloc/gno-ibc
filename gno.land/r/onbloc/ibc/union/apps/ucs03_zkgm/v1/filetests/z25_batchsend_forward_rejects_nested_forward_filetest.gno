// PKGPATH: gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/v1/main
package main

import (
	types "gno.land/p/onbloc/ibc/union/types"
	z "gno.land/p/onbloc/ibc/union/zkgm"
	u256 "gno.land/p/gnoswap/uint256"
	zkgm "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm"
	impl "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/v1"
)

func main(cur realm) {
	app := impl.NewUCS03ZkgmV1(zkgm.NewStore())
	nested := z.Forward{
		Path: mustZ25ForwardPath(1, 2),
		Instruction: z.Instruction{
			Version: z.INSTR_VERSION_0,
			Opcode:  z.OP_FORWARD,
			Operand: mustZ25ForwardBytes(z.Forward{Path: mustZ25ForwardPath(1, 2)}),
		},
	}
	forward := z.Forward{
		Path:             mustZ25ForwardPath(2, 3),
		TimeoutTimestamp: 999,
		Instruction:      mustZ25ForwardInstruction(nested),
	}
	packet := types.NewPacket(types.ChannelId(1), types.ChannelId(2), mustZ25PacketData(mustZ25ForwardInstruction(forward)), 0)

	result := app.OnRecvPacket(0, cur, packet, address("g1relayer"), nil)
	ack, _ := z.DecodeAck(result.Acknowledgement)
	println("status", int(result.Status))
	println("failure_tag_zero", ack.Tag.IsZero())
}

func mustZ25ForwardPath(channels ...uint32) *u256.Uint {
	path := u256.Zero()
	for _, channel := range channels {
		next, err := z.UpdateChannelPath(path, channel)
		if err != nil {
			panic(err)
		}
		path = next
	}
	return path
}

func mustZ25ForwardBytes(forward z.Forward) []byte {
	bz, err := z.EncodeForward(forward)
	if err != nil {
		panic(err)
	}
	return bz
}

func mustZ25ForwardInstruction(forward z.Forward) z.Instruction {
	return z.Instruction{Version: z.INSTR_VERSION_0, Opcode: z.OP_FORWARD, Operand: mustZ25ForwardBytes(forward)}
}

func mustZ25PacketData(instr z.Instruction) []byte {
	bz, err := z.EncodeZkgmPacket(z.ZkgmPacket{Path: u256.Zero(), Instruction: instr})
	if err != nil {
		panic(err)
	}
	return bz
}

// Output:
// status 2
// failure_tag_zero true
