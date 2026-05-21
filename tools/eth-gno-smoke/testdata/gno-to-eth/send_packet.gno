package main

import (
	"chain/runtime"
	"encoding/hex"

	z "gno.land/p/gnoswap/ibc/zkgm"
	core "gno.land/r/core/ibc/v1/core"
	zkgm "gno.land/r/gnoswap/ibc/v1/apps/zkgm"
	e2e "gno.land/r/gnoswap/ibc/v1/apps/zkgm/testing/e2e"
	_ "gno.land/r/gnoswap/ibc/v1/apps/zkgm/v0/loader"
)

func main() {
	e2e.RegisterMockLightClient(cross)
	pair := e2e.OpenE2EChannelPair(cross)

	sender := runtime.OriginCaller().String()
	callBytes, err := z.EncodeCall(z.Call{
		Sender:          []byte(sender),
		ContractAddress: []byte("gno.land/r/gnoswap/ibc/v1/apps/zkgm/testing/mock"),
	})
	if err != nil {
		panic(err)
	}

	var salt [32]byte
	timeout := core.Timestamp(1 << 60)
	packet := zkgm.Send(cross, pair.Source, timeout, salt, z.Instruction{
		Version: z.INSTR_VERSION_0,
		Opcode:  z.OP_CALL,
		Operand: callBytes,
	})

	batchHash := core.CommitPackets([]core.Packet{packet})
	batchPath := core.BatchPacketsPath(batchHash)

	println("source_channel_id", packet.SourceChannelId.String())
	println("destination_channel_id", packet.DestinationChannelId.String())
	println("packet_data_hex", "0x"+hex.EncodeToString(packet.Data))
	println("timeout_timestamp", packet.TimeoutTimestamp.String())
	println("packet_hash", core.CommitPacket(packet).String())
	println("batch_hash", batchHash.String())
	println("batch_path_hex", batchPath.String())
	println("commitment_value_hex", core.QueryCommitmentAtPath(batchPath))
}
