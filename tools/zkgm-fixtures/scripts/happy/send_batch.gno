// Happy-path probe: Batch of two Call sub-instructions, both with
// sender = tx signer and eureka = false.
package main

import (
	"chain/runtime"

	z "gno.land/p/gnoswap/ibc/zkgm"
	core "gno.land/r/core/ibc/v1/core"
	e2e "gno.land/r/gnoswap/ibc/v1/apps/zkgm/testing/e2e"
	zkgm "gno.land/r/gnoswap/ibc/v1/apps/zkgm"
)

func main() {
	e2e.RegisterMockLightClient(cross)
	pair := e2e.OpenE2EChannelPair(cross)

	signer := runtime.OriginCaller().String()
	call1 := z.Call{
		Sender:           []byte(signer),
		Eureka:           false,
		ContractAddress:  []byte("contract-a"),
		ContractCalldata: []byte{0xCA, 0xFE},
	}
	call2 := z.Call{
		Sender:           []byte(signer),
		Eureka:           false,
		ContractAddress:  []byte("contract-b"),
		ContractCalldata: nil,
	}
	c1Bytes, err := z.EncodeCall(call1)
	if err != nil {
		panic(err)
	}
	c2Bytes, err := z.EncodeCall(call2)
	if err != nil {
		panic(err)
	}
	batch := z.Batch{Instructions: []z.Instruction{
		{Version: z.INSTR_VERSION_0, Opcode: z.OP_CALL, Operand: c1Bytes},
		{Version: z.INSTR_VERSION_0, Opcode: z.OP_CALL, Operand: c2Bytes},
	}}
	operand, err := z.EncodeBatch(batch)
	if err != nil {
		panic(err)
	}
	packet := zkgm.Send(cross,
		pair.Source,
		core.Timestamp(1700000000000000000),
		[32]byte{},
		z.Instruction{Version: z.INSTR_VERSION_0, Opcode: z.OP_BATCH, Operand: operand},
	)
	println("source_channel", pair.Source.String())
	println("destination_channel", pair.Destination.String())
	println("packet.Data.len", len(packet.Data))
}
