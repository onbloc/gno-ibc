// PKGPATH: gno.land/r/onbloc/unionibc/v1/apps/zkgm/testing/e2e/scenarios
package scenarios

import (
	z "gno.land/p/onbloc/ibc/zkgm"
	u256 "gno.land/p/gnoswap/uint256"
	"gno.land/p/nt/testutils/v0"
	core "gno.land/r/onbloc/unionibc/v1/core"
	e2e "gno.land/r/onbloc/unionibc/v1/apps/zkgm/testing/e2e"
	impl "gno.land/r/onbloc/unionibc/v1/apps/zkgm/v0/impl"
	_ "gno.land/r/onbloc/unionibc/v1/apps/zkgm/v0/loader"
)

func main(cur realm) {
	e2e.RegisterMockLightClient(cross(cur))
	pair := e2e.OpenE2EChannelPair(cross(cur))

	receiver := string(testutils.TestAddress("receiver"))
	quoteToken := impl.PredictWrappedTokenV1(u256.Zero(), uint32(pair.Destination), []byte("ugnot"))
	order := z.TokenOrderV2{
		Sender:      []byte("sender"),
		Receiver:    []byte(receiver),
		BaseToken:   []byte("ugnot"),
		BaseAmount:  u256.NewUint(100),
		QuoteToken:  []byte(quoteToken),
		QuoteAmount: u256.NewUint(21),
		Kind:        z.TOKEN_ORDER_KIND_ESCROW,
	}
	packet := core.NewPacket(cross(cur), pair.Source, pair.Destination, e2e.MustPacketData(cross(cur), e2e.MustTokenOrderInstruction(cross(cur), order)), 0, 0)

	core.PacketRecv(cross(cur), core.NewMsgPacketRecv(cross(cur), []core.Packet{packet}, nil, nil, core.Height(1)))

	println("quote_balance", impl.VoucherBalanceOf(quoteToken, address(receiver)))
	println("relayer_balance", impl.VoucherBalanceOf(quoteToken, cur.Address()))
}

// Output:
// quote_balance 21
// relayer_balance 79
