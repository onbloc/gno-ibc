package impl

import (
	"bytes"
	"chain"
	"testing"
	"time"

	tb "gno.land/p/onbloc/tokenbucket"
	z "gno.land/p/onbloc/unionibc/zkgm"
	u256 "gno.land/p/gnoswap/uint256"
	"gno.land/p/nt/bptree/v0"
	"gno.land/p/nt/testutils/v0"
	"gno.land/p/nt/uassert/v0"
	core "gno.land/r/onbloc/unionibc/v1/core"
	zkgm "gno.land/r/onbloc/unionibc/v1/apps/zkgm"
)

func TestTokenOrderVerifyEscrowBurnsVoucherAndIncreasesChannelBalance(cur realm, t *testing.T) {
	resetTokenOrderTest(cur)

	sender := testAddress("v1-sender")
	baseToken := "ibc/v1-send"
	uassert.NoError(t, mintVoucher(cross(cur), baseToken, baseToken, [32]byte{}, sender, u256.NewUint(50)))
	order := z.TokenOrderV2{
		Sender:      []byte(sender),
		BaseToken:   []byte(baseToken),
		BaseAmount:  u256.NewUint(13),
		QuoteToken:  []byte("quote"),
		QuoteAmount: u256.NewUint(12),
		Kind:        z.TOKEN_ORDER_KIND_ESCROW,
	}

	err := (&ZkgmV1{}).verifyTokenOrderV2(cur, core.ChannelId(3), sender, newSentCoinBudget(nil), u256.Zero(), order)

	uassert.NoError(t, err)
	uassert.Equal(t, int64(37), VoucherBalanceOf(baseToken, address(sender)))

	balance := zkgm.GetChannelBalanceV2(ChannelBalanceKeyV2(core.ChannelId(3), u256.Zero(), order.BaseToken, order.QuoteToken))
	uassert.Equal(t, "13", balance.ToString())
}

func TestTokenOrderAckMarketMakerEscrowWithVoucherRewardsMarketMaker(cur realm, t *testing.T) {
	resetTokenOrderTest(cur)

	sender := testAddress("v1-mm-voucher-sender")
	marketMaker := testAddress("v1-mm-voucher-maker")
	baseToken := "ibc/v1-mm-voucher"
	channelId := core.ChannelId(8)
	amount := u256.NewUint(13)
	uassert.NoError(t, mintVoucher(cross(cur), baseToken, baseToken, [32]byte{}, sender, u256.NewUint(50)))

	order := z.TokenOrderV2{
		Sender:      []byte(sender),
		BaseToken:   []byte(baseToken),
		BaseAmount:  amount,
		QuoteToken:  []byte("quote"),
		QuoteAmount: amount,
		Kind:        z.TOKEN_ORDER_KIND_ESCROW,
	}
	uassert.NoError(t, (&ZkgmV1{}).verifyTokenOrderV2(cur, channelId, sender, newSentCoinBudget(nil), u256.Zero(), order))
	uassert.Equal(t, int64(37), VoucherBalanceOf(baseToken, address(sender)))

	err := (&ZkgmV1{}).acknowledgeTokenOrderV2(cur, channelId, u256.Zero(), order, marketMakerAck(marketMaker))

	uassert.NoError(t, err)
	uassert.Equal(t, int64(13), VoucherBalanceOf(baseToken, address(marketMaker)))

	balance := zkgm.GetChannelBalanceV2(ChannelBalanceKeyV2(channelId, u256.Zero(), order.BaseToken, order.QuoteToken))
	uassert.True(t, balance == nil || balance.IsZero())
}

func TestTokenOrderVerifyNativeRequiresSentCoin(cur realm, t *testing.T) {
	order := z.TokenOrderV2{
		Sender:     []byte(testAddress("v1-native-sender")),
		BaseToken:  []byte("ugnot"),
		BaseAmount: u256.NewUint(13),
		QuoteToken: []byte("quote"),
		Kind:       z.TOKEN_ORDER_KIND_INITIALIZE,
	}

	err := (&ZkgmV1{}).verifyTokenOrderV2(cur, core.ChannelId(4), string(order.Sender), newSentCoinBudget(chain.NewCoins(chain.NewCoin("ugnot", 13))), u256.Zero(), order)

	uassert.NoError(t, err)
}

