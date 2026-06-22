// PKGPATH: gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/v1/main
package main

import (
	"testing"

	"gno.land/p/nt/testutils/v0"
	"gno.land/p/nt/uassert/v0"
	types "gno.land/p/onbloc/ibc/union/types"
	z "gno.land/p/onbloc/ibc/union/zkgm"
	u256 "gno.land/p/gnoswap/uint256"
	zkgm "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm"
	impl "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/v1"
)

var t *testing.T

func main(cur realm) {
	app := impl.NewUCS03ZkgmV1(zkgm.NewStore())
	source := types.ChannelId(1)
	sender := string(testutils.TestAddress("zs14b-sender"))
	marketMaker := string(testutils.TestAddress("zs14b-maker"))
	baseToken := "ibc/zs14b-base"
	quoteToken := "quote"

	order := z.TokenOrderV2{
		Sender:      []byte(sender),
		Receiver:    []byte(marketMaker),
		BaseToken:   []byte(baseToken),
		BaseAmount:  u256.NewUint(21),
		QuoteToken:  []byte(quoteToken),
		QuoteAmount: u256.NewUint(21),
		Kind:        z.TOKEN_ORDER_KIND_ESCROW,
	}
	packet := types.NewPacket(source, types.ChannelId(2), mustZS14BPacketData(mustZS14BTokenOrderInstruction(order)), types.Timestamp(1))
	key := impl.ChannelBalanceKeyV2(source, u256.Zero(), order.BaseToken, order.QuoteToken)

	println("[SCENARIO] ack and timeout reject missing escrow")
	uassert.AbortsContains(t, cur, "zkgm/channel_balance: underflow", func() {
		app.OnAcknowledgementPacket(0, cur, packet, mustZS14BSuccessAck(mustZS14BMarketMakerTokenOrderAck([]byte(marketMaker))), testutils.TestAddress("zs14b-relayer"))
	})
	uassert.AbortsContains(t, cur, "zkgm/channel_balance: underflow", func() {
		app.OnTimeoutPacket(0, cur, packet, testutils.TestAddress("zs14b-relayer"))
	})
	println("channel_balance_key", key)
	println("ack_timeout_boundaries", "ok")
}

func mustZS14BTokenOrderInstruction(order z.TokenOrderV2) z.Instruction {
	bz, err := z.EncodeTokenOrderV2(order)
	if err != nil {
		panic(err)
	}
	return z.Instruction{Version: z.INSTR_VERSION_2, Opcode: z.OP_TOKEN_ORDER, Operand: bz}
}

func mustZS14BPacketData(instr z.Instruction) []byte {
	bz, err := z.EncodeZkgmPacket(z.ZkgmPacket{Path: u256.Zero(), Instruction: instr})
	if err != nil {
		panic(err)
	}
	return bz
}

func mustZS14BMarketMakerTokenOrderAck(marketMaker []byte) []byte {
	bz, err := z.EncodeTokenOrderAck(z.TokenOrderAck{
		FillType:    new(u256.Uint).SetBytes(z.FILL_TYPE_MARKETMAKER[:]),
		MarketMaker: marketMaker,
	})
	if err != nil {
		panic(err)
	}
	return bz
}

func mustZS14BSuccessAck(inner []byte) []byte {
	bz, err := z.EncodeAck(z.Ack{Tag: new(u256.Uint).SetBytes(z.TAG_ACK_SUCCESS[:]), InnerAck: inner})
	if err != nil {
		panic(err)
	}
	return bz
}

// Output:
// [SCENARIO] ack and timeout reject missing escrow
// channel_balance_key 1/0/6962632f7a733134622d62617365/71756f7465
// ack_timeout_boundaries ok
