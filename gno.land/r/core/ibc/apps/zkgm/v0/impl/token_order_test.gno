package impl

import (
	"chain"
	"chain/banker"
	"chain/runtime"
	"testing"

	"gno.land/p/aib/ibc/types"
	z "gno.land/p/gnoswap/ibc/zkgm"
	u256 "gno.land/p/gnoswap/uint256"
	"gno.land/p/nt/bptree/v0"
	"gno.land/p/nt/testutils/v0"
	"gno.land/p/nt/uassert/v0"
	zkgm "gno.land/r/gnoswap/ibc/apps/zkgm"
)

func TestExecuteInitializeMintsVoucherAndSuccessAck(cur realm, t *testing.T) {
	resetImplForTest()

	metaBytes := mustEncodeTokenMetadata(z.TokenMetadata{
		Implementation: []byte("grc20"),
		Initializer:    []byte("init"),
	})
	image := MetadataImage(mustDecodeTokenMetadata(metaBytes))
	ibcDenom := PredictWrappedTokenV2(u256.NewUint(7), 1, []byte("ugnot"), image)
	order := z.TokenOrderV2{
		Sender:      []byte("sender"),
		Receiver:    []byte(testAddress("receiver")),
		BaseToken:   []byte("ugnot"),
		BaseAmount:  u256.NewUint(100),
		QuoteToken:  []byte(ibcDenom),
		QuoteAmount: u256.NewUint(95),
		Kind:        z.TOKEN_ORDER_KIND_INITIALIZE,
		Metadata:    metaBytes,
	}

	res, err := (&ZkgmV0{}).executeTokenOrderV2(zkgm.RecvRequest{
		DestinationClient: "client-1",
		Caller:            testAddress("relayer"),
	}, u256.NewUint(7), order)

	uassert.NoError(t, err)
	uassert.True(t, res.Status == types.PacketStatus_Success)
	assertProtocolAck(t, res.Acknowledgement)

	uassert.Equal(t, int64(95), VoucherBalanceOf(ibcDenom, address(order.Receiver)))
	uassert.Equal(t, int64(5), VoucherBalanceOf(ibcDenom, address(testAddress("relayer"))))
	storedImage, ok := zkgm.GetMetadataImageOf(ibcDenom)
	uassert.True(t, ok)
	uassert.True(t, image == storedImage)
	origin, ok := zkgm.GetTokenOrigin(ibcDenom)
	uassert.True(t, ok)
	uassert.Equal(t, "4294967303", origin.ToString())
}

func TestVerifyEscrowBurnsVoucherAndIncreasesChannelBalance(cur realm, t *testing.T) {
	resetImplForTest()

	sender := testAddress("sender")
	baseToken := "ibc/send"
	uassert.NoError(t, mintVoucher(cross, baseToken, baseToken, [32]byte{}, sender, u256.NewUint(50)))
	order := z.TokenOrderV2{
		Sender:      []byte(sender),
		BaseToken:   []byte(baseToken),
		BaseAmount:  u256.NewUint(13),
		QuoteToken:  []byte("quote"),
		QuoteAmount: u256.NewUint(12),
		Kind:        z.TOKEN_ORDER_KIND_ESCROW,
	}

	err := (&ZkgmV0{}).verifyTokenOrderV2("client-0", sender, nil, u256.Zero(), order)

	uassert.NoError(t, err)
	uassert.Equal(t, int64(37), VoucherBalanceOf(baseToken, address(sender)))
	balance := zkgm.GetChannelBalanceV2(ChannelBalanceKeyV2("client-0", u256.Zero(), order.BaseToken, order.QuoteToken))
	uassert.Equal(t, "13", balance.ToString())
}

func TestExecuteEscrowMintsQuoteVoucher(cur realm, t *testing.T) {
	resetImplForTest()

	receiver := testAddress("receiver")
	path := u256.NewUint(2)
	image := MetadataImage(z.TokenMetadata{Implementation: []byte("grc20"), Initializer: []byte("quote")})
	quoteToken := PredictWrappedTokenV2(path, 1, []byte("ugnot"), image)
	uassert.NoError(t, mintVoucher(cross, quoteToken, "quote", image, receiver, u256.NewUint(1)))
	order := z.TokenOrderV2{
		Receiver:    []byte(receiver),
		BaseToken:   []byte("ugnot"),
		BaseAmount:  u256.NewUint(100),
		QuoteToken:  []byte(quoteToken),
		QuoteAmount: u256.NewUint(21),
		Kind:        z.TOKEN_ORDER_KIND_ESCROW,
	}

	res, err := (&ZkgmV0{}).executeTokenOrderV2(zkgm.RecvRequest{
		DestinationClient: "client-1",
		Caller:            testAddress("relayer"),
	}, path, order)

	uassert.NoError(t, err)
	uassert.True(t, res.Status == types.PacketStatus_Success)
	assertProtocolAck(t, res.Acknowledgement)
	uassert.Equal(t, int64(22), VoucherBalanceOf(quoteToken, address(receiver)))
}