func TestTokenOrderVerifyUnescrowNativeRejectedBeforeBudgetConsume(cur realm, t *testing.T) {
	resetTokenOrderTest(cur)
	baseDenom := "native-unescrow"
	zkgm.SetTokenOrigin(cross(cur), baseDenom, u256.Zero())
	order := z.TokenOrderV2{
		Sender:      []byte(testAddress("native-unescrow")),
		BaseToken:   []byte(baseDenom),
		BaseAmount:  u256.NewUint(13),
		QuoteToken:  []byte("ugnot"),
		QuoteAmount: u256.NewUint(13),
		Kind:        z.TOKEN_ORDER_KIND_UNESCROW,
	}
	budget := newSentCoinBudget(chain.NewCoins(chain.NewCoin(baseDenom, 13)))

	err := (&ZkgmV1{}).verifyTokenOrderV2(cur, core.ChannelId(0), string(order.Sender), budget, u256.Zero(), order)

	uassert.ErrorContains(t, err, "invalid token order unescrow")
	uassert.False(t, budget.drained())
}

func TestTokenOrderVerifyAppliesRateLimit(cur realm, t *testing.T) {
	denom := "rate-limit-denom"
	now := u256.NewUint(uint64(time.Now().Unix()))
	bucket, err := tb.New(u256.NewUint(10), u256.NewUint(1), now)
	if err != nil {
		t.Fatal(err)
	}
	zkgm.SetTokenBucket(cross(cur), denom, bucket)
	order := z.TokenOrderV2{
		Sender:      []byte(testAddress("v1-rate-limit-sender")),
		BaseToken:   []byte(denom),
		BaseAmount:  u256.NewUint(7),
		QuoteToken:  []byte("quote"),
		QuoteAmount: u256.NewUint(7),
		Kind:        z.TOKEN_ORDER_KIND_INITIALIZE,
	}

	err = (&ZkgmV1{}).verifyTokenOrderV2(cur, core.ChannelId(4), string(order.Sender), newSentCoinBudget(chain.NewCoins(chain.NewCoin(denom, 7))), u256.Zero(), order)
	uassert.NoError(t, err)

	err = (&ZkgmV1{}).verifyTokenOrderV2(cur, core.ChannelId(4), string(order.Sender), newSentCoinBudget(chain.NewCoins(chain.NewCoin(denom, 7))), u256.Zero(), order)
	uassert.ErrorContains(t, err, "token bucket rate limit exceeded")

	zkgm.RemoveTokenBucket(cross(cur), denom)
}

func TestTokenOrderExecuteInitializeMintsVoucherAndSuccessAck(cur realm, t *testing.T) {
	resetTokenOrderTest(cur)

	metaBytes := mustEncodeTokenMetadata(z.TokenMetadata{
		Implementation: []byte("grc20"),
		Initializer:    []byte("init"),
	})
	image := MetadataImage(mustDecodeTokenMetadata(metaBytes))
	ibcDenom := PredictWrappedTokenV2(u256.NewUint(7), 5, []byte("ugnot"), image)
	order := z.TokenOrderV2{
		Sender:      []byte("sender"),
		Receiver:    []byte(testAddress("v1-receiver")),
		BaseToken:   []byte("ugnot"),
		BaseAmount:  u256.NewUint(100),
		QuoteToken:  []byte(ibcDenom),
		QuoteAmount: u256.NewUint(95),
		Kind:        z.TOKEN_ORDER_KIND_INITIALIZE,
		Metadata:    metaBytes,
	}
	packet := core.NewPacket(cross(cur), core.ChannelId(1), core.ChannelId(5), nil, 0, 0)

	res, err := (&ZkgmV1{}).executeTokenOrderV2(cur, packet, address(testAddress("v1-relayer")), u256.NewUint(7), order, false)

	uassert.NoError(t, err)
	uassert.True(t, res.Status == core.PacketStatusSuccess)
	assertProtocolAck(t, res.Ack)

	uassert.Equal(t, int64(95), VoucherBalanceOf(ibcDenom, address(order.Receiver)))

	storedImage, ok := zkgm.GetMetadataImageOf(ibcDenom)
	uassert.True(t, ok)
	uassert.True(t, image == storedImage)

	origin, ok := zkgm.GetTokenOrigin(ibcDenom)
	uassert.True(t, ok)
	uassert.Equal(t, "21474836487", origin.ToString())
}

