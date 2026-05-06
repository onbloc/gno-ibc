package main

import (
	"gno.land/p/aib/ibc/types"
	z "gno.land/p/gnoswap/ibc/zkgm"
	u256 "gno.land/p/gnoswap/uint256"
	zkgm "gno.land/r/gnoswap/ibc/apps/zkgm"
	impl "gno.land/r/gnoswap/ibc/apps/zkgm/v0/impl"
	_ "gno.land/r/gnoswap/ibc/apps/zkgm/v0/loader"
)

func main() {
	receiver := "g1wymu47drhr0kuq2098m792lytgtj2nyx77yrsm"
	metaBytes := mustEncodeTokenMetadata(z.TokenMetadata{
		Implementation: []byte("grc20"),
		Initializer:    []byte("init"),
	})
	order := z.TokenOrderV2{
		Sender:      []byte("counterparty-sender"),
		Receiver:    []byte(receiver),
		BaseToken:   []byte("ugnot"),
		BaseAmount:  u256.NewUint(100),
		QuoteToken:  []byte("uatom"),
		QuoteAmount: u256.NewUint(95),
		Kind:        z.TOKEN_ORDER_KIND_INITIALIZE,
		Metadata:    metaBytes,
	}

	res := zkgm.AsIBCApp().OnRecvPacket(cross, "client-a", "client-b", 1, mustTokenOrderPayload(order))
	ack, err := z.DecodeAck(res.Acknowledgement)
	if err != nil {
		panic(err)
	}
	orderAck, err := z.DecodeTokenOrderAck(ack.InnerAck)
	if err != nil {
		panic(err)
	}
	image := impl.MetadataImage(mustDecodeTokenMetadata(metaBytes))
	ibcDenom := impl.PredictWrappedTokenV2("client-b", order.BaseToken, image)
	origin, hasOrigin := zkgm.GetTokenOrigin(ibcDenom)
	_, hasImage := zkgm.GetMetadataImageOf(ibcDenom)

	println("status", int(res.Status))
	println("ack_tag", ack.Tag.Dec())
	println("fill_type", orderAck.FillType.Dec())
	println("voucher_balance", impl.VoucherBalanceOf(ibcDenom, address(receiver)))
	println("has_origin", hasOrigin)
	println("origin_path", origin.Dec())
	println("has_metadata_image", hasImage)
}

func mustTokenOrderPayload(order z.TokenOrderV2) types.Payload {
	orderBytes, err := z.EncodeTokenOrderV2(order)
	if err != nil {
		panic(err)
	}
	packetBytes, err := z.EncodeZkgmPacket(z.ZkgmPacket{
		Path: u256.NewUint(7),
		Instruction: z.Instruction{
			Version: z.INSTR_VERSION_2,
			Opcode:  z.OP_TOKEN_ORDER,
			Operand: orderBytes,
		},
	})
	if err != nil {
		panic(err)
	}
	return types.Payload{Value: packetBytes}
}

func mustEncodeTokenMetadata(meta z.TokenMetadata) []byte {
	bz, err := z.EncodeTokenMetadata(meta)
	if err != nil {
		panic(err)
	}
	return bz
}

func mustDecodeTokenMetadata(bz []byte) z.TokenMetadata {
	meta, err := z.DecodeTokenMetadata(bz)
	if err != nil {
		panic(err)
	}
	return meta
}

// Output:
// status 1
// ack_tag 1
// fill_type 11586256
// voucher_balance 95
// has_origin true
// origin_path 7
// has_metadata_image true