func TestSolveKindRemainsUnsupported(cur realm, t *testing.T) {
	err := (&ZkgmV0{}).verifyTokenOrderV2("client-0", "sender", nil, u256.Zero(), z.TokenOrderV2{
		Kind: z.TOKEN_ORDER_KIND_SOLVE,
	})

	uassert.ErrorContains(t, err, "solve token order not implemented")
}

func TestAckFailureRefundsEscrowedVoucher(cur realm, t *testing.T) {
	resetImplForTest()

	sender := testAddress("sender")
	baseToken := "ibc/refund"
	order := z.TokenOrderV2{
		Sender:      []byte(sender),
		BaseToken:   []byte(baseToken),
		BaseAmount:  u256.NewUint(40),
		QuoteToken:  []byte("quote"),
		QuoteAmount: u256.NewUint(40),
		Kind:        z.TOKEN_ORDER_KIND_ESCROW,
	}
	path := u256.NewUint(9)
	increaseChannelBalanceV2(cross, "client-0", path, order.BaseToken, order.QuoteToken, order.BaseAmount)

	err := (&ZkgmV0{}).acknowledgeTokenOrderV2("client-0", path, order, z.Ack{
		Tag:      tagAckFailure,
		InnerAck: []byte("failed"),
	})

	uassert.NoError(t, err)
	uassert.Equal(t, int64(40), VoucherBalanceOf(baseToken, address(sender)))
	uassert.True(t, zkgm.GetChannelBalanceV2(ChannelBalanceKeyV2("client-0", path, order.BaseToken, order.QuoteToken)) == nil)
}

func TestTimeoutRefundsEscrowedVoucher(cur realm, t *testing.T) {
	resetImplForTest()

	sender := testAddress("sender")
	order := z.TokenOrderV2{
		Sender:      []byte(sender),
		BaseToken:   []byte("ibc/timeout"),
		BaseAmount:  u256.NewUint(11),
		QuoteToken:  []byte("quote"),
		QuoteAmount: u256.NewUint(11),
		Kind:        z.TOKEN_ORDER_KIND_ESCROW,
	}
	path := u256.NewUint(3)
	increaseChannelBalanceV2(cross, "client-0", path, order.BaseToken, order.QuoteToken, order.BaseAmount)

	err := (&ZkgmV0{}).refundV2("client-0", path, order)

	uassert.NoError(t, err)
	uassert.Equal(t, int64(11), VoucherBalanceOf("ibc/timeout", address(sender)))
	uassert.True(t, zkgm.GetChannelBalanceV2(ChannelBalanceKeyV2("client-0", path, order.BaseToken, order.QuoteToken)) == nil)
}

func TestAckMarketMakerUnescrowMintsVoucher(cur realm, t *testing.T) {
	resetImplForTest()

	marketMaker := testAddress("marketmaker")
	order := z.TokenOrderV2{
		BaseToken:   []byte("ibc/mm"),
		BaseAmount:  u256.NewUint(23),
		QuoteToken:  []byte("ugnot"),
		QuoteAmount: u256.NewUint(20),
		Kind:        z.TOKEN_ORDER_KIND_UNESCROW,
	}
	ack := z.Ack{
		Tag:      tagAckSuccess,
		InnerAck: mustEncodeTokenOrderAck(z.TokenOrderAck{FillType: fillTypeMarketMaker, MarketMaker: []byte(marketMaker)}),
	}

	err := (&ZkgmV0{}).acknowledgeTokenOrderV2("client-0", u256.Zero(), order, ack)

	uassert.NoError(t, err)
	uassert.Equal(t, int64(23), VoucherBalanceOf("ibc/mm", address(marketMaker)))
}

func TestAckSuccessProtocolNoopPreservesChannelBalance(cur realm, t *testing.T) {
	resetImplForTest()

	order := z.TokenOrderV2{
		BaseToken:   []byte("ibc/escrow"),
		BaseAmount:  u256.NewUint(5),
		QuoteToken:  []byte("quote"),
		QuoteAmount: u256.NewUint(5),
		Kind:        z.TOKEN_ORDER_KIND_ESCROW,
	}
	path := u256.NewUint(4)
	increaseChannelBalanceV2(cross, "client-0", path, order.BaseToken, order.QuoteToken, order.BaseAmount)
	ack := z.Ack{
		Tag:      tagAckSuccess,
		InnerAck: mustEncodeTokenOrderAck(z.TokenOrderAck{FillType: fillTypeProtocol}),
	}

	err := (&ZkgmV0{}).acknowledgeTokenOrderV2("client-0", path, order, ack)

	uassert.NoError(t, err)
	balance := zkgm.GetChannelBalanceV2(ChannelBalanceKeyV2("client-0", path, order.BaseToken, order.QuoteToken))
	uassert.Equal(t, "5", balance.ToString())
}

