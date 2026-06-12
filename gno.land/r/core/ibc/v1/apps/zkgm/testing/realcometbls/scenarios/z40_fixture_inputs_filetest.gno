// PKGPATH: gno.land/r/onbloc/unionibc/v1/apps/zkgm/testing/realcometbls/scenarios
package scenarios

import (
	"encoding/hex"

	u256 "gno.land/p/gnoswap/uint256"

	z "gno.land/p/onbloc/unionibc/zkgm"

	"gno.land/r/onbloc/unionibc/v1/apps/zkgm/testing/e2e"
	"gno.land/r/onbloc/unionibc/v1/apps/zkgm/v0/impl"
	"gno.land/r/onbloc/unionibc/v1/core"
)

const mockReceiverPath = "gno.land/r/onbloc/unionibc/v1/apps/zkgm/testing/mock"

func main(cur realm) {
	mixedPacket := z40MixedBatchPacket(cur)
	panicPacket := z40PanicBatchPacket(cur)
	tokenFirstPanicPacket := z40TokenFirstPanicBatchPacket(cur)
	mixedPacketKey := core.PacketCommitmentPath(mixedPacket)
	panicPacketKey := core.PacketCommitmentPath(panicPacket)
	tokenFirstPanicPacketKey := core.PacketCommitmentPath(tokenFirstPanicPacket)
	packetValue := core.COMMITMENT_MAGIC

	println("[INFO] existing z40 packet commitment fixtures")
	printKV("mixed_batch_packet_commitment", mixedPacketKey[:], packetValue[:])
	printKV("panic_batch_packet_commitment", panicPacketKey[:], packetValue[:])

	println("")
	println("[INFO] token-first panic packet commitment fixture")
	printKV("token_first_panic_batch_packet_commitment", tokenFirstPanicPacketKey[:], packetValue[:])
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

func z40TokenFirstPanicBatchPacket(cur realm) core.Packet {
	// Use a valid predicted quote token so the token child mints before CALL panics.
	quoteToken := impl.PredictWrappedTokenV1(u256.Zero(), 1, []byte("ugnot"))
	return z40BatchPacket(cur, z.Batch{Instructions: []z.Instruction{
		e2e.MustTokenOrderInstruction(cross(cur), z.TokenOrderV2{
			Sender:      []byte("sender"),
			Receiver:    []byte("g1wymu47drhr0kuq2098m792lytgtj2nyx77yrsm"),
			BaseToken:   []byte("ugnot"),
			BaseAmount:  u256.NewUint(100),
			QuoteToken:  []byte(quoteToken),
			QuoteAmount: u256.NewUint(21),
			Kind:        z.TOKEN_ORDER_KIND_ESCROW,
		}),
		e2e.MustCallInstruction(cross(cur), z.Call{
			Sender:           []byte("sender"),
			ContractAddress:  []byte(mockReceiverPath),
			ContractCalldata: []byte("panic-call"),
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
// [INFO] existing z40 packet commitment fixtures
// mixed_batch_packet_commitment_key 0xdd374ceb5016bfb0edc44e88684c07621e1aeeaa95c885f084d75b54c4a6bf41
// mixed_batch_packet_commitment_value 0x0100000000000000000000000000000000000000000000000000000000000000
// panic_batch_packet_commitment_key 0x188c2ebc42b9ae5f6d2195ecc721c01dbb96906277e64a9492036fa2d73786d9
// panic_batch_packet_commitment_value 0x0100000000000000000000000000000000000000000000000000000000000000
//
// [INFO] token-first panic packet commitment fixture
// token_first_panic_batch_packet_commitment_key 0x881c5cad03a31e4ccda9e678cddbb6febcd493969a01e3116a534859f2370b7a
// token_first_panic_batch_packet_commitment_value 0x0100000000000000000000000000000000000000000000000000000000000000
