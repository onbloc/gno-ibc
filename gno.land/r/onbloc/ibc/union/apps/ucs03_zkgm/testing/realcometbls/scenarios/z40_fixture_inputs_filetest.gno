// PKGPATH: gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/testing/realcometbls/scenarios
package scenarios

import (
	"encoding/hex"

	z "gno.land/p/onbloc/ibc/zkgm"
	u256 "gno.land/p/gnoswap/uint256"
	core "gno.land/r/onbloc/ibc/union/core"
	e2e "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/testing/e2e"
)

const mockReceiverPath = "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/testing/mock"

func main(cur realm) {
	mixedPacket := z40MixedBatchPacket(cur)
	panicPacket := z40PanicBatchPacket(cur)
	mixedPacketKey := core.PacketCommitmentPath(mixedPacket)
	panicPacketKey := core.PacketCommitmentPath(panicPacket)
	packetValue := core.COMMITMENT_MAGIC

	printKV("mixed_batch_packet_commitment", mixedPacketKey[:], packetValue[:])
	printKV("panic_batch_packet_commitment", panicPacketKey[:], packetValue[:])
}

func z40MixedBatchPacket(cur realm) core.Packet {
	return z40BatchPacket(cur, z.Batch{Instructions: []z.Instruction{
		e2e.MustCallInstruction(cross(cur), z.Call{
			Sender:           []byte("sender"),
			ContractAddress:  []byte(mockReceiverPath),
			ContractCalldata: []byte("batch-call"),
		}),
		e2e.MustTokenOrderInstruction(cross(cur), z.TokenOrderV2{
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

func z40PanicBatchPacket(cur realm) core.Packet {
	return z40BatchPacket(cur, z.Batch{Instructions: []z.Instruction{
		e2e.MustCallInstruction(cross(cur), z.Call{
			Sender:           []byte("sender"),
			ContractAddress:  []byte(mockReceiverPath),
			ContractCalldata: []byte("panic-call"),
		}),
		e2e.MustTokenOrderInstruction(cross(cur), z.TokenOrderV2{
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

func z40BatchPacket(cur realm, batch z.Batch) core.Packet {
	return core.NewPacket(cross(cur), core.ChannelId(2), core.ChannelId(1), e2e.MustPacketData(cross(cur), e2e.MustBatchInstruction(cross(cur), batch)), 0, core.Timestamp(0))
}

func printKV(name string, key []byte, value []byte) {
	println(name+"_key", "0x"+hex.EncodeToString(key))
	println(name+"_value", "0x"+hex.EncodeToString(value))
}

// Output:
// mixed_batch_packet_commitment_key 0xdd374ceb5016bfb0edc44e88684c07621e1aeeaa95c885f084d75b54c4a6bf41
// mixed_batch_packet_commitment_value 0x0100000000000000000000000000000000000000000000000000000000000000
// panic_batch_packet_commitment_key 0x188c2ebc42b9ae5f6d2195ecc721c01dbb96906277e64a9492036fa2d73786d9
// panic_batch_packet_commitment_value 0x0100000000000000000000000000000000000000000000000000000000000000
