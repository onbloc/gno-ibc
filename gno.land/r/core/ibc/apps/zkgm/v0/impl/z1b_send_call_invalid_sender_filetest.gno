package main

import (
	"time"

	z "gno.land/p/gnoswap/ibc/zkgm"
	zkgm "gno.land/r/gnoswap/ibc/apps/zkgm"
	_ "gno.land/r/gnoswap/ibc/apps/zkgm/v0/loader"
)

func main() {
	r := revive(func() {
		zkgm.Send(cross, "client-1", uint64(time.Now().Add(time.Hour).Unix()), [32]byte{}, mustCallInstruction(z.Call{
			Sender:          []byte("not-origin-caller"),
			ContractAddress: []byte("gno.land/r/gnoswap/ibc/apps/zkgm/testing/mock"),
		}))
	})
	println("panic_message", r)
}

func mustCallInstruction(call z.Call) z.Instruction {
	callBytes, err := z.EncodeCall(call)
	if err != nil {
		panic(err)
	}
	return z.Instruction{Version: z.INSTR_VERSION_0, Opcode: z.OP_CALL, Operand: callBytes}
}

// Output:
// panic_message zkgm/v0: invalid call sender