func TestTokenOrderIntentVoucherMarketMakerFillTransfersMakerFunds(cur realm, t *testing.T) {
	resetTokenOrderTest(cur)

	maker := testAddress("v1-intent-maker")
	receiver := testAddress("v1-intent-receiver")
	quoteToken := "ibc/v1-intent-quote"
	uassert.NoError(t, mintVoucher(cross(cur), quoteToken, "base", [32]byte{}, maker, u256.NewUint(30)))
	order := z.TokenOrderV2{
		Sender:      []byte("sender"),
		Receiver:    []byte(receiver),
		BaseToken:   []byte("ugnot"),
		BaseAmount:  u256.NewUint(100),
		QuoteToken:  []byte(quoteToken),
		QuoteAmount: u256.NewUint(12),
		Kind:        z.TOKEN_ORDER_KIND_ESCROW,
	}
	packet := core.NewPacket(cross(cur), core.ChannelId(1), core.ChannelId(5), nil, 0, 0)

	res, err := (&ZkgmV1{}).executeTokenOrderV2(cur, packet, address(maker), u256.Zero(), order, true)

	uassert.NoError(t, err)
	uassert.True(t, res.Status == core.PacketStatusSuccess)
	assertMarketMakerAck(t, res.Ack, maker)
	uassert.Equal(t, int64(18), VoucherBalanceOf(quoteToken, address(maker)))
	uassert.Equal(t, int64(12), VoucherBalanceOf(quoteToken, address(receiver)))

	if _, ok := zkgm.GetTokenOrigin(quoteToken); ok {
		t.Fatal("market-maker fill must not set token origin")
	}
	balance := zkgm.GetChannelBalanceV2(ChannelBalanceKeyV2(core.ChannelId(5), u256.Zero(), order.BaseToken, order.QuoteToken))
	uassert.True(t, balance == nil || balance.IsZero())
}

func TestTokenOrderIntentUnknownQuoteReturnsOnlyMaker(cur realm, t *testing.T) {
	resetTokenOrderTest(cur)

	order := z.TokenOrderV2{
		Receiver:    []byte(testAddress("int-unknown-rx")),
		BaseToken:   []byte("ugnot"),
		BaseAmount:  u256.NewUint(10),
		QuoteToken:  []byte("ugnot"),
		QuoteAmount: u256.NewUint(10),
		Kind:        z.TOKEN_ORDER_KIND_UNESCROW,
	}
	packet := core.NewPacket(cross(cur), core.ChannelId(1), core.ChannelId(5), nil, 0, 0)

	res, err := (&ZkgmV1{}).executeTokenOrderV2(cur, packet, address(testAddress("v1-intent-maker")), u256.Zero(), order, true)

	uassert.NoError(t, err)
	uassert.True(t, res.Status == core.PacketStatusSuccess)
	uassert.True(t, bytes.Equal(z.ACK_ERR_ONLY_MAKER, res.Ack))
}

