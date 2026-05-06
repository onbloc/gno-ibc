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
	instr := mustCallInstruction(z.Call{
		Sender:           []byte(runtime.OriginCaller().String()),
		ContractAddress:  []byte("gno.land/r/gnoswap/ibc/apps/zkgm/testing/mock"),
		ContractCalldata: []byte("hello-zkgm"),
	})
	seq, hash := zkgm.Send(cross, setupClient(), uint64(time.Now().Add(time.Hour).Unix()), [32]byte{}, instr)

	println("sequence", seq)
	println("packet_hash_len", len(hash))
}

func setupClient() string {
	clientID := core.CreateClient(cross,
		tmtesting.NewClientState("chain-id-2", types.NewHeight(2, 2)),
		tmtesting.GenConsensusState(time.Now(), tmtesting.Hash("apphash"), tmtesting.GenValset().Hash()),
	)
	core.RegisterCounterparty(cross, clientID, [][]byte{[]byte("iavlStoreKey"), []byte("prefix2")}, "07-tendermint-2")
	return clientID
}

func mustCallInstruction(call z.Call) z.Instruction {
	callBytes, err := z.EncodeCall(call)
	if err != nil {
		panic(err)
	}
	return z.Instruction{Version: z.INSTR_VERSION_0, Opcode: z.OP_CALL, Operand: callBytes}
}

// Output:
// sequence 1
// packet_hash_len 32