func TestTokenTransferRoundTripReleasesEscrowedNative(cur realm, t *testing.T) {
	resetImplForTest()

	sender := testAddress("roundtrip-sender")
	receiver := testAddress("roundtrip-receiver")
	channelID := "client-1"
	nativeDenom := "/" + runtime.CurrentRealm().PkgPath() + ":roundtrip"
	amount := u256.NewUint(100)
	metaBytes := mustEncodeTokenMetadata(z.TokenMetadata{
		Implementation: []byte("grc20"),
		Initializer:    []byte("roundtrip"),
	})
	image := MetadataImage(mustDecodeTokenMetadata(metaBytes))
	voucherDenom := PredictWrappedTokenV2(u256.Zero(), 1, []byte(nativeDenom), image)

	issueNativeToCurrentRealm(nativeDenom, 100)
	beforeReceiverNative := nativeBalance(receiver, nativeDenom)

	sendOrder := z.TokenOrderV2{
		Sender:      []byte(sender),
		Receiver:    []byte(sender),
		BaseToken:   []byte(nativeDenom),
		BaseAmount:  amount,
		QuoteToken:  []byte(voucherDenom),
		QuoteAmount: amount,
		Kind:        z.TOKEN_ORDER_KIND_INITIALIZE,
		Metadata:    metaBytes,
	}
	err := (&ZkgmV0{}).verifyTokenOrderV2(channelID, sender, chain.NewCoins(chain.NewCoin(nativeDenom, 100)), u256.Zero(), sendOrder)
	uassert.NoError(t, err)
	sourceKey := ChannelBalanceKeyV2(channelID, u256.Zero(), sendOrder.BaseToken, sendOrder.QuoteToken)
	uassert.Equal(t, "100", zkgm.GetChannelBalanceV2(sourceKey).ToString())

	recvRes, err := (&ZkgmV0{}).executeTokenOrderV2(zkgm.RecvRequest{
		DestinationClient: channelID,
		Relayer:           []byte(testAddress("roundtrip-relayer")),
	}, u256.Zero(), sendOrder)
	uassert.NoError(t, err)
	uassert.True(t, recvRes.Status == types.PacketStatus_Success)
	assertProtocolAck(t, recvRes.Acknowledgement)
	uassert.Equal(t, int64(100), VoucherBalanceOf(voucherDenom, address(sender)))

	returnOrder := z.TokenOrderV2{
		Sender:      []byte(sender),
		Receiver:    []byte(receiver),
		BaseToken:   []byte(voucherDenom),
		BaseAmount:  amount,
		QuoteToken:  []byte(nativeDenom),
		QuoteAmount: amount,
		Kind:        z.TOKEN_ORDER_KIND_UNESCROW,
	}
	err = (&ZkgmV0{}).verifyTokenOrderV2(channelID, sender, nil, u256.Zero(), returnOrder)
	uassert.NoError(t, err)
	uassert.Equal(t, int64(0), VoucherBalanceOf(voucherDenom, address(sender)))

	returnRes, err := (&ZkgmV0{}).executeTokenOrderV2(zkgm.RecvRequest{
		DestinationClient: channelID,
		Relayer:           []byte(testAddress("roundtrip-relayer")),
	}, u256.Zero(), returnOrder)
	uassert.NoError(t, err)
	uassert.True(t, returnRes.Status == types.PacketStatus_Success)
	assertProtocolAck(t, returnRes.Acknowledgement)
	uassert.True(t, zkgm.GetChannelBalanceV2(sourceKey) == nil)
	uassert.Equal(t, beforeReceiverNative+100, nativeBalance(receiver, nativeDenom))
}

func resetImplForTest() {
	voucherTokens = bptree.NewBPTree32()
}

func testAddress(name string) string {
	return string(testutils.TestAddress(name))
}

func issueNativeToCurrentRealm(denom string, amount int64) {
	b := banker.NewBanker(banker.BankerTypeRealmIssue)
	b.IssueCoin(runtime.CurrentRealm().Address(), denom, amount)
}

func nativeBalance(addr string, denom string) int64 {
	b := banker.NewBanker(banker.BankerTypeReadonly)
	return b.GetCoins(address(addr)).AmountOf(denom)
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

func mustEncodeTokenOrderAck(ack z.TokenOrderAck) []byte {
	bz, err := z.EncodeTokenOrderAck(ack)
	if err != nil {
		panic(err)
	}
	return bz
}