func TestTokenOrderIntentInsufficientMakerBalanceReturnsOnlyMaker(cur realm, t *testing.T) {
	resetTokenOrderTest(cur)

	maker := testAddress("v1-intent-poor-maker")
	receiver := testAddress("int-poor-rx")
	quoteToken := "ibc/v1-intent-poor"
	uassert.NoError(t, mintVoucher(cross(cur), quoteToken, "base", [32]byte{}, maker, u256.NewUint(3)))
	order := z.TokenOrderV2{
		Receiver:    []byte(receiver),
		BaseToken:   []byte("ugnot"),
		BaseAmount:  u256.NewUint(10),
		QuoteToken:  []byte(quoteToken),
		QuoteAmount: u256.NewUint(9),
		Kind:        z.TOKEN_ORDER_KIND_ESCROW,
	}
	packet := core.NewPacket(cross(cur), core.ChannelId(1), core.ChannelId(5), nil, 0, 0)

	res, err := (&ZkgmV1{}).executeTokenOrderV2(cur, packet, address(maker), u256.Zero(), order, true)

	uassert.NoError(t, err)
	uassert.True(t, res.Status == core.PacketStatusSuccess)
	uassert.True(t, bytes.Equal(z.ACK_ERR_ONLY_MAKER, res.Ack))
	uassert.Equal(t, int64(3), VoucherBalanceOf(quoteToken, address(maker)))
	uassert.Equal(t, int64(0), VoucherBalanceOf(quoteToken, address(receiver)))
}

func TestAckConstantConstructorsReturnIndependentInstances(t *testing.T) {
	a1, a2 := tagAckSuccess(), tagAckSuccess()
	a1.SetAllOne()
	uassert.True(t, !a2.Eq(a1), "tagAckSuccess: mutation propagated to second call")

	b1, b2 := tagAckFailure(), tagAckFailure()
	b1.SetAllOne()
	uassert.True(t, !b2.Eq(b1), "tagAckFailure: mutation propagated to second call")

	c1, c2 := fillTypeProtocol(), fillTypeProtocol()
	c1.SetAllOne()
	uassert.True(t, !c2.Eq(c1), "fillTypeProtocol: mutation propagated to second call")

	d1, d2 := fillTypeMarketMaker(), fillTypeMarketMaker()
	d1.SetAllOne()
	uassert.True(t, !d2.Eq(d1), "fillTypeMarketMaker: mutation propagated to second call")
}

func resetTokenOrderTest(cur realm) {
	voucherTokens = bptree.NewBPTree32()
	zkgm.UpdateImpl(cross(cur), zkgm.NewUpdateRequest(cross(cur), &ZkgmV1{}, nil))
}

func testAddress(name string) string {
	return string(testutils.TestAddress(name))
}

func assertProtocolAck(t *testing.T, ackBytes []byte) {
	ack, err := z.DecodeAck(ackBytes)
	uassert.NoError(t, err)
	uassert.True(t, ack.Tag.Eq(tagAckSuccess()))

	orderAck, err := z.DecodeTokenOrderAck(ack.InnerAck)
	uassert.NoError(t, err)
	uassert.True(t, orderAck.FillType.Eq(fillTypeProtocol()))
}

func assertMarketMakerAck(t *testing.T, ackBytes []byte, maker string) {
	ack, err := z.DecodeAck(ackBytes)
	uassert.NoError(t, err)
	uassert.True(t, ack.Tag.Eq(tagAckSuccess()))

	orderAck, err := z.DecodeTokenOrderAck(ack.InnerAck)
	uassert.NoError(t, err)
	uassert.True(t, orderAck.FillType.Eq(fillTypeMarketMaker()))
	uassert.Equal(t, maker, string(orderAck.MarketMaker))
}

func marketMakerAck(marketMaker string) z.Ack {
	innerAck, err := z.EncodeTokenOrderAck(z.TokenOrderAck{
		FillType:    fillTypeMarketMaker(),
		MarketMaker: []byte(marketMaker),
	})
	if err != nil {
		panic(err)
	}
	return z.Ack{Tag: tagAckSuccess(), InnerAck: innerAck}
}

func mustEncodeTokenMetadata(meta z.TokenMetadata) []byte {
	bz, err := z.EncodeTokenMetadata(meta)
	if err != nil {
		panic(err)
	}
	return bz
}

func mustDecodeTokenMetadata(bz []byte) z.TokenMetadata {
	meta, err := z.DecodeTokenMetadata(bz)
	if err != nil {
		panic(err)
	}
	return meta
}
