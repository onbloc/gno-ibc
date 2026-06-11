// PKGPATH: gno.land/r/onbloc/unionibc/v1/apps/zkgm/testing/e2e/scenarios_grc20
package scenarios_grc20

import (
	stdtesting "testing"

	"gno.land/p/demo/tokens/grc20"
	u256 "gno.land/p/gnoswap/uint256"
	"gno.land/p/nt/testutils/v0"
	z "gno.land/p/onbloc/unionibc/zkgm"
	"gno.land/r/demo/defi/grc20reg"
	zkgm "gno.land/r/onbloc/unionibc/v1/apps/zkgm"
	e2e "gno.land/r/onbloc/unionibc/v1/apps/zkgm/testing/e2e"
	_ "gno.land/r/onbloc/unionibc/v1/apps/zkgm/testing/loader"
	impl "gno.land/r/onbloc/unionibc/v1/apps/zkgm/v0/impl"
	core "gno.land/r/onbloc/unionibc/v1/core"
)

const pkgPath = "gno.land/r/onbloc/unionibc/v1/apps/zkgm/testing/e2e/scenarios_grc20"

func main(cur realm) {
	e2e.RegisterMockLightClient(cross(cur))
	pair := e2e.OpenE2EChannelPair(cross(cur))

	sender := testutils.TestAddress("grc20-ack-refund")
	tok, ledger := newToken(cur, "Ack Refund Token", "ART")
	grc20reg.Register(cross(cur), tok, "ack_refund")
	denom := pkgPath + ".ack_refund"
	ledger.Mint(sender, 20)
	ledger.Approve(sender, zkgm.ProxyAddress(), 13)

	order := z.TokenOrderV2{
		Sender:      []byte(sender.String()),
		BaseToken:   []byte(denom),
		BaseAmount:  u256.NewUint(13),
		QuoteToken:  []byte("remote/quote"),
		QuoteAmount: u256.NewUint(13),
		Kind:        z.TOKEN_ORDER_KIND_ESCROW,
	}
	stdtesting.SetRealm(stdtesting.NewUserRealm(sender))
	packet := zkgm.Send(cross(cur), pair.Source, core.Timestamp(1<<62), [32]byte{}, e2e.MustTokenOrderInstruction(cross(cur), order))
	stdtesting.SetRealm(stdtesting.NewCodeRealm(pkgPath))

	ack := e2e.MustAck(cross(cur), u256.NewUint(0), []byte("UNIVERSAL_ERROR"))
	core.PacketAcknowledgement(cross(cur), core.NewMsgPacketAcknowledgement(cross(cur), []core.Packet{packet}, [][]byte{ack}, nil, core.Height(1)))

	println("sender_balance", tok.BalanceOf(sender))
	println("proxy_balance", tok.BalanceOf(zkgm.ProxyAddress()))
	println("channel_balance", channelBalanceString(pair.Source, order.BaseToken, order.QuoteToken))
	println("commitment_after_ack", core.HasPacketCommitment(cross(cur), packet))
}

func newToken(cur realm, name string, symbol string) (*grc20.Token, *grc20.PrivateLedger) {
	return grc20.NewToken(0, cur, name, symbol, 0)
}

func channelBalanceString(channelId core.ChannelId, baseToken []byte, quoteToken []byte) string {
	balance := zkgm.GetChannelBalanceV2(impl.ChannelBalanceKeyV2(channelId, u256.Zero(), baseToken, quoteToken))
	if balance == nil {
		return "0"
	}
	return balance.ToString()
}

// Output:
// sender_balance 20
// proxy_balance 0
// channel_balance 0
// commitment_after_ack false
