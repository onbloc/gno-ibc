// PKGPATH: gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/testing/e2e/scenarios_batchsend
package scenarios_batchsend

import (
	types "gno.land/p/onbloc/ibc/union/types"

	u256 "gno.land/p/gnoswap/uint256"
	"gno.land/p/nt/testutils/v0"
	z "gno.land/p/onbloc/ibc/union/zkgm"
	e2e "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/testing/e2e"
	impl "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/v1"
	core "gno.land/r/onbloc/ibc/union/core"
)

func main(cur realm) {
	impl.Register(cross(cur))
	e2e.RegisterMockLightClient(cross(cur))
	pair := e2e.OpenE2EChannelPair(cross(cur))

	receiver := string(testutils.TestAddress("zs89-receiver"))
	// Regression slot for the current behavior: flat batches have no length cap.
	bases := []string{"zs89-a", "zs89-b", "zs89-c", "zs89-d", "zs89-e", "zs89-f", "zs89-g", "zs89-h"}
	quoteTokens := make([]string, len(bases))
	instructions := make([]z.Instruction, len(bases))
	for i := 0; i < len(instructions); i++ {
		metaBytes := e2e.MustTokenMetadata(cross(cur), "grc20", z.TokenInitializer{Name: bases[i], Symbol: "ZS89", Decimals: 6})
		quoteTokens[i] = z.PredictWrappedTokenV2(u256.Zero(), uint32(pair.Destination), []byte(bases[i]), z.MetadataImage(mustDecodeZS89TokenMetadata(metaBytes)))
		instructions[i] = e2e.MustTokenOrderInstruction(cross(cur), z.TokenOrderV2{
			Sender:      []byte("sender"),
			Receiver:    []byte(receiver),
			BaseToken:   []byte(bases[i]),
			BaseAmount:  u256.NewUint(1),
			QuoteToken:  []byte(quoteTokens[i]),
			QuoteAmount: u256.NewUint(1),
			Kind:        z.TOKEN_ORDER_KIND_INITIALIZE,
			Metadata:    metaBytes,
		})
	}
	largeBatch := z.Batch{Instructions: instructions}
	largePacket := core.NewPacket(pair.Source, pair.Destination,
		e2e.MustPacketData(cross(cur), e2e.MustBatchInstruction(cross(cur), largeBatch)), types.Timestamp(1<<62))

	println("[SCENARIO] flat allowlisted batch")
	core.PacketRecv(cross(cur), types.NewMsgPacketRecv([]types.Packet{largePacket}, [][]byte{nil}, nil, 1))
	println("large_batch_receipt", core.HasPacketReceipt(cross(cur), largePacket))
	println("large_batch_success_ack", core.AcknowledgementHash(cross(cur), largePacket).String() == zs89BatchSuccessAckHash(cross(cur), len(instructions)))
	println("large_batch_minted_children", zs89MintedChildren(quoteTokens, address(receiver)))

	println("")
	println("[SCENARIO] nested batch child rejected by allowlist")
	nestedBatch := z.Batch{Instructions: []z.Instruction{
		e2e.MustBatchInstruction(cross(cur), z.Batch{}),
	}}
	nestedPacket := core.NewPacket(pair.Source, pair.Destination,
		e2e.MustPacketData(cross(cur), e2e.MustBatchInstruction(cross(cur), nestedBatch)), types.Timestamp(1<<62))
	core.PacketRecv(cross(cur), types.NewMsgPacketRecv([]types.Packet{nestedPacket}, [][]byte{nil}, nil, 1))
	println("nested_batch_receipt", core.HasPacketReceipt(cross(cur), nestedPacket))
	println("nested_batch_failure_ack", core.AcknowledgementHash(cross(cur), nestedPacket).String() == zs89FailureAckHash())
	println("minted_children_after_nested_batch", zs89MintedChildren(quoteTokens, address(receiver)))
}

func zs89MintedChildren(quoteTokens []string, receiver address) int {
	n := 0
	for _, quoteToken := range quoteTokens {
		if impl.VoucherBalanceOf(quoteToken, receiver) == 1 {
			n++
		}
	}
	return n
}

func mustDecodeZS89TokenMetadata(bz []byte) z.TokenMetadata {
	meta, err := z.DecodeTokenMetadata(bz)
	if err != nil {
		panic(err)
	}
	return meta
}

func zs89BatchSuccessAckHash(cur realm, count int) string {
	childAcks := make([][]byte, count)
	for i := 0; i < count; i++ {
		childAcks[i] = e2e.MustSuccessAck(cross(cur), e2e.MustProtocolTokenOrderAck(cross(cur)))
	}
	return types.CommitAcks([][]byte{e2e.MustBatchAck(cross(cur), childAcks)}).String()
}

func zs89FailureAckHash() string {
	ack, err := z.EncodeAck(z.Ack{Tag: u256.NewUint(0), InnerAck: []byte("UNIVERSAL_ERROR")})
	if err != nil {
		panic(err)
	}
	return types.CommitAcks([][]byte{ack}).String()
}

// Output:
// [SCENARIO] flat allowlisted batch
// large_batch_receipt true
// large_batch_success_ack true
// large_batch_minted_children 8
//
// [SCENARIO] nested batch child rejected by allowlist
// nested_batch_receipt true
// nested_batch_failure_ack true
// minted_children_after_nested_batch 8
