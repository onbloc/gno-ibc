// PKGPATH: gno.land/r/onbloc/unionibc/v1/apps/zkgm/testing/e2e/scenarios_grc20
package scenarios_grc20

import (
	"gno.land/p/demo/tokens/grc20"
	u256 "gno.land/p/gnoswap/uint256"
	"gno.land/p/nt/testutils/v0"
	z "gno.land/p/onbloc/unionibc/zkgm"
	"gno.land/r/demo/defi/grc20reg"
	zkgm "gno.land/r/onbloc/unionibc/v1/apps/zkgm"
	e2e "gno.land/r/onbloc/unionibc/v1/apps/zkgm/testing/e2e"
	_ "gno.land/r/onbloc/unionibc/v1/apps/zkgm/testing/loader"
	core "gno.land/r/onbloc/unionibc/v1/core"
)

const pkgPath = "gno.land/r/onbloc/unionibc/v1/apps/zkgm/testing/e2e/scenarios_grc20"

func main(cur realm) {
	e2e.RegisterMockLightClient(cross(cur))
	pair := e2e.OpenE2EChannelPair(cross(cur))

	receiver := testutils.TestAddress("grc20-zero-receiver")
	tok, ledger := newToken(cur, "Zero Token", "ZERO")
	grc20reg.Register(cross(cur), tok, "zero")
	denom := pkgPath + ".zero"
	ledger.Mint(zkgm.ProxyAddress(), 7)

	order := z.TokenOrderV2{
		Receiver:    []byte(receiver.String()),
		BaseToken:   []byte("remote/base"),
		BaseAmount:  u256.Zero(),
		QuoteToken:  []byte(denom),
		QuoteAmount: u256.Zero(),
		Kind:        z.TOKEN_ORDER_KIND_UNESCROW,
	}
	packet := tokenOrderPacket(cross(cur), pair.Source, pair.Destination, order)

	core.PacketRecv(cross(cur), core.NewMsgPacketRecv(cross(cur), []core.Packet{packet}, nil, nil, core.Height(1)))

	println("receiver_balance", tok.BalanceOf(receiver))
	println("proxy_balance", tok.BalanceOf(zkgm.ProxyAddress()))
	println("ack_failure", core.AcknowledgementHash(cross(cur), packet).String() == failureAckHash())
}

func newToken(cur realm, name string, symbol string) (*grc20.Token, *grc20.PrivateLedger) {
	return grc20.NewToken(0, cur, name, symbol, 0)
}

func tokenOrderPacket(cur realm, source core.ChannelId, destination core.ChannelId, order z.TokenOrderV2) core.Packet {
	instr := e2e.MustTokenOrderInstruction(cross(cur), order)
	data := e2e.MustPacketData(cross(cur), instr)
	return core.NewPacket(cross(cur), source, destination, data, 0, core.Timestamp(1<<62))
}

func failureAckHash() string {
	ack, err := z.EncodeAck(z.Ack{Tag: u256.NewUint(0), InnerAck: []byte("UNIVERSAL_ERROR")})
	if err != nil {
		panic(err)
	}
	return core.CommitAcks([][]byte{ack}).String()
}

// Output:
// receiver_balance 0
// proxy_balance 7
// ack_failure true
