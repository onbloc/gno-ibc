// PKGPATH: gno.land/r/onbloc/unionibc/v1/apps/zkgm/testing/e2e/scenarios_grc20
package scenarios_grc20

import (
	stdtesting "testing"

	"gno.land/p/demo/tokens/grc20"
	"gno.land/p/nt/testutils/v0"

	u256 "gno.land/p/gnoswap/uint256"
	"gno.land/r/demo/defi/grc20reg"

	z "gno.land/p/onbloc/unionibc/zkgm"
	"gno.land/r/onbloc/unionibc/v1/apps/zkgm"

	"gno.land/r/onbloc/unionibc/v1/apps/zkgm/testing/e2e"
	"gno.land/r/onbloc/unionibc/v1/apps/zkgm/v0/impl"
	"gno.land/r/onbloc/unionibc/v1/core"

	_ "gno.land/r/onbloc/unionibc/v1/apps/zkgm/testing/loader"
)

const pkgPath = "gno.land/r/onbloc/unionibc/v1/apps/zkgm/testing/e2e/scenarios_grc20"

func main(cur realm) {
	e2e.RegisterMockLightClient(cross(cur))
	pair := e2e.OpenE2EChannelPair(cross(cur))

	sender := testutils.TestAddress("g20-unescrow-send")
	receiver := testutils.TestAddress("g20-unescrow-recv")
	relayer := testutils.TestAddress("g20-unescrow-relay")
	tok, ledger := newToken(cur, "Unescrow Token", "UET")
	grc20reg.Register(cross(cur), tok, "unescrow_recv")
	denom := pkgPath + ".unescrow_recv"
	ledger.Mint(sender, 20)
	ledger.Approve(sender, zkgm.ProxyAddress(), 20)

	escrowOrder := z.TokenOrderV2{
		Sender:      []byte(sender.String()),
		BaseToken:   []byte(denom),
		BaseAmount:  u256.NewUint(20),
		QuoteToken:  []byte("remote/base"),
		QuoteAmount: u256.NewUint(20),
		Kind:        z.TOKEN_ORDER_KIND_ESCROW,
	}
	println("[INFO] before send local GRC20 is held by sender")
	println("sender_before_send", tok.BalanceOf(sender))
	println("proxy_before_send", tok.BalanceOf(zkgm.ProxyAddress()))
	println("channel_before_send", channelBalanceString(pair.Destination, escrowOrder.BaseToken, escrowOrder.QuoteToken))

	stdtesting.SetRealm(stdtesting.NewUserRealm(sender))
	zkgm.Send(cross(cur), pair.Destination, core.Timestamp(1<<62), [32]byte{}, e2e.MustTokenOrderInstruction(cross(cur), escrowOrder))
	stdtesting.SetRealm(stdtesting.NewCodeRealm(pkgPath))

	println("")
	println("[SCENARIO] local GRC20 send escrows into proxy")
	println("sender_after_send", tok.BalanceOf(sender))
	println("proxy_after_send", tok.BalanceOf(zkgm.ProxyAddress()))
	println("channel_after_send", channelBalanceString(pair.Destination, escrowOrder.BaseToken, escrowOrder.QuoteToken))

	order := z.TokenOrderV2{
		Receiver:    []byte(receiver.String()),
		BaseToken:   []byte("remote/base"),
		BaseAmount:  u256.NewUint(20),
		QuoteToken:  []byte(denom),
		QuoteAmount: u256.NewUint(17),
		Kind:        z.TOKEN_ORDER_KIND_UNESCROW,
	}
	packet := tokenOrderPacket(cross(cur), pair.Source, pair.Destination, order)

	stdtesting.SetRealm(stdtesting.NewUserRealm(relayer))
	core.PacketRecv(cross(cur), core.NewMsgPacketRecv(cross(cur), []core.Packet{packet}, nil, nil, core.Height(1)))
	stdtesting.SetRealm(stdtesting.NewCodeRealm(pkgPath))

	println("")
	println("[SCENARIO] counterparty UNESCROW releases GRC20 to receiver and fee to relayer")
	println("sender_after_recv", tok.BalanceOf(sender))
	println("proxy_after_recv", tok.BalanceOf(zkgm.ProxyAddress()))
	println("receiver_balance", tok.BalanceOf(receiver))
	println("relayer_balance", tok.BalanceOf(relayer))
	println("channel_after_recv", channelBalanceString(pair.Destination, order.QuoteToken, order.BaseToken))
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
// [INFO] before send local GRC20 is held by sender
// sender_before_send 20
// proxy_before_send 0
// channel_before_send 0
//
// [SCENARIO] local GRC20 send escrows into proxy
// sender_after_send 0
// proxy_after_send 20
// channel_after_send 20
//
// [SCENARIO] counterparty UNESCROW releases GRC20 to receiver and fee to relayer
// sender_after_recv 0
// proxy_after_recv 0
// receiver_balance 17
// relayer_balance 3
// channel_after_recv 0
// ack_success true
