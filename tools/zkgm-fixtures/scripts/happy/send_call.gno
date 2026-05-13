// Happy-path probe: open a mock-LC backed channel pair, then invoke
// zkgm.Send with a clean Call instruction (sender = tx signer, eureka =
// false). All three steps land in one tx; we print the produced packet
// fields so callers can correlate the on-chain commit.
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
	call := z.Call{
		Sender:           []byte(signer),
		Eureka:           false,
		ContractAddress:  []byte("any-contract"),
		ContractCalldata: nil,
	}
	operand, err := z.EncodeCall(call)
	if err != nil {
		panic(err)
	}

	packet := zkgm.Send(
		cross,
		pair.Source,
		core.Timestamp(1700000000000000000),
		[32]byte{},
		z.Instruction{
			Version: z.INSTR_VERSION_0,
			Opcode:  z.OP_CALL,
			Operand: operand,
		},
	)

	println("source_channel", pair.Source.String())
	println("destination_channel", pair.Destination.String())
	println("client_id", pair.ClientId.String())
	println("connection_id", pair.ConnectionId.String())
	println("packet.SourceChannelId", packet.SourceChannelId.String())
	println("packet.DestinationChannelId", packet.DestinationChannelId.String())
	println("packet.TimeoutTimestamp", packet.TimeoutTimestamp.String())
	println("packet.Data.len", len(packet.Data))
}
