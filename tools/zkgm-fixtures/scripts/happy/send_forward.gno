// Happy-path probe: Forward wrapping a Call.
package main

import (
	"chain/runtime"

	z "gno.land/p/gnoswap/ibc/zkgm"
	u256 "gno.land/p/gnoswap/uint256"
	core "gno.land/r/core/ibc/v1/core"
	e2e "gno.land/r/gnoswap/ibc/v1/apps/zkgm/testing/e2e"
	zkgm "gno.land/r/gnoswap/ibc/v1/apps/zkgm"
)

func main() {
	e2e.RegisterMockLightClient(cross)
	pair := e2e.OpenE2EChannelPair(cross)

	signer := runtime.OriginCaller().String()
	inner := z.Call{
		Sender:           []byte(signer),
		Eureka:           false,
		ContractAddress:  []byte("inner-contract"),
		ContractCalldata: []byte{0xDE, 0xAD},
	}
	innerBytes, _ := z.EncodeCall(inner)
	forward := z.Forward{
		Path:             u256.NewUint(1),
		TimeoutHeight:    0,
		TimeoutTimestamp: 1700000000000000000,
		Instruction:      z.Instruction{Version: z.INSTR_VERSION_0, Opcode: z.OP_CALL, Operand: innerBytes},
	}
	operand, err := z.EncodeForward(forward)
	if err != nil {
		panic(err)
	}
	packet := zkgm.Send(cross,
		pair.Source,
		core.Timestamp(1700000000000000000),
		[32]byte{},
		z.Instruction{Version: z.INSTR_VERSION_0, Opcode: z.OP_FORWARD, Operand: operand},
	)
	println("source_channel", pair.Source.String())
	println("destination_channel", pair.Destination.String())
	println("packet.Data.len", len(packet.Data))
}
