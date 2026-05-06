package main

import (
	"chain/runtime"
	"time"

	z "gno.land/p/gnoswap/ibc/zkgm"
	u256 "gno.land/p/gnoswap/uint256"
	zkgm "gno.land/r/gnoswap/ibc/apps/zkgm"
	_ "gno.land/r/gnoswap/ibc/apps/zkgm/v0/loader"
)

func main() {
	r := revive(func() {
		zkgm.Send(cross, "client-1", uint64(time.Now().Add(time.Hour).Unix()), [32]byte{}, mustForwardInstruction(z.Forward{
			Path:        forwardPath(1, 2),
			Instruction: mustForwardInstruction(z.Forward{Path: forwardPath(2, 3), Instruction: mustCallInstruction()}),
		}))
	})
	println("panic_message", r)
}

func mustCallInstruction() z.Instruction {
	callBytes, err := z.EncodeCall(z.Call{
		Sender:          []byte(runtime.OriginCaller().String()),
		ContractAddress: []byte("gno.land/r/gnoswap/ibc/apps/zkgm/testing/mock"),
	})
	if err != nil {
		panic(err)
	}
	return z.Instruction{Version: z.INSTR_VERSION_0, Opcode: z.OP_CALL, Operand: callBytes}
}

func mustForwardInstruction(forward z.Forward) z.Instruction {
	forwardBytes, err := z.EncodeForward(forward)
	if err != nil {
		panic(err)
	}
	return z.Instruction{Version: z.INSTR_VERSION_0, Opcode: z.OP_FORWARD, Operand: forwardBytes}
}

func forwardPath(channels ...uint64) *u256.Uint {
	path := u256.Zero()
	for i, channel := range channels {
		path = new(u256.Uint).Or(path, new(u256.Uint).Lsh(u256.NewUint(channel), uint(32*i)))
	}
	return path
}

// Output:
// panic_message zkgm/v0: invalid forward instruction
