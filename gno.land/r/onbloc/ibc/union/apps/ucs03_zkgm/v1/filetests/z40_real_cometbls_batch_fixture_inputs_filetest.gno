// PKGPATH: gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/v1/main
package main

import (
	"encoding/hex"

	u256 "gno.land/p/gnoswap/uint256"
	types "gno.land/p/onbloc/ibc/union/types"
	z "gno.land/p/onbloc/ibc/union/zkgm"
)

const z40MockReceiverPath = "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/testing/mock"

func main() {
	mixedPacket := z40MixedBatchPacket()
	panicPacket := z40PanicBatchPacket()
	mixedPacketKey := types.MustCommit(types.PacketCommitmentPath(mixedPacket))
	panicPacketKey := types.MustCommit(types.PacketCommitmentPath(panicPacket))
	packetValue := types.COMMITMENT_MAGIC

	printZ40KV("mixed_batch_packet_commitment", mixedPacketKey[:], packetValue[:])
	printZ40KV("panic_batch_packet_commitment", panicPacketKey[:], packetValue[:])
}

func z40MixedBatchPacket() types.Packet {
	return z40BatchPacket(z.Batch{Instructions: []z.Instruction{
		mustZ40CallInstruction(z.Call{
			Sender:           []byte("sender"),
			ContractAddress:  []byte(z40MockReceiverPath),
			ContractCalldata: []byte("batch-call"),
		}),
		mustZ40TokenOrderInstruction(z.TokenOrderV2{
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

func z40PanicBatchPacket() types.Packet {
	return z40BatchPacket(z.Batch{Instructions: []z.Instruction{
		mustZ40CallInstruction(z.Call{
			Sender:           []byte("sender"),
			ContractAddress:  []byte(z40MockReceiverPath),
			ContractCalldata: []byte("panic-call"),
		}),
		mustZ40TokenOrderInstruction(z.TokenOrderV2{
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

func z40BatchPacket(batch z.Batch) types.Packet {
	return types.NewPacket(types.ChannelId(2), types.ChannelId(1), mustZ40PacketData(mustZ40BatchInstruction(batch)), types.Timestamp(0))
}

func mustZ40CallInstruction(call z.Call) z.Instruction {
	callBytes, err := z.EncodeCall(call)
	if err != nil {
		panic(err)
	}
	return z.Instruction{
		Version: z.INSTR_VERSION_0,
		Opcode:  z.OP_CALL,
		Operand: callBytes,
	}
}

func mustZ40TokenOrderInstruction(order z.TokenOrderV2) z.Instruction {
	orderBytes, err := z.EncodeTokenOrderV2(order)
	if err != nil {
		panic(err)
	}
	return z.Instruction{
		Version: z.INSTR_VERSION_2,
		Opcode:  z.OP_TOKEN_ORDER,
		Operand: orderBytes,
	}
}

func mustZ40BatchInstruction(batch z.Batch) z.Instruction {
	batchBytes, err := z.EncodeBatch(batch)
	if err != nil {
		panic(err)
	}
	return z.Instruction{
		Version: z.INSTR_VERSION_0,
		Opcode:  z.OP_BATCH,
		Operand: batchBytes,
	}
}

func mustZ40PacketData(instr z.Instruction) []byte {
	packetBytes, err := z.EncodeZkgmPacket(z.ZkgmPacket{
		Path:        u256.Zero(),
		Instruction: instr,
	})
	if err != nil {
		panic(err)
	}
	return packetBytes
}

func printZ40KV(name string, key []byte, value []byte) {
	println(name+"_key", "0x"+hex.EncodeToString(key))
	println(name+"_value", "0x"+hex.EncodeToString(value))
}

// Output:
// mixed_batch_packet_commitment_key 0x5b6d15280476ff21b8582b241254a08073cd68019a7021427aa49ed2e12ed028
// mixed_batch_packet_commitment_value 0x0100000000000000000000000000000000000000000000000000000000000000
// panic_batch_packet_commitment_key 0x40b8521a5f940a9da33617a71e52dcf702f56c7f070333b94f23f5014b272e4a
// panic_batch_packet_commitment_value 0x0100000000000000000000000000000000000000000000000000000000000000
