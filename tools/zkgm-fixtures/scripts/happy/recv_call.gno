// Recv-side probe for OP_CALL: with no Zkgmable receiver registered for the
// target contract path, executeCall short-circuits with callErrAck("receiver
// not registered: ..."). dispatchExecute commits a failure-tag Ack via
// WriteAck — the tx succeeds, proving the Call dispatch path runs end-to-end
// without crashing on a cold registry. To exercise the success branch,
// register a Zkgmable receiver via zkgm.RegisterReceiver from a dedicated
// realm and target its package path here.
package main

import (
	"chain/runtime"

	z "gno.land/p/gnoswap/ibc/zkgm"
	core "gno.land/r/core/ibc/v1/core"
	e2e "gno.land/r/gnoswap/ibc/v1/apps/zkgm/testing/e2e"
)

func main() {
	e2e.RegisterMockLightClient(cross)
	pair := e2e.OpenE2EChannelPair(cross)

	signer := runtime.OriginCaller().String()
	call := z.Call{
		Sender:           []byte(signer),
		Eureka:           false,
		ContractAddress:  []byte("unregistered-target"),
		ContractCalldata: []byte{0xCA, 0xFE},
	}
	packet := core.Packet{
		SourceChannelId:      pair.Source,
		DestinationChannelId: pair.Destination,
		Data:                 e2e.MustPacketData(cross, e2e.MustCallInstruction(cross, call)),
	}

	core.PacketRecv(cross, core.MsgPacketRecv{
		Packets:     []core.Packet{packet},
		ProofHeight: core.Height(1),
	})

	println("source_channel", pair.Source.String())
	println("destination_channel", pair.Destination.String())
	println("packet.Data.len", len(packet.Data))
}
