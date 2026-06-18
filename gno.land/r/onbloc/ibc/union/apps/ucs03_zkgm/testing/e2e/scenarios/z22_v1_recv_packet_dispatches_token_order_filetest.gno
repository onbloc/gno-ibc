// PKGPATH: gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/testing/e2e/scenarios
package scenarios

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
	packet := core.NewPacket(cross(cur), pair.Source, pair.Destination, e2e.MustPacketData(cross(cur), e2e.MustTokenOrderInstruction(cross(cur), order)), 0)

	core.PacketRecv(cross(cur), types.NewMsgPacketRecv([]types.Packet{packet}, [][]byte{nil}, address(""), nil, 1))

	println("quote_balance", impl.VoucherBalanceOf(quoteToken, address(receiver)))
	println("relayer_balance", impl.VoucherBalanceOf(quoteToken, cur.Address()))
}

// Output:
// quote_balance 21
// relayer_balance 79
