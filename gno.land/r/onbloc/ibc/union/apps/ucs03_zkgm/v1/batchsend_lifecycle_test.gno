package ucs03_zkgm

import (
	"testing"

	u256 "gno.land/p/gnoswap/uint256"
	"gno.land/p/nt/uassert/v0"
	types "gno.land/p/onbloc/ibc/union/types"
	z "gno.land/p/onbloc/ibc/union/zkgm"
)

const z36MarketMaker = "g1wymu47drhr0kuq2098m792lytgtj2nyx77yrsm"

func TestZ36BatchSendAckMarketMakerUnescrowMintsVoucher(cur realm, t *testing.T) {
	v := newTestImpl()
	packet, order := z36BatchSendUnescrowPacket("ibc/z36-base")

	v.OnAcknowledgementPacket(0, cur, packet, z36SuccessAck(marketMakerAck(z36MarketMaker)), address(testAddress("z36-relayer")))

	uassert.Equal(t, int64(21), voucherBalanceOf(string(order.BaseToken), address(z36MarketMaker)))
	uassert.Equal(t, int64(0), voucherBalanceOf(string(order.BaseToken), address(string(order.Sender))))
}

func TestZ37BatchSendTimeoutRefundsSenderVoucher(cur realm, t *testing.T) {
	v := newTestImpl()
	packet, order := z36BatchSendUnescrowPacket("ibc/z37-base")
	sender := string(order.Sender)

	v.OnTimeoutPacket(0, cur, packet, address(testAddress("z37-relayer")))

	uassert.Equal(t, int64(21), voucherBalanceOf(string(order.BaseToken), address(sender)))
	uassert.Equal(t, int64(0), voucherBalanceOf(string(order.BaseToken), address(z36MarketMaker)))
}

func z36BatchSendUnescrowPacket(baseToken string) (types.Packet, z.TokenOrderV2) {
	order := z.TokenOrderV2{
		Sender:      []byte(testAddress("timeout-sender")),
		Receiver:    []byte(z36MarketMaker),
		BaseToken:   []byte(baseToken),
		BaseAmount:  u256.NewUint(21),
		QuoteToken:  []byte("ugnot"),
		QuoteAmount: u256.NewUint(21),
		Kind:        z.TOKEN_ORDER_KIND_UNESCROW,
	}
	return types.NewPacket(types.ChannelId(1), types.ChannelId(2), mustZkgmPacketBytes(batchMustOrderInstruction(order)), types.Timestamp(3600)), order
}

func z36SuccessAck(orderAck z.TokenOrderAck) []byte {
	inner, err := z.EncodeTokenOrderAck(orderAck)
	if err != nil {
		panic(err)
	}
	ack, err := z.EncodeAck(z.Ack{Tag: tagAckSuccess(), InnerAck: inner})
	if err != nil {
		panic(err)
	}
	return ack
}
