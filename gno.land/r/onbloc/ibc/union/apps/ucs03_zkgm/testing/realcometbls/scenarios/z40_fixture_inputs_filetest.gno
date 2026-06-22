// PKGPATH: gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/testing/realcometbls/scenarios
package scenarios

import (
	"encoding/hex"

	types "gno.land/p/onbloc/ibc/union/types"

	u256 "gno.land/p/gnoswap/uint256"
	z "gno.land/p/onbloc/ibc/union/zkgm"
	core "gno.land/r/onbloc/ibc/union/core"
)

const mockReceiverPath = "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/testing/mock"

func main(cur realm) {
	mixedPacket := z40MixedBatchPacket(cur)
	panicPacket := z40PanicBatchPacket(cur)
	mixedPacketKey := types.MustCommit(types.PacketCommitmentPath(mixedPacket))
	panicPacketKey := types.MustCommit(types.PacketCommitmentPath(panicPacket))
	packetValue := types.COMMITMENT_MAGIC

	printKV("mixed_batch_packet_commitment", mixedPacketKey[:], packetValue[:])
	printKV("panic_batch_packet_commitment", panicPacketKey[:], packetValue[:])
}

func z40MixedBatchPacket(cur realm) types.Packet {
	return z40BatchPacket(cur, z.Batch{Instructions: []z.Instruction{
		mustRealcometCallInstruction(z.Call{
			Sender:           []byte("sender"),
			ContractAddress:  []byte(mockReceiverPath),
			ContractCalldata: []byte("batch-call"),
		}),
		mustRealcometTokenOrderInstruction(z.TokenOrderV2{
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

func z40PanicBatchPacket(cur realm) types.Packet {
	return z40BatchPacket(cur, z.Batch{Instructions: []z.Instruction{
		mustRealcometCallInstruction(z.Call{
			Sender:           []byte("sender"),
			ContractAddress:  []byte(mockReceiverPath),
			ContractCalldata: []byte("panic-call"),
		}),
		mustRealcometTokenOrderInstruction(z.TokenOrderV2{
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

func z40BatchPacket(cur realm, batch z.Batch) types.Packet {
	return core.NewPacket(types.ChannelId(2), types.ChannelId(1), mustRealcometZkgmPacketData(mustRealcometBatchInstruction(batch)), types.Timestamp(0))
}

func mustRealcometCallInstruction(call z.Call) z.Instruction {
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

func mustRealcometTokenOrderInstruction(order z.TokenOrderV2) z.Instruction {
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

func mustRealcometBatchInstruction(batch z.Batch) z.Instruction {
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

func mustRealcometZkgmPacketData(instr z.Instruction) []byte {
	packetBytes, err := z.EncodeZkgmPacket(z.ZkgmPacket{
		Path:        u256.Zero(),
		Instruction: instr,
	})
	if err != nil {
		panic(err)
	}
	return packetBytes
}

func printKV(name string, key []byte, value []byte) {
	println(name+"_key", "0x"+hex.EncodeToString(key))
	println(name+"_value", "0x"+hex.EncodeToString(value))
}

// Output:
// mixed_batch_packet_commitment_key 0x5b6d15280476ff21b8582b241254a08073cd68019a7021427aa49ed2e12ed028
// mixed_batch_packet_commitment_value 0x0100000000000000000000000000000000000000000000000000000000000000
// panic_batch_packet_commitment_key 0x40b8521a5f940a9da33617a71e52dcf702f56c7f070333b94f23f5014b272e4a
// panic_batch_packet_commitment_value 0x0100000000000000000000000000000000000000000000000000000000000000
