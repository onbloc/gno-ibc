// PKGPATH: gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/v1/main
package main

import (
	"gno.land/p/nt/testutils/v0"
	types "gno.land/p/onbloc/ibc/union/types"
	z "gno.land/p/onbloc/ibc/union/zkgm"
	u256 "gno.land/p/gnoswap/uint256"
	zkgm "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm"
	impl "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/v1"
)

func main(cur realm) {
	store := zkgm.NewStore()
	app := impl.NewUCS03ZkgmV1(store)
	destination := types.ChannelId(2)
	receiver := string(testutils.TestAddress("zs89-receiver"))
	bases := []string{"zs89-a", "zs89-b", "zs89-c", "zs89-d", "zs89-e", "zs89-f", "zs89-g", "zs89-h"}
	quoteTokens := make([]string, len(bases))
	instructions := make([]z.Instruction, len(bases))
	for i := 0; i < len(instructions); i++ {
		meta := mustZS89TokenMetadata(bases[i], "ZS89", 6)
		quoteTokens[i] = impl.PredictWrappedTokenV2(u256.Zero(), uint32(destination), []byte(bases[i]), impl.MetadataImage(mustZS89DecodeTokenMetadata(meta)))
		instructions[i] = mustZS89TokenOrderInstruction(z.TokenOrderV2{
			Sender:      []byte("sender"),
			Receiver:    []byte(receiver),
			BaseToken:   []byte(bases[i]),
			BaseAmount:  u256.NewUint(1),
			QuoteToken:  []byte(quoteTokens[i]),
			QuoteAmount: u256.NewUint(1),
			Kind:        z.TOKEN_ORDER_KIND_INITIALIZE,
			Metadata:    meta,
		})
	}

	println("[SCENARIO] flat allowlisted batch")
	largePacket := types.NewPacket(types.ChannelId(1), destination, mustZS89PacketData(mustZS89BatchInstruction(z.Batch{Instructions: instructions})), types.Timestamp(1<<62))
	largeResult := app.OnRecvPacket(0, cur, largePacket, testutils.TestAddress("zs89-relayer"), nil)
	largeAck, _ := z.DecodeAck(largeResult.Acknowledgement)
	largeBatchAck, _ := z.DecodeBatchAck(largeAck.InnerAck)
	println("large_batch_status", int(largeResult.Status))
	println("large_batch_ack_count", len(largeBatchAck.Acknowledgements))
	println("large_batch_minted_children", zs89MintedChildren(store, quoteTokens, address(receiver)))

	println("")
	println("[SCENARIO] nested batch child rejected by allowlist")
	nestedPacket := types.NewPacket(types.ChannelId(1), destination, mustZS89PacketData(mustZS89BatchInstruction(z.Batch{Instructions: []z.Instruction{
		mustZS89BatchInstruction(z.Batch{}),
	}})), types.Timestamp(1<<62))
	nestedResult := app.OnRecvPacket(0, cur, nestedPacket, testutils.TestAddress("zs89-relayer"), nil)
	nestedAck, _ := z.DecodeAck(nestedResult.Acknowledgement)
	println("nested_batch_status", int(nestedResult.Status))
	println("nested_batch_failure_ack", nestedAck.Tag.IsZero())
	println("minted_children_after_nested_batch", zs89MintedChildren(store, quoteTokens, address(receiver)))
}

func zs89MintedChildren(store *zkgm.Store, quoteTokens []string, receiver address) int {
	n := 0
	for _, quoteToken := range quoteTokens {
		voucher, ok := store.GetVoucher(quoteToken)
		if ok && voucher.Token().BalanceOf(receiver) == 1 {
			n++
		}
	}
	return n
}

func mustZS89TokenMetadata(name string, symbol string, decimals uint8) []byte {
	init, err := z.EncodeTokenInitializer(z.TokenInitializer{Name: name, Symbol: symbol, Decimals: decimals})
	if err != nil {
		panic(err)
	}
	meta, err := z.EncodeTokenMetadata(z.TokenMetadata{Implementation: []byte("grc20"), Initializer: init})
	if err != nil {
		panic(err)
	}
	return meta
}

func mustZS89DecodeTokenMetadata(bz []byte) z.TokenMetadata {
	meta, err := z.DecodeTokenMetadata(bz)
	if err != nil {
		panic(err)
	}
	return meta
}

func mustZS89TokenOrderInstruction(order z.TokenOrderV2) z.Instruction {
	bz, err := z.EncodeTokenOrderV2(order)
	if err != nil {
		panic(err)
	}
	return z.Instruction{Version: z.INSTR_VERSION_2, Opcode: z.OP_TOKEN_ORDER, Operand: bz}
}

func mustZS89BatchInstruction(batch z.Batch) z.Instruction {
	bz, err := z.EncodeBatch(batch)
	if err != nil {
		panic(err)
	}
	return z.Instruction{Version: z.INSTR_VERSION_0, Opcode: z.OP_BATCH, Operand: bz}
}

func mustZS89PacketData(instr z.Instruction) []byte {
	bz, err := z.EncodeZkgmPacket(z.ZkgmPacket{Path: u256.Zero(), Instruction: instr})
	if err != nil {
		panic(err)
	}
	return bz
}

// Output:
// [SCENARIO] flat allowlisted batch
// large_batch_status 1
// large_batch_ack_count 8
// large_batch_minted_children 8
//
// [SCENARIO] nested batch child rejected by allowlist
// nested_batch_status 2
// nested_batch_failure_ack true
// minted_children_after_nested_batch 8
