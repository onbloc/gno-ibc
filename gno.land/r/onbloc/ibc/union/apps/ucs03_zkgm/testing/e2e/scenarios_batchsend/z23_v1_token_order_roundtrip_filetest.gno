// PKGPATH: gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/testing/e2e/scenarios_batchsend
package scenarios_batchsend

import (
	types "gno.land/p/onbloc/ibc/union/types"

	u256 "gno.land/p/gnoswap/uint256"
	z "gno.land/p/onbloc/ibc/union/zkgm"
	e2e "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/testing/e2e"
	impl "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/v1"
	core "gno.land/r/onbloc/ibc/union/core"
)

func main(cur realm) {
	impl.Register(cross(cur))
	e2e.RegisterMockLightClient(cross(cur))
	pair := e2e.OpenE2EChannelPair(cross(cur))

	sender := "g17xpfvakm2amg962yls6f84z3kell8c5lserqta"
	receiver := "g1wymu47drhr0kuq2098m792lytgtj2nyx77yrsm"
	metaBytes := e2e.MustTokenMetadata(cross(cur), "grc20", z.TokenInitializer{Name: "Gno Token", Symbol: "GNOT", Decimals: 6})
	quoteToken := impl.PredictWrappedTokenV2(u256.Zero(), uint32(pair.Destination), []byte("ugnot"), impl.MetadataImage(mustDecodeTokenMetadata(metaBytes)))
	order := z.TokenOrderV2{
		Sender:      []byte(sender),
		Receiver:    []byte(receiver),
		BaseToken:   []byte("ugnot"),
		BaseAmount:  u256.NewUint(33),
		QuoteToken:  []byte(quoteToken),
		QuoteAmount: u256.NewUint(33),
		Kind:        z.TOKEN_ORDER_KIND_INITIALIZE,
		Metadata:    metaBytes,
	}
	instr := e2e.MustTokenOrderInstruction(cross(cur), order)
	packet := core.NewPacket(cross(cur), pair.Source, pair.Destination, e2e.MustPacketData(cross(cur), instr), types.Timestamp(1<<62))
	e2e.BatchSend(cross(cur), packet)

	core.PacketRecv(cross(cur), types.NewMsgPacketRecv([]types.Packet{packet}, [][]byte{nil}, address(""), nil, 1))

	ack := e2e.MustSuccessAck(cross(cur), e2e.MustProtocolTokenOrderAck(cross(cur)))
	core.PacketAcknowledgement(cross(cur), types.NewMsgPacketAcknowledgement([]types.Packet{packet}, [][]byte{ack}, nil, 1, address("")))

	println("quote_balance", impl.VoucherBalanceOf(impl.PredictWrappedTokenV2(u256.Zero(), uint32(pair.Destination), order.BaseToken, impl.MetadataImage(mustDecodeTokenMetadata(order.Metadata))), address(receiver)))
	println("ack_roundtrip", "ok")
}

func mustDecodeTokenMetadata(bz []byte) z.TokenMetadata {
	meta, err := z.DecodeTokenMetadata(bz)
	if err != nil {
		panic(err)
	}
	return meta
}

// Output:
// quote_balance 33
// ack_roundtrip ok
