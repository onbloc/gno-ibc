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

func main(cur realm) {
	e2e.RegisterMockLightClient(cross(cur))
	pair := e2e.OpenE2EChannelPair(cross(cur))

	sender := testutils.TestAddress("grc20-send-escrow")
	tok, ledger := grc20.NewToken(0, cur, "Send Escrow Token", "SET", 0)
	grc20reg.Register(cross(cur), tok, "send_escrow")
	denom := "gno.land/r/onbloc/unionibc/v1/apps/zkgm/testing/e2e/scenarios_grc20.send_escrow"
	ledger.Mint(sender, 20)
	ledger.Approve(sender, zkgm.ProxyAddress(), 9)

	order := z.TokenOrderV2{
		Sender:      []byte(sender.String()),
		BaseToken:   []byte(denom),
		BaseAmount:  u256.NewUint(9),
		QuoteToken:  []byte("remote/quote"),
		QuoteAmount: u256.NewUint(9),
		Kind:        z.TOKEN_ORDER_KIND_ESCROW,
	}
	stdtesting.SetRealm(stdtesting.NewUserRealm(sender))
	zkgm.Send(cross(cur), pair.Source, core.Timestamp(1<<62), [32]byte{}, e2e.MustTokenOrderInstruction(cross(cur), order))

	println("sender_balance", tok.BalanceOf(sender))
	println("proxy_balance", tok.BalanceOf(zkgm.ProxyAddress()))
	println("channel_balance", channelBalanceString(pair.Source, order.BaseToken, order.QuoteToken))
}

func channelBalanceString(channelId core.ChannelId, baseToken []byte, quoteToken []byte) string {
	balance := zkgm.GetChannelBalanceV2(impl.ChannelBalanceKeyV2(channelId, u256.Zero(), baseToken, quoteToken))
	if balance == nil {
		return "0"
	}
	return balance.ToString()
}

// Output:
// sender_balance 11
// proxy_balance 9
// channel_balance 9
