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

	sender := testutils.TestAddress("grc20-pin-sender")
	receiver := testutils.TestAddress("grc20-pin-receiver")
	tokA, ledgerA := newToken(cur, "Pinned Token", "PIN")
	grc20reg.Register(cross(cur), tokA, "pin")
	denom := pkgPath + ".pin"
	ledgerA.Mint(sender, 10)
	ledgerA.Approve(sender, zkgm.ProxyAddress(), 10)
	zkgm.EscrowGRC20(cross(cur), denom, sender, 10)

	tokB, ledgerB := newToken(cur, "Replacement Token", "RPL")
	ledgerB.Mint(zkgm.ProxyAddress(), 100)
	grc20reg.Register(cross(cur), tokB, "pin")

	order := z.TokenOrderV2{
		Receiver:    []byte(receiver.String()),
		BaseToken:   []byte("remote/base"),
		BaseAmount:  u256.NewUint(10),
		QuoteToken:  []byte(denom),
		QuoteAmount: u256.NewUint(10),
		Kind:        z.TOKEN_ORDER_KIND_UNESCROW,
	}
	setChannelBalance(cross(cur), pair.Destination, order.QuoteToken, order.BaseToken, order.BaseAmount)
	packet := tokenOrderPacket(cross(cur), pair.Source, pair.Destination, order)

	core.PacketRecv(cross(cur), core.NewMsgPacketRecv(cross(cur), []core.Packet{packet}, nil, nil, core.Height(1)))

	println("token_a_proxy", tokA.BalanceOf(zkgm.ProxyAddress()))
	println("token_a_receiver", tokA.BalanceOf(receiver))
	println("token_b_proxy", tokB.BalanceOf(zkgm.ProxyAddress()))
	println("token_b_receiver", tokB.BalanceOf(receiver))
	println("channel_balance", channelBalanceString(pair.Destination, order.QuoteToken, order.BaseToken))
	println("ack_success", core.AcknowledgementHash(cross(cur), packet).String() == successAckHash(cross(cur)))
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

func successAckHash(cur realm) string {
	ack := e2e.MustSuccessAck(cross(cur), e2e.MustProtocolTokenOrderAck(cross(cur)))
	return core.CommitAcks([][]byte{ack}).String()
}

// Output:
// token_a_proxy 0
// token_a_receiver 10
// token_b_proxy 100
// token_b_receiver 0
// channel_balance 0
// ack_success true
