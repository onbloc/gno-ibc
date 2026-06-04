// PKGPATH: gno.land/r/onbloc/ibc/v1/apps/zkgm/testing/realcometbls/scenarios
package scenarios

import (
	"encoding/hex"

	z "gno.land/p/onbloc/ibc/zkgm"
	u256 "gno.land/p/gnoswap/uint256"
	core "gno.land/r/core/ibc/v1/core"
	e2e "gno.land/r/onbloc/ibc/v1/apps/zkgm/testing/e2e"
)

const mockReceiverPath = "gno.land/r/onbloc/ibc/v1/apps/zkgm/testing/mock"

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
// mixed_batch_packet_commitment_key 0x8cfda3c16919b3e2624c76ed112b65a2bdf66c9558d881cd267d5ddfc9d46530
// mixed_batch_packet_commitment_value 0x0100000000000000000000000000000000000000000000000000000000000000
// panic_batch_packet_commitment_key 0xe211a9dd587bf368686ec948ddff276afb804ed557f1eef352a0bf0d9ae861e8
// panic_batch_packet_commitment_value 0x0100000000000000000000000000000000000000000000000000000000000000
