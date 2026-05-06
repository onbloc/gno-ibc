package main

import (
	"chain/runtime"
	"time"

	z "gno.land/p/gnoswap/ibc/zkgm"
	zkgm "gno.land/r/gnoswap/ibc/apps/zkgm"
	_ "gno.land/r/gnoswap/ibc/apps/zkgm/v0/loader"
)

func main() {
	r := revive(func() {
		zkgm.Send(cross, "client-1", uint64(time.Now().Add(time.Hour).Unix()), [32]byte{}, mustBatchInstruction(z.Batch{
			Instructions: []z.Instruction{mustBatchInstruction(z.Batch{
				Instructions: []z.Instruction{mustCallInstruction()},
			})},
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

func mustBatchInstruction(batch z.Batch) z.Instruction {
	batchBytes, err := z.EncodeBatch(batch)
	if err != nil {
		panic(err)
	}
	return z.Instruction{Version: z.INSTR_VERSION_0, Opcode: z.OP_BATCH, Operand: batchBytes}
}

// Output:
// panic_message zkgm/v0: invalid batch instruction
