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
	order := z.TokenOrderV2{
		Sender:      []byte(runtime.OriginCaller().String()),
		Receiver:    []byte("counterparty-receiver"),
		BaseToken:   []byte("ugnot"),
		BaseAmount:  u256.NewUint(100),
		QuoteToken:  []byte("quote"),
		QuoteAmount: u256.NewUint(95),
		Kind:        z.TOKEN_ORDER_KIND_ESCROW,
	}

	r := revive(func() {
		zkgm.Send(cross, "client-1", uint64(time.Now().Add(time.Hour).Unix()), [32]byte{}, mustOrderInstruction(order))
	})
	println("panic_message", r)
}

func mustOrderInstruction(order z.TokenOrderV2) z.Instruction {
	orderBytes, err := z.EncodeTokenOrderV2(order)
	if err != nil {
		panic(err)
	}
	return z.Instruction{Version: z.INSTR_VERSION_2, Opcode: z.OP_TOKEN_ORDER, Operand: orderBytes}
}

// Output:
// panic_message zkgm/coins: sent coin mismatch
