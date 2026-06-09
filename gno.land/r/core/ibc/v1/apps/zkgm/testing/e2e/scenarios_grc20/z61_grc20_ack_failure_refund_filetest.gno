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
	zkgm.EscrowGRC20(cross(cur), denom, sender, 13)

	order := z.TokenOrderV2{
		Sender:      []byte(sender.String()),
		BaseToken:   []byte(denom),
		BaseAmount:  u256.NewUint(13),
		QuoteToken:  []byte("remote/quote"),
		QuoteAmount: u256.NewUint(13),
		Kind:        z.TOKEN_ORDER_KIND_ESCROW,
	}
	setChannelBalance(cross(cur), pair.Source, order.BaseToken, order.QuoteToken, order.BaseAmount)
	packet := tokenOrderPacket(cross(cur), pair.Source, pair.Destination, order)
	e2e.BatchSend(cross(cur), packet)

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

func tokenOrderPacket(cur realm, source core.ChannelId, destination core.ChannelId, order z.TokenOrderV2) core.Packet {
	instr := e2e.MustTokenOrderInstruction(cross(cur), order)
	data := e2e.MustPacketData(cross(cur), instr)
	return core.NewPacket(cross(cur), source, destination, data, 0, core.Timestamp(1<<62))
}

func setChannelBalance(cur realm, channelId core.ChannelId, baseToken []byte, quoteToken []byte, amount *u256.Uint) {
	zkgm.SetChannelBalanceV2(cross(cur), impl.ChannelBalanceKeyV2(channelId, u256.Zero(), baseToken, quoteToken), amount)
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
