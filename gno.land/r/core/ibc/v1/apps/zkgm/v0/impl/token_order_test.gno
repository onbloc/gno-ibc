package impl

import (
	"chain"
	"testing"

	z "gno.land/p/gnoswap/ibc/zkgm"
	u256 "gno.land/p/gnoswap/uint256"
	"gno.land/p/nt/bptree/v0"
	"gno.land/p/nt/testutils/v0"
	"gno.land/p/nt/uassert/v0"
	core "gno.land/r/core/ibc/v1/core"
	zkgm "gno.land/r/gnoswap/ibc/v1/apps/zkgm"
)

func TestTokenOrderVerifyEscrowBurnsVoucherAndIncreasesChannelBalance(cur realm, t *testing.T) {
	resetTokenOrderTest()

	sender := testAddress("v1-sender")
	baseToken := "ibc/v1-send"
	uassert.NoError(t, mintVoucher(cross, baseToken, baseToken, [32]byte{}, sender, u256.NewUint(50)))
	order := z.TokenOrderV2{
		Sender:      []byte(sender),
		BaseToken:   []byte(baseToken),
		BaseAmount:  u256.NewUint(13),
		QuoteToken:  []byte("quote"),
		QuoteAmount: u256.NewUint(12),
		Kind:        z.TOKEN_ORDER_KIND_ESCROW,
	}

	err := (&ZkgmV1{}).verifyTokenOrderV2(core.ChannelId(3), sender, nil, order)

	uassert.NoError(t, err)
	uassert.Equal(t, int64(37), VoucherBalanceOf(baseToken, address(sender)))

	balance := zkgm.GetChannelBalanceV2(ChannelBalanceKeyV2(core.ChannelId(3), u256.Zero(), order.BaseToken, order.QuoteToken))
	uassert.Equal(t, "13", balance.ToString())
}

func TestTokenOrderVerifyNativeRequiresSentCoin(cur realm, t *testing.T) {
	order := z.TokenOrderV2{
		Sender:     []byte(testAddress("v1-native-sender")),
		BaseToken:  []byte("ugnot"),
		BaseAmount: u256.NewUint(13),
		QuoteToken: []byte("quote"),
		Kind:       z.TOKEN_ORDER_KIND_INITIALIZE,
	}

	err := (&ZkgmV1{}).verifyTokenOrderV2(core.ChannelId(4), string(order.Sender), chain.NewCoins(chain.NewCoin("ugnot", 13)), order)

	uassert.NoError(t, err)
}

func TestTokenOrderVerifyAppliesRateLimit(cur realm, t *testing.T) {
	denom := "rate-limit-denom"
	zkgm.SetRateLimitDisabled(cross, false)
	zkgm.SetBucketConfig(cross, denom, u256.NewUint(10), u256.NewUint(1))
	order := z.TokenOrderV2{
		Sender:      []byte(testAddress("v1-rate-limit-sender")),
		BaseToken:   []byte(denom),
		BaseAmount:  u256.NewUint(7),
		QuoteToken:  []byte("quote"),
		QuoteAmount: u256.NewUint(7),
		Kind:        z.TOKEN_ORDER_KIND_INITIALIZE,
	}

	err := (&ZkgmV1{}).verifyTokenOrderV2(core.ChannelId(4), string(order.Sender), chain.NewCoins(chain.NewCoin(denom, 7)), order)
	uassert.NoError(t, err)

	err = (&ZkgmV1{}).verifyTokenOrderV2(core.ChannelId(4), string(order.Sender), chain.NewCoins(chain.NewCoin(denom, 7)), order)
	uassert.ErrorContains(t, err, "token bucket rate limit exceeded")

	zkgm.RemoveTokenBucket(cross, denom)
	zkgm.SetRateLimitDisabled(cross, true)
}

func TestTokenOrderExecuteInitializeMintsVoucherAndSuccessAck(cur realm, t *testing.T) {
	resetTokenOrderTest()

	metaBytes := mustEncodeTokenMetadata(z.TokenMetadata{
		Implementation: []byte("grc20"),
		Initializer:    []byte("init"),
	})
	order := z.TokenOrderV2{
		Sender:      []byte("sender"),
		Receiver:    []byte(testAddress("v1-receiver")),
		BaseToken:   []byte("ugnot"),
		BaseAmount:  u256.NewUint(100),
		QuoteToken:  []byte("quote"),
		QuoteAmount: u256.NewUint(95),
		Kind:        z.TOKEN_ORDER_KIND_INITIALIZE,
		Metadata:    metaBytes,
	}
	packet := core.Packet{SourceChannelId: core.ChannelId(1), DestinationChannelId: core.ChannelId(5)}

	res, err := (&ZkgmV1{}).executeTokenOrderV2(packet, u256.NewUint(7), order)

	uassert.NoError(t, err)
	uassert.True(t, res.Status == core.PacketStatusSuccess)
	assertProtocolAck(t, res.Ack)

	image := MetadataImage(mustDecodeTokenMetadata(metaBytes))
	ibcDenom := PredictWrappedTokenV2(core.ChannelId(5), order.BaseToken, image)
	uassert.Equal(t, int64(95), VoucherBalanceOf(ibcDenom, address(order.Receiver)))

	storedImage, ok := zkgm.GetMetadataImageOf(ibcDenom)
	uassert.True(t, ok)
	uassert.True(t, image == storedImage)

	origin, ok := zkgm.GetTokenOrigin(ibcDenom)
	uassert.True(t, ok)
	uassert.Equal(t, "7", origin.ToString())
}

func resetTokenOrderTest() {
	voucherTokens = bptree.NewBPTree32()
}

func testAddress(name string) string {
	return string(testutils.TestAddress(name))
}

func assertProtocolAck(t *testing.T, ackBytes []byte) {
	ack, err := z.DecodeAck(ackBytes)
	uassert.NoError(t, err)
	uassert.True(t, ack.Tag.Eq(tagAckSuccess))

	orderAck, err := z.DecodeTokenOrderAck(ack.InnerAck)
	uassert.NoError(t, err)
	uassert.True(t, orderAck.FillType.Eq(fillTypeProtocol))
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
