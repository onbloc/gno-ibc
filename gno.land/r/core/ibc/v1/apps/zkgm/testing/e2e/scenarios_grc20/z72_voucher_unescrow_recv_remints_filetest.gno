// PKGPATH: gno.land/r/onbloc/unionibc/v1/apps/zkgm/testing/e2e/scenarios_grc20
package scenarios_grc20

import (
	"gno.land/p/nt/testutils/v0"
	u256 "gno.land/p/gnoswap/uint256"

	z "gno.land/p/onbloc/unionibc/zkgm"

	"gno.land/r/onbloc/unionibc/v1/apps/zkgm"
	"gno.land/r/onbloc/unionibc/v1/apps/zkgm/testing/e2e"

	"gno.land/r/onbloc/unionibc/v1/apps/zkgm/v0/impl"
	"gno.land/r/onbloc/unionibc/v1/core"

	_ "gno.land/r/onbloc/unionibc/v1/apps/zkgm/testing/loader"
)

func main(cur realm) {
	e2e.RegisterMockLightClient(cross(cur))
	pair := e2e.OpenE2EChannelPair(cross(cur))

	receiver := testutils.TestAddress("voucher-recv")
	denom := "ibc/z72-voucher"
	amount := u256.NewUint(17)
	order := z.TokenOrderV2{
		Receiver:    []byte(receiver.String()),
		BaseToken:   []byte("remote/base"),
		BaseAmount:  amount,
		QuoteToken:  []byte(denom),
		QuoteAmount: amount,
		Kind:        z.TOKEN_ORDER_KIND_UNESCROW,
	}
	setChannelBalance(cross(cur), pair.Destination, order.QuoteToken, order.BaseToken, amount)
	packet := tokenOrderPacket(cross(cur), pair.Source, pair.Destination, order)

	core.PacketRecv(cross(cur), core.NewMsgPacketRecv(cross(cur), []core.Packet{packet}, nil, nil, core.Height(1)))

	println("receiver_balance", impl.VoucherBalanceOf(denom, receiver))
	println("channel_balance", channelBalanceString(pair.Destination, order.QuoteToken, order.BaseToken))
	println("ack_success", core.AcknowledgementHash(cross(cur), packet).String() == successAckHash(cross(cur)))
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
// receiver_balance 17
// channel_balance 0
// ack_success true
