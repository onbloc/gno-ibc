package main

import (
	"chain/runtime"
	"time"

	tmtesting "gno.land/p/aib/ibc/lightclient/tendermint/testing"
	"gno.land/p/aib/ibc/types"
	z "gno.land/p/gnoswap/ibc/zkgm"
	"gno.land/r/aib/ibc/core"
	zkgm "gno.land/r/gnoswap/ibc/apps/zkgm"
	_ "gno.land/r/gnoswap/ibc/apps/zkgm/v0/loader"
)

func main() {
	instr := mustCallInstruction()
	zkgm.Pause(cross)
	r := revive(func() {
		zkgm.Send(cross, "client-1", uint64(time.Now().Add(time.Hour).Unix()), [32]byte{}, instr)
	})
	println("paused_panic", r)

	zkgm.Unpause(cross)
	seq, _ := zkgm.Send(cross, setupClient(), uint64(time.Now().Add(time.Hour).Unix()), [32]byte{}, instr)
	println("after_unpause_seq", seq)
}

func setupClient() string {
	clientID := core.CreateClient(cross,
		tmtesting.NewClientState("chain-id-2", types.NewHeight(2, 2)),
		tmtesting.GenConsensusState(time.Now(), tmtesting.Hash("apphash"), tmtesting.GenValset().Hash()),
	)
	core.RegisterCounterparty(cross, clientID, [][]byte{[]byte("iavlStoreKey"), []byte("prefix2")}, "07-tendermint-2")
	return clientID
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

// Output:
// paused_panic zkgm: paused
// after_unpause_seq 1
