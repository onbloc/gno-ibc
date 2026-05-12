package main

import (
	"crypto/keccak256"
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
	mixedPacketKey := packetCommitmentPath(mixedPacket)
	panicPacketKey := packetCommitmentPath(panicPacket)
	packetValue := core.COMMITMENT_MAGIC

	printKV("mixed_batch_packet_commitment", mixedPacketKey[:], packetValue[:])
	printKV("panic_batch_packet_commitment", panicPacketKey[:], packetValue[:])
}

func z40MixedBatchPacket() core.Packet {
	return z40BatchPacket(core.Sequence(10), z.Batch{Instructions: []z.Instruction{
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
	return z40BatchPacket(core.Sequence(11), z.Batch{Instructions: []z.Instruction{
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

func z40BatchPacket(sequence core.Sequence, batch z.Batch) core.Packet {
	return core.NewPacket(
		cross,
		sequence,
		core.ChannelId(2),
		core.ChannelId(1),
		e2e.MustPacketData(cross, e2e.MustBatchInstruction(cross, batch)),
		core.Timestamp(0),
	)
}

func hash(bz []byte) [32]byte {
	return keccak256.Sum256(bz)
}

func packetCommitmentPath(packet core.Packet) [32]byte {
	batchHash := hash(packet.EthAbiEncode())
	return hash(concat(core.PACKETS[:], batchHash[:]))
}

func concat(parts ...[]byte) []byte {
	size := 0
	for _, p := range parts {
		size += len(p)
	}
	out := make([]byte, 0, size)
	for _, p := range parts {
		out = append(out, p...)
	}
	return out
}

func printKV(name string, key []byte, value []byte) {
	println(name+"_key", "0x"+hex.EncodeToString(key))
	println(name+"_value", "0x"+hex.EncodeToString(value))
}

// Output:
// mixed_batch_packet_commitment_key 0x642c27b2a9c2cbe440533099564bb5326041acfc25c5142322e3c453a50570c3
// mixed_batch_packet_commitment_value 0x0100000000000000000000000000000000000000000000000000000000000000
// panic_batch_packet_commitment_key 0x5650289645e1d5dc8de38e678c37ec8a608cc7befffed6d0b62359403da79567
// panic_batch_packet_commitment_value 0x0100000000000000000000000000000000000000000000000000000000000000
