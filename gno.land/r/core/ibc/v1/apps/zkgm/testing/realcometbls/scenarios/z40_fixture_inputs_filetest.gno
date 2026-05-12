package main

import (
	"encoding/hex"

	z "gno.land/p/gnoswap/ibc/zkgm"
	u256 "gno.land/p/gnoswap/uint256"
	core "gno.land/r/core/ibc/v1/core"
	e2e "gno.land/r/gnoswap/ibc/v1/apps/zkgm/testing/e2e"
)

const mockReceiverPath = "gno.land/r/gnoswap/ibc/v1/apps/zkgm/testing/mock"

func main() {
	mixedPacket := z40MixedBatchPacket()
	panicPacket := z40PanicBatchPacket()
	mixedPacketKey := core.PacketCommitmentPath(mixedPacket)
	panicPacketKey := core.PacketCommitmentPath(panicPacket)
	packetValue := core.COMMITMENT_MAGIC

	printKV("mixed_batch_packet_commitment", mixedPacketKey[:], packetValue[:])
	printKV("panic_batch_packet_commitment", panicPacketKey[:], packetValue[:])
}

func z40MixedBatchPacket() core.Packet {
	return z40BatchPacket(z.Batch{Instructions: []z.Instruction{
		e2e.MustCallInstruction(cross, z.Call{
			Sender:           []byte("sender"),
			ContractAddress:  []byte(mockReceiverPath),
			ContractCalldata: []byte("batch-call"),
		}),
		e2e.MustTokenOrderInstruction(cross, z.TokenOrderV2{
			Sender:      []byte("sender"),
			Receiver:    []byte("g1wymu47drhr0kuq2098m792lytgtj2nyx77yrsm"),
			BaseToken:   []byte("ugnot"),
			BaseAmount:  u256.NewUint(100),
			QuoteToken:  []byte("ibc/batch-quote"),
			QuoteAmount: u256.NewUint(21),
			Kind:        z.TOKEN_ORDER_KIND_ESCROW,
		}),
	}})
}

func z40PanicBatchPacket() core.Packet {
	return z40BatchPacket(z.Batch{Instructions: []z.Instruction{
		e2e.MustCallInstruction(cross, z.Call{
			Sender:           []byte("sender"),
			ContractAddress:  []byte(mockReceiverPath),
			ContractCalldata: []byte("panic-call"),
		}),
		e2e.MustTokenOrderInstruction(cross, z.TokenOrderV2{
			Sender:      []byte("sender"),
			Receiver:    []byte("g1wymu47drhr0kuq2098m792lytgtj2nyx77yrsm"),
			BaseToken:   []byte("ugnot"),
			BaseAmount:  u256.NewUint(100),
			QuoteToken:  []byte("ibc/batch-panic-quote"),
			QuoteAmount: u256.NewUint(21),
			Kind:        z.TOKEN_ORDER_KIND_ESCROW,
		}),
	}})
}

func z40BatchPacket(batch z.Batch) core.Packet {
	return core.Packet{
		SourceChannelId:      core.ChannelId(2),
		DestinationChannelId: core.ChannelId(1),
		Data:                 e2e.MustPacketData(cross, e2e.MustBatchInstruction(cross, batch)),
		TimeoutTimestamp:     core.Timestamp(0),
	}
}

func printKV(name string, key []byte, value []byte) {
	println(name+"_key", "0x"+hex.EncodeToString(key))
	println(name+"_value", "0x"+hex.EncodeToString(value))
}

// Output:
// mixed_batch_packet_commitment_key 0xa27e1b52c3beaeb1c4b3c6afb3bb6000536eb98562c019f0109f7b1274a3d102
// mixed_batch_packet_commitment_value 0x0100000000000000000000000000000000000000000000000000000000000000
// panic_batch_packet_commitment_key 0x9102811e2a4d94c7593e8711e65c4163820045992a2ab08e771615a067ca23cd
// panic_batch_packet_commitment_value 0x0100000000000000000000000000000000000000000000000000000000000000
