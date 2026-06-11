package impl

import (
	"bytes"
	"chain"
	"math"
	"testing"
	"time"

	"gno.land/p/demo/tokens/grc20"
	u256 "gno.land/p/gnoswap/uint256"
	"gno.land/p/nt/bptree/v0"
	"gno.land/p/nt/testutils/v0"
	"gno.land/p/nt/uassert/v0"
	tb "gno.land/p/onbloc/tokenbucket"
	z "gno.land/p/onbloc/unionibc/zkgm"
	"gno.land/r/demo/defi/grc20reg"
	zkgm "gno.land/r/onbloc/unionibc/v1/apps/zkgm"
	core "gno.land/r/onbloc/unionibc/v1/core"
)

func TestTokenOrderVerifyEscrowBurnsVoucherAndIncreasesChannelBalance(cur realm, t *testing.T) {
	resetTokenOrderTest(cur)

	sender := testAddress("v1-sender")
	baseToken := "ibc/v1-send"
	uassert.NoError(t, zkgm.MintVoucher(cross(cur), baseToken, baseToken, [32]byte{}, "", "", 0, sender, u256.NewUint(50)))
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
	uassert.NoError(t, zkgm.MintVoucher(cross(cur), baseToken, baseToken, [32]byte{}, "", "", 0, sender, u256.NewUint(50)))

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

func TestTokenOrderVerifyGRC20EscrowsWithApproval(cur realm, t *testing.T) {
	resetTokenOrderTest(cur)

	sender := testAddress("v1-grc20-sender")
	denom, tok, ledger := registerImplTestGRC20(cur, "send_approved")
	uassert.NoError(t, ledger.Mint(address(sender), 30))
	uassert.NoError(t, ledger.Approve(address(sender), zkgm.ProxyAddress(), 13))
	order := z.TokenOrderV2{
		Sender:      []byte(sender),
		BaseToken:   []byte(denom),
		BaseAmount:  u256.NewUint(13),
		QuoteToken:  []byte("quote"),
		QuoteAmount: u256.NewUint(12),
		Kind:        z.TOKEN_ORDER_KIND_ESCROW,
	}

	err := (&ZkgmV1{}).verifyTokenOrderV2(cur, core.ChannelId(9), sender, newSentCoinBudget(nil), u256.Zero(), order)

	uassert.NoError(t, err)
	uassert.Equal(t, int64(17), tok.BalanceOf(address(sender)))
	uassert.Equal(t, int64(13), tok.BalanceOf(zkgm.ProxyAddress()))
	uassert.True(t, assetClassFor(denom) == classLocalGRC20)
	balance := zkgm.GetChannelBalanceV2(ChannelBalanceKeyV2(core.ChannelId(9), u256.Zero(), order.BaseToken, order.QuoteToken))
	uassert.Equal(t, "13", balance.ToString())
}

func TestTokenOrderVerifyEscrowRejectsSenderMismatch(cur realm, t *testing.T) {
	resetTokenOrderTest(cur)

	sender := testAddress("sender-mismatch-real")
	wireSender := testAddress("sender-mismatch-wire")
	denom, tok, ledger := registerImplTestGRC20(cur, "sender_mismatch")
	uassert.NoError(t, ledger.Mint(address(sender), 30))
	uassert.NoError(t, ledger.Approve(address(sender), zkgm.ProxyAddress(), 13))
	order := z.TokenOrderV2{
		Sender:      []byte(wireSender),
		BaseToken:   []byte(denom),
		BaseAmount:  u256.NewUint(13),
		QuoteToken:  []byte("quote"),
		QuoteAmount: u256.NewUint(12),
		Kind:        z.TOKEN_ORDER_KIND_ESCROW,
	}

	err := (&ZkgmV1{}).verifyTokenOrderV2(cur, core.ChannelId(12), sender, newSentCoinBudget(nil), u256.Zero(), order)

	uassert.ErrorContains(t, err, "sender mismatch")
	uassert.Equal(t, int64(30), tok.BalanceOf(address(sender)))
	uassert.Equal(t, int64(0), tok.BalanceOf(zkgm.ProxyAddress()))
	balance := zkgm.GetChannelBalanceV2(ChannelBalanceKeyV2(core.ChannelId(12), u256.Zero(), order.BaseToken, order.QuoteToken))
	uassert.True(t, balance == nil)
}

func TestTokenOrderVerifyGRC20WithoutApprovalDoesNotIncreaseChannelBalance(cur realm, t *testing.T) {
	resetTokenOrderTest(cur)

	sender := testAddress("v1-grc20-no-approval")
	denom, tok, ledger := registerImplTestGRC20(cur, "send_noapproval")
	uassert.NoError(t, ledger.Mint(address(sender), 30))
	order := z.TokenOrderV2{
		Sender:      []byte(sender),
		BaseToken:   []byte(denom),
		BaseAmount:  u256.NewUint(13),
		QuoteToken:  []byte("quote"),
		QuoteAmount: u256.NewUint(12),
		Kind:        z.TOKEN_ORDER_KIND_ESCROW,
	}

	err := (&ZkgmV1{}).verifyTokenOrderV2(cur, core.ChannelId(10), sender, newSentCoinBudget(nil), u256.Zero(), order)

	uassert.ErrorContains(t, err, "insufficient allowance")
	uassert.Equal(t, int64(30), tok.BalanceOf(address(sender)))
	uassert.Equal(t, int64(0), tok.BalanceOf(zkgm.ProxyAddress()))
	balance := zkgm.GetChannelBalanceV2(ChannelBalanceKeyV2(core.ChannelId(10), u256.Zero(), order.BaseToken, order.QuoteToken))
	uassert.True(t, balance == nil || balance.IsZero())
}

func TestTokenOrderVerifyGRC20ZeroAmountReturnsError(cur realm, t *testing.T) {
	resetTokenOrderTest(cur)

	sender := testAddress("v1-grc20-zero")
	denom, tok, ledger := registerImplTestGRC20(cur, "send_zero")
	uassert.NoError(t, ledger.Mint(address(sender), 30))
	uassert.NoError(t, ledger.Approve(address(sender), zkgm.ProxyAddress(), 13))
	order := z.TokenOrderV2{
		Sender:      []byte(sender),
		BaseToken:   []byte(denom),
		BaseAmount:  u256.Zero(),
		QuoteToken:  []byte("quote"),
		QuoteAmount: u256.Zero(),
		Kind:        z.TOKEN_ORDER_KIND_ESCROW,
	}

	err := (&ZkgmV1{}).verifyTokenOrderV2(cur, core.ChannelId(16), sender, newSentCoinBudget(nil), u256.Zero(), order)

	uassert.ErrorContains(t, err, "base amount must be positive")
	uassert.Equal(t, int64(30), tok.BalanceOf(address(sender)))
	uassert.Equal(t, int64(0), tok.BalanceOf(zkgm.ProxyAddress()))
	balance := zkgm.GetChannelBalanceV2(ChannelBalanceKeyV2(core.ChannelId(16), u256.Zero(), order.BaseToken, order.QuoteToken))
	uassert.True(t, balance == nil || balance.IsZero())
}

func TestTokenOrderVerifyGRC20RejectsStrayNativeCoin(cur realm, t *testing.T) {
	resetTokenOrderTest(cur)

	sender := testAddress("g20-stray")
	denom, _, ledger := registerImplTestGRC20(cur, "send_stray")
	uassert.NoError(t, ledger.Mint(address(sender), 30))
	uassert.NoError(t, ledger.Approve(address(sender), zkgm.ProxyAddress(), 13))
	order := z.TokenOrderV2{
		Sender:      []byte(sender),
		BaseToken:   []byte(denom),
		BaseAmount:  u256.NewUint(13),
		QuoteToken:  []byte("quote"),
		QuoteAmount: u256.NewUint(12),
		Kind:        z.TOKEN_ORDER_KIND_ESCROW,
	}
	budget := newSentCoinBudget(chain.NewCoins(chain.NewCoin("ugnot", 1)))

	err := (&ZkgmV1{}).verifyTokenOrderV2(cur, core.ChannelId(11), sender, budget, u256.Zero(), order)
	uassert.NoError(t, err)
	uassert.ErrorContains(t, budget.assertDrained(), "sent coin mismatch")
}

func TestTokenOrderExecuteUnescrowReleasesLocalGRC20(cur realm, t *testing.T) {
	resetTokenOrderTest(cur)

	receiver := testAddress("g20-unescrow-rx")
	relayer := testAddress("g20-unescrow-relay")
	denom, tok, ledger := registerImplTestGRC20(cur, "unescrow_release")
	uassert.NoError(t, ledger.Mint(zkgm.ProxyAddress(), 20))
	recordAssetClass(denom, classLocalGRC20)
	path := u256.NewUint(7)
	reversed, err := z.ReverseChannelPath(path)
	uassert.NoError(t, err)
	order := z.TokenOrderV2{
		Receiver:    []byte(receiver),
		BaseToken:   []byte("remote"),
		BaseAmount:  u256.NewUint(20),
		QuoteToken:  []byte(denom),
		QuoteAmount: u256.NewUint(17),
		Kind:        z.TOKEN_ORDER_KIND_UNESCROW,
	}
	packet := core.NewPacket(cross(cur), core.ChannelId(1), core.ChannelId(12), nil, 0, 0)
	increaseChannelBalanceV2(cross(cur), packet.DestinationChannelId, reversed, order.QuoteToken, order.BaseToken, order.BaseAmount)

	res, err := (&ZkgmV1{}).executeTokenOrderV2(cur, packet, address(relayer), path, order, false)

	uassert.NoError(t, err)
	uassert.True(t, res.Status == core.PacketStatusSuccess)
	uassert.Equal(t, int64(0), tok.BalanceOf(zkgm.ProxyAddress()))
	uassert.Equal(t, int64(17), tok.BalanceOf(address(receiver)))
	uassert.Equal(t, int64(3), tok.BalanceOf(address(relayer)))
}

func TestTokenOrderAckFailureRefundsLocalGRC20(cur realm, t *testing.T) {
	resetTokenOrderTest(cur)

	sender := testAddress("v1-grc20-ack-refund")
	denom, tok, ledger := registerImplTestGRC20(cur, "ack_refund")
	uassert.NoError(t, ledger.Mint(zkgm.ProxyAddress(), 13))
	recordAssetClass(denom, classLocalGRC20)
	order := z.TokenOrderV2{
		Sender:      []byte(sender),
		BaseToken:   []byte(denom),
		BaseAmount:  u256.NewUint(13),
		QuoteToken:  []byte("quote"),
		QuoteAmount: u256.NewUint(12),
		Kind:        z.TOKEN_ORDER_KIND_ESCROW,
	}
	increaseChannelBalanceV2(cross(cur), core.ChannelId(13), u256.Zero(), order.BaseToken, order.QuoteToken, order.BaseAmount)

	err := (&ZkgmV1{}).acknowledgeTokenOrderV2(cur, core.ChannelId(13), u256.Zero(), order, z.Ack{Tag: tagAckFailure()})

	uassert.NoError(t, err)
	uassert.Equal(t, int64(0), tok.BalanceOf(zkgm.ProxyAddress()))
	uassert.Equal(t, int64(13), tok.BalanceOf(address(sender)))
}

func TestTokenOrderTimeoutRefundsLocalGRC20(cur realm, t *testing.T) {
	resetTokenOrderTest(cur)

	sender := testAddress("g20-timeout-refund")
	denom, tok, ledger := registerImplTestGRC20(cur, "timeout_refund")
	uassert.NoError(t, ledger.Mint(zkgm.ProxyAddress(), 13))
	recordAssetClass(denom, classLocalGRC20)
	order := z.TokenOrderV2{
		Sender:      []byte(sender),
		BaseToken:   []byte(denom),
		BaseAmount:  u256.NewUint(13),
		QuoteToken:  []byte("quote"),
		QuoteAmount: u256.NewUint(12),
		Kind:        z.TOKEN_ORDER_KIND_ESCROW,
	}
	increaseChannelBalanceV2(cross(cur), core.ChannelId(14), u256.Zero(), order.BaseToken, order.QuoteToken, order.BaseAmount)

	err := (&ZkgmV1{}).refundV2(cur, core.ChannelId(14), u256.Zero(), order)

	uassert.NoError(t, err)
	uassert.Equal(t, int64(0), tok.BalanceOf(zkgm.ProxyAddress()))
	uassert.Equal(t, int64(13), tok.BalanceOf(address(sender)))
}

func TestTokenOrderPersistedNativeClassSurvivesLaterGRC20Registration(cur realm, t *testing.T) {
	resetTokenOrderTest(cur)

	denom := "gno.land/r/onbloc/unionibc/v1/apps/zkgm/v0/impl.native_later_grc20"
	recipient := testAddress("native-persist-rx")
	order := z.TokenOrderV2{
		Sender:      []byte(testAddress("native-persist-send")),
		BaseToken:   []byte(denom),
		BaseAmount:  u256.NewUint(7),
		QuoteToken:  []byte("quote"),
		QuoteAmount: u256.NewUint(7),
		Kind:        z.TOKEN_ORDER_KIND_ESCROW,
	}
	uassert.NoError(t, (&ZkgmV1{}).verifyTokenOrderV2(cur, core.ChannelId(15), string(order.Sender), newSentCoinBudget(chain.NewCoins(chain.NewCoin(denom, 7))), u256.Zero(), order))
	testing.IssueCoins(zkgm.ProxyAddress(), chain.NewCoins(chain.NewCoin(denom, 7)))
	token, _ := grc20.NewToken(0, cur, "Native Later Token", "NLT", 0)
	grc20reg.Register(cross(cur), token, "native_later_grc20")

	err := settleEscrowedV2(cur, core.ChannelId(15), u256.Zero(), order, recipient)

	uassert.NoError(t, err)
	uassert.True(t, assetClassFor(denom) == classNative)
}

func TestAssetClassFallbackTreatsUnrecordedRegisteredDenomAsNative(cur realm, t *testing.T) {
	resetTokenOrderTest(cur)

	denom := "gno.land/r/onbloc/unionibc/v1/apps/zkgm/v0/impl.native_inflight"
	token, _ := grc20.NewToken(0, cur, "Inflight Native Token", "INT", 0)
	grc20reg.Register(cross(cur), token, "native_inflight")

	uassert.True(t, assetClassFor(denom) == classNative)
}

func TestAssetClassFallbackTreatsUnrecordedIBCDenomAsVoucher(cur realm, t *testing.T) {
	resetTokenOrderTest(cur)

	uassert.True(t, assetClassFor("ibc/inflight") == classVoucher)
}

func TestTokenOrderVerifyRejectsEscrowAfterRecordedClassChanges(cur realm, t *testing.T) {
	resetTokenOrderTest(cur)

	sender := testAddress("native-class-change")
	denom := "gno.land/r/onbloc/unionibc/v1/apps/zkgm/v0/impl.native_later_grc20_escrow"
	order := z.TokenOrderV2{
		Sender:      []byte(sender),
		BaseToken:   []byte(denom),
		BaseAmount:  u256.NewUint(7),
		QuoteToken:  []byte("quote"),
		QuoteAmount: u256.NewUint(7),
		Kind:        z.TOKEN_ORDER_KIND_ESCROW,
	}
	uassert.NoError(t, (&ZkgmV1{}).verifyTokenOrderV2(cur, core.ChannelId(17), sender, newSentCoinBudget(chain.NewCoins(chain.NewCoin(denom, 7))), u256.Zero(), order))

	token, ledger := grc20.NewToken(0, cur, "Native Later Escrow Token", "NLE", 0)
	uassert.NoError(t, ledger.Mint(address(sender), 7))
	uassert.NoError(t, ledger.Approve(address(sender), zkgm.ProxyAddress(), 7))
	grc20reg.Register(cross(cur), token, "native_later_grc20_escrow")

	err := (&ZkgmV1{}).verifyTokenOrderV2(cur, core.ChannelId(18), sender, newSentCoinBudget(chain.NewCoins(chain.NewCoin(denom, 7))), u256.Zero(), order)

	uassert.ErrorContains(t, err, "asset class changed")
	uassert.Equal(t, int64(7), token.BalanceOf(address(sender)))
	uassert.Equal(t, int64(0), token.BalanceOf(zkgm.ProxyAddress()))
	balance := zkgm.GetChannelBalanceV2(ChannelBalanceKeyV2(core.ChannelId(18), u256.Zero(), order.BaseToken, order.QuoteToken))
	uassert.True(t, balance == nil || balance.IsZero())
}

func TestTokenOrderVerifyNativeEscrowConsumesBudgetAndIncreasesChannelBalance(cur realm, t *testing.T) {
	resetTokenOrderTest(cur)

	sender := testAddress("native-escrow-sender")
	const channelId = core.ChannelId(20)
	order := z.TokenOrderV2{
		Sender:      []byte(sender),
		BaseToken:   []byte("ugnot"),
		BaseAmount:  u256.NewUint(13),
		QuoteToken:  []byte("quote-native"),
		QuoteAmount: u256.NewUint(13),
		Kind:        z.TOKEN_ORDER_KIND_ESCROW,
	}
	budget := newSentCoinBudget(chain.NewCoins(chain.NewCoin("ugnot", 13)))

	err := (&ZkgmV1{}).verifyTokenOrderV2(cur, channelId, sender, budget, u256.Zero(), order)

	uassert.NoError(t, err)
	uassert.True(t, budget.drained())
	balance := zkgm.GetChannelBalanceV2(ChannelBalanceKeyV2(channelId, u256.Zero(), order.BaseToken, order.QuoteToken))
	uassert.Equal(t, "13", balance.ToString())
}

func TestTokenOrderVerifyVoucherBurnInsufficientBalanceRejected(cur realm, t *testing.T) {
	resetTokenOrderTest(cur)

	sender := testAddress("burn-insuf-sender")
	baseToken := "ibc/burn-insuf"
	uassert.NoError(t, zkgm.MintVoucher(cross(cur), baseToken, baseToken, [32]byte{}, "", "", 0, sender, u256.NewUint(10)))

	order := z.TokenOrderV2{
		Sender:      []byte(sender),
		BaseToken:   []byte(baseToken),
		BaseAmount:  u256.NewUint(50),
		QuoteToken:  []byte("quote"),
		QuoteAmount: u256.NewUint(50),
		Kind:        z.TOKEN_ORDER_KIND_ESCROW,
	}

	err := (&ZkgmV1{}).verifyTokenOrderV2(cur, core.ChannelId(21), sender, newSentCoinBudget(nil), u256.Zero(), order)

	uassert.Error(t, err)
	uassert.Equal(t, int64(10), VoucherBalanceOf(baseToken, address(sender)))
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
		Initializer:    mustEncodeTokenInitializer(z.TokenInitializer{Name: "Gno Token", Symbol: "GNOT", Decimals: 6}),
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

	uassert.Equal(t, "Gno Token", zkgm.VoucherNameOf(ibcDenom))
	uassert.Equal(t, "GNOT", zkgm.VoucherSymbolOf(ibcDenom))
	uassert.Equal(t, 6, zkgm.VoucherDecimalsOf(ibcDenom))
}

func TestTokenOrderExecuteInitializeMalformedInitializerUsesDefaults(cur realm, t *testing.T) {
	resetTokenOrderTest(cur)

	// Initializer is raw bytes that cannot be decoded as TokenInitializer.
	// The protocol must fall back to ibcDenom-derived name/symbol and 0 decimals.
	metaBytes := mustEncodeTokenMetadata(z.TokenMetadata{
		Implementation: []byte("grc20"),
		Initializer:    []byte("not-valid-abi"),
	})
	image := MetadataImage(mustDecodeTokenMetadata(metaBytes))
	ibcDenom := PredictWrappedTokenV2(u256.NewUint(3), 4, []byte("ugnot"), image)
	order := z.TokenOrderV2{
		Sender:      []byte("sender"),
		Receiver:    []byte(testAddress("fallback-receiver")),
		BaseToken:   []byte("ugnot"),
		BaseAmount:  u256.NewUint(50),
		QuoteToken:  []byte(ibcDenom),
		QuoteAmount: u256.NewUint(50),
		Kind:        z.TOKEN_ORDER_KIND_INITIALIZE,
		Metadata:    metaBytes,
	}
	packet := core.NewPacket(cross(cur), core.ChannelId(1), core.ChannelId(4), nil, 0, 0)

	res, err := (&ZkgmV1{}).executeTokenOrderV2(cur, packet, address(testAddress("fallback-relayer")), u256.NewUint(3), order, false)

	uassert.NoError(t, err)
	uassert.True(t, res.Status == core.PacketStatusSuccess)

	uassert.Equal(t, 0, zkgm.VoucherDecimalsOf(ibcDenom))
}

func TestTokenOrderExecuteInitializeEmptyInitializerUsesDefaults(cur realm, t *testing.T) {
	resetTokenOrderTest(cur)

	// Empty Initializer: decimals must default to 0, symbol derived from ibcDenom.
	metaBytes := mustEncodeTokenMetadata(z.TokenMetadata{
		Implementation: []byte("grc20"),
		Initializer:    []byte{},
	})
	image := MetadataImage(mustDecodeTokenMetadata(metaBytes))
	ibcDenom := PredictWrappedTokenV2(u256.NewUint(5), 6, []byte("ugnot"), image)
	order := z.TokenOrderV2{
		Sender:      []byte("sender"),
		Receiver:    []byte(testAddress("empty-init-receiver")),
		BaseToken:   []byte("ugnot"),
		BaseAmount:  u256.NewUint(20),
		QuoteToken:  []byte(ibcDenom),
		QuoteAmount: u256.NewUint(20),
		Kind:        z.TOKEN_ORDER_KIND_INITIALIZE,
		Metadata:    metaBytes,
	}
	packet := core.NewPacket(cross(cur), core.ChannelId(1), core.ChannelId(6), nil, 0, 0)

	res, err := (&ZkgmV1{}).executeTokenOrderV2(cur, packet, address(testAddress("empty-init-relayer")), u256.NewUint(5), order, false)

	uassert.NoError(t, err)
	uassert.True(t, res.Status == core.PacketStatusSuccess)

	uassert.Equal(t, 0, zkgm.VoucherDecimalsOf(ibcDenom))
}

func TestTokenOrderExecuteInitializeMintErrorDoesNotSetOrigin(cur realm, t *testing.T) {
	resetTokenOrderTest(cur)

	metaBytes := mustEncodeTokenMetadata(z.TokenMetadata{
		Implementation: []byte("grc20-invalid-rx"),
		Initializer:    []byte("init-invalid-rx"),
	})

	image := MetadataImage(mustDecodeTokenMetadata(metaBytes))
	ibcDenom := PredictWrappedTokenV2(u256.NewUint(9), 7, []byte("ugnot"), image)
	order := z.TokenOrderV2{
		Sender:      []byte("sender"),
		Receiver:    []byte("not-a-valid-address"),
		BaseToken:   []byte("ugnot"),
		BaseAmount:  u256.NewUint(100),
		QuoteToken:  []byte(ibcDenom),
		QuoteAmount: u256.NewUint(95),
		Kind:        z.TOKEN_ORDER_KIND_INITIALIZE,
		Metadata:    metaBytes,
	}
	packet := core.NewPacket(cross(cur), core.ChannelId(1), core.ChannelId(7), nil, 0, 0)

	_, err := (&ZkgmV1{}).executeTokenOrderV2(cur, packet, address(testAddress("invalid-rx-relayer")), u256.NewUint(9), order, false)
	uassert.ErrorContains(t, err, "invalid address")

	_, ok := zkgm.GetTokenOrigin(ibcDenom)
	uassert.False(t, ok, "mint error must not set token origin")
}

func TestTokenOrderExecuteEscrowMintErrorDoesNotSetOrigin(cur realm, t *testing.T) {
	resetTokenOrderTest(cur)

	path := u256.NewUint(11)
	destChan := uint32(8)
	quoteDenom := PredictWrappedTokenV1(path, destChan, []byte("ugnot"))
	order := z.TokenOrderV2{
		Sender:      []byte("sender"),
		Receiver:    []byte("not-a-valid-address"),
		BaseToken:   []byte("ugnot"),
		BaseAmount:  u256.NewUint(100),
		QuoteToken:  []byte(quoteDenom),
		QuoteAmount: u256.NewUint(95),
		Kind:        z.TOKEN_ORDER_KIND_ESCROW,
	}
	packet := core.NewPacket(cross(cur), core.ChannelId(1), core.ChannelId(destChan), nil, 0, 0)

	_, err := (&ZkgmV1{}).executeTokenOrderV2(cur, packet, address(testAddress("escrow-rx-relayer")), path, order, false)

	uassert.ErrorContains(t, err, "invalid address")
	_, ok := zkgm.GetTokenOrigin(quoteDenom)
	uassert.False(t, ok, "mint error must not set token origin")
}

func TestTokenOrderExecuteInitializeQuoteExceedsBaseReturnsFailure(cur realm, t *testing.T) {
	resetTokenOrderTest(cur)

	metaBytes := mustEncodeTokenMetadata(z.TokenMetadata{
		Implementation: []byte("grc20"),
		Initializer:    []byte("init"),
	})
	image := MetadataImage(mustDecodeTokenMetadata(metaBytes))
	path := u256.NewUint(30)
	const destChan = core.ChannelId(30)
	ibcDenom := PredictWrappedTokenV2(path, uint32(destChan), []byte("ugnot"), image)
	receiver := testAddress("quote-exceeds-rx")

	order := z.TokenOrderV2{
		Sender:      []byte("sender"),
		Receiver:    []byte(receiver),
		BaseToken:   []byte("ugnot"),
		BaseAmount:  u256.NewUint(95),
		QuoteToken:  []byte(ibcDenom),
		QuoteAmount: u256.NewUint(100),
		Kind:        z.TOKEN_ORDER_KIND_INITIALIZE,
		Metadata:    metaBytes,
	}
	packet := core.NewPacket(cross(cur), core.ChannelId(1), destChan, nil, 0, 0)

	res, err := (&ZkgmV1{}).executeTokenOrderV2(cur, packet, address(testAddress("quote-exceeds-rly")), path, order, false)

	uassert.NoError(t, err)
	uassert.True(t, res.Status == core.PacketStatusFailure)
	uassert.Equal(t, int64(0), VoucherBalanceOf(ibcDenom, address(receiver)))
}

func TestTokenOrderExecuteUnescrowChannelBalanceUnderflow(cur realm, t *testing.T) {
	resetTokenOrderTest(cur)

	const destChan = core.ChannelId(40)
	baseToken := []byte("ibc/unescrow-test")
	quoteToken := []byte("ugnot")

	// decreaseChannelBalanceV2 uses (QuoteToken, BaseToken); seed 50 so the 100-withdraw underflows.
	increaseChannelBalanceV2(cross(cur), destChan, u256.Zero(), quoteToken, baseToken, u256.NewUint(50))
	uassert.Equal(t, int64(50), zkgm.GetChannelBalanceV2(ChannelBalanceKeyV2(destChan, u256.Zero(), quoteToken, baseToken)).Int64())

	order := z.TokenOrderV2{
		Sender:      []byte("sender"),
		Receiver:    []byte(testAddress("unescrow-rx")),
		BaseToken:   baseToken,
		BaseAmount:  u256.NewUint(100),
		QuoteToken:  quoteToken,
		QuoteAmount: u256.NewUint(100),
		Kind:        z.TOKEN_ORDER_KIND_UNESCROW,
	}
	packet := core.NewPacket(cross(cur), core.ChannelId(1), destChan, nil, 0, 0)

	_, err := (&ZkgmV1{}).executeTokenOrderV2(cur, packet, address(testAddress("unescrow-rly")), u256.Zero(), order, false)

	uassert.ErrorContains(t, err, "underflow")
}

func TestTokenOrderExecuteEscrowQuoteDenomMismatchReturnsFailure(cur realm, t *testing.T) {
	resetTokenOrderTest(cur)

	receiver := testAddress("escrow-mismatch-rx")
	order := z.TokenOrderV2{
		Sender:      []byte("sender"),
		Receiver:    []byte(receiver),
		BaseToken:   []byte("ugnot"),
		BaseAmount:  u256.NewUint(100),
		QuoteToken:  []byte("ibc/wrong-denom"),
		QuoteAmount: u256.NewUint(95),
		Kind:        z.TOKEN_ORDER_KIND_ESCROW,
	}
	packet := core.NewPacket(cross(cur), core.ChannelId(1), core.ChannelId(50), nil, 0, 0)

	res, err := (&ZkgmV1{}).executeTokenOrderV2(cur, packet, address(testAddress("escrow-mismatch-rly")), u256.Zero(), order, false)

	uassert.NoError(t, err)
	uassert.True(t, res.Status == core.PacketStatusFailure)
	uassert.Equal(t, int64(0), VoucherBalanceOf("ibc/wrong-denom", address(receiver)))
}

func TestTokenOrderExecuteEscrowZeroFeeSkipsRelayerMint(cur realm, t *testing.T) {
	resetTokenOrderTest(cur)

	path := u256.Zero()
	const destChan = core.ChannelId(60)
	relayer := testAddress("zero-fee-relayer")
	receiver := testAddress("zero-fee-receiver")
	quoteDenom := PredictWrappedTokenV1(path, uint32(destChan), []byte("ugnot"))
	order := z.TokenOrderV2{
		Sender:      []byte("sender"),
		Receiver:    []byte(receiver),
		BaseToken:   []byte("ugnot"),
		BaseAmount:  u256.NewUint(100),
		QuoteToken:  []byte(quoteDenom),
		QuoteAmount: u256.NewUint(100), // fee = 0
		Kind:        z.TOKEN_ORDER_KIND_ESCROW,
	}
	packet := core.NewPacket(cross(cur), core.ChannelId(1), destChan, nil, 0, 0)

	res, err := (&ZkgmV1{}).executeTokenOrderV2(cur, packet, address(relayer), path, order, false)

	uassert.NoError(t, err)
	uassert.True(t, res.Status == core.PacketStatusSuccess)
	uassert.Equal(t, int64(100), VoucherBalanceOf(quoteDenom, address(receiver)))
	uassert.Equal(t, int64(0), VoucherBalanceOf(quoteDenom, address(relayer)))
}

func TestTokenOrderExecuteEscrowZeroQuoteSkipsReceiverMint(cur realm, t *testing.T) {
	resetTokenOrderTest(cur)

	path := u256.Zero()
	const destChan = core.ChannelId(61)
	relayer := testAddress("zero-quote-relayer")
	receiver := testAddress("zero-quote-receiver")
	quoteDenom := PredictWrappedTokenV1(path, uint32(destChan), []byte("ugnot"))
	order := z.TokenOrderV2{
		Sender:      []byte("sender"),
		Receiver:    []byte(receiver),
		BaseToken:   []byte("ugnot"),
		BaseAmount:  u256.NewUint(100),
		QuoteToken:  []byte(quoteDenom),
		QuoteAmount: u256.NewUint(0), // receiver gets nothing; all goes to relayer as fee
		Kind:        z.TOKEN_ORDER_KIND_ESCROW,
	}
	packet := core.NewPacket(cross(cur), core.ChannelId(1), destChan, nil, 0, 0)

	res, err := (&ZkgmV1{}).executeTokenOrderV2(cur, packet, address(relayer), path, order, false)

	uassert.NoError(t, err)
	uassert.True(t, res.Status == core.PacketStatusSuccess)
	uassert.Equal(t, int64(0), VoucherBalanceOf(quoteDenom, address(receiver)))
	uassert.Equal(t, int64(100), VoucherBalanceOf(quoteDenom, address(relayer)))
}

func TestTokenOrderExecuteEscrowZeroAmountSkipsBothMints(cur realm, t *testing.T) {
	resetTokenOrderTest(cur)

	path := u256.Zero()
	const destChan = core.ChannelId(62)
	relayer := testAddress("zero-amt-relayer")
	receiver := testAddress("zero-amt-receiver")
	quoteDenom := PredictWrappedTokenV1(path, uint32(destChan), []byte("ugnot"))
	order := z.TokenOrderV2{
		Sender:      []byte("sender"),
		Receiver:    []byte(receiver),
		BaseToken:   []byte("ugnot"),
		BaseAmount:  u256.NewUint(0),
		QuoteToken:  []byte(quoteDenom),
		QuoteAmount: u256.NewUint(0),
		Kind:        z.TOKEN_ORDER_KIND_ESCROW,
	}
	packet := core.NewPacket(cross(cur), core.ChannelId(1), destChan, nil, 0, 0)

	res, err := (&ZkgmV1{}).executeTokenOrderV2(cur, packet, address(relayer), path, order, false)

	uassert.NoError(t, err)
	uassert.True(t, res.Status == core.PacketStatusSuccess)
	uassert.Equal(t, int64(0), VoucherBalanceOf(quoteDenom, address(receiver)))
	uassert.Equal(t, int64(0), VoucherBalanceOf(quoteDenom, address(relayer)))
}

func TestTokenOrderVerifyUnescrowV1PredictionPasses(cur realm, t *testing.T) {
	resetTokenOrderTest(cur)

	const destChan = core.ChannelId(70)
	sender := testAddress("v1-predict-sender")
	quoteToken := []byte("ugnot")
	baseDenom := PredictWrappedTokenV1(u256.Zero(), uint32(destChan), quoteToken)
	origin, err := z.UpdateChannelPath(u256.Zero(), uint32(destChan))
	uassert.NoError(t, err)
	zkgm.SetTokenOrigin(cross(cur), baseDenom, origin)
	uassert.NoError(t, zkgm.MintVoucher(cross(cur), baseDenom, baseDenom, [32]byte{}, "", "", 0, sender, u256.NewUint(100)))

	order := z.TokenOrderV2{
		Sender:      []byte(sender),
		BaseToken:   []byte(baseDenom),
		BaseAmount:  u256.NewUint(50),
		QuoteToken:  quoteToken,
		QuoteAmount: u256.NewUint(50),
		Kind:        z.TOKEN_ORDER_KIND_UNESCROW,
	}

	err = (&ZkgmV1{}).verifyTokenOrderV2(cur, destChan, sender, newSentCoinBudget(nil), u256.Zero(), order)

	uassert.NoError(t, err)
	uassert.Equal(t, int64(50), VoucherBalanceOf(baseDenom, address(sender)))
}

func TestTokenOrderVerifyUnescrowV2PredictionWithImagePasses(cur realm, t *testing.T) {
	resetTokenOrderTest(cur)

	const destChan = core.ChannelId(71)
	sender := testAddress("v2-predict-sender")
	quoteToken := []byte("ugnot")
	image := [32]byte{0x01}
	baseDenom := PredictWrappedTokenV2(u256.Zero(), uint32(destChan), quoteToken, image)
	origin, err := z.UpdateChannelPath(u256.Zero(), uint32(destChan))
	uassert.NoError(t, err)
	zkgm.SetTokenOrigin(cross(cur), baseDenom, origin)
	// Let MintVoucher set the metadata image via getOrCreateVoucherV2 internally.
	// Calling SetMetadataImageOf here and then again via MintVoucher would attempt
	// a double-Set on the same bptree slot (test-realm tainted value), which panics.
	uassert.NoError(t, zkgm.MintVoucher(cross(cur), baseDenom, baseDenom, image, "", "", 0, sender, u256.NewUint(100)))

	order := z.TokenOrderV2{
		Sender:      []byte(sender),
		BaseToken:   []byte(baseDenom),
		BaseAmount:  u256.NewUint(50),
		QuoteToken:  quoteToken,
		QuoteAmount: u256.NewUint(50),
		Kind:        z.TOKEN_ORDER_KIND_UNESCROW,
	}

	err = (&ZkgmV1{}).verifyTokenOrderV2(cur, destChan, sender, newSentCoinBudget(nil), u256.Zero(), order)

	uassert.NoError(t, err)
	uassert.Equal(t, int64(50), VoucherBalanceOf(baseDenom, address(sender)))
}

func TestTokenOrderVerifyUnescrowWrongImageRejected(cur realm, t *testing.T) {
	resetTokenOrderTest(cur)

	const destChan = core.ChannelId(72)
	sender := testAddress("wrong-image-sender")
	quoteToken := []byte("ugnot")
	imageCorrect := [32]byte{0x01}
	imageWrong := [32]byte{0x02}
	baseDenom := PredictWrappedTokenV2(u256.Zero(), uint32(destChan), quoteToken, imageCorrect)
	origin, err := z.UpdateChannelPath(u256.Zero(), uint32(destChan))
	uassert.NoError(t, err)
	zkgm.SetTokenOrigin(cross(cur), baseDenom, origin)
	// imageWrong diverges from imageCorrect used to hash baseDenom — prediction will not match.
	uassert.NoError(t, zkgm.MintVoucher(cross(cur), baseDenom, baseDenom, imageWrong, "", "", 0, sender, u256.NewUint(100)))

	order := z.TokenOrderV2{
		Sender:      []byte(sender),
		BaseToken:   []byte(baseDenom),
		BaseAmount:  u256.NewUint(50),
		QuoteToken:  quoteToken,
		QuoteAmount: u256.NewUint(50),
		Kind:        z.TOKEN_ORDER_KIND_UNESCROW,
	}

	err = (&ZkgmV1{}).verifyTokenOrderV2(cur, destChan, sender, newSentCoinBudget(nil), u256.Zero(), order)

	uassert.ErrorContains(t, err, "invalid token order unescrow")
}

func TestTokenOrderIntentVoucherMarketMakerFillTransfersMakerFunds(cur realm, t *testing.T) {
	resetTokenOrderTest(cur)

	maker := testAddress("v1-intent-maker")
	receiver := testAddress("v1-intent-receiver")
	quoteToken := "ibc/v1-intent-quote"
	uassert.NoError(t, zkgm.MintVoucher(cross(cur), quoteToken, "base", [32]byte{}, "", "", 0, maker, u256.NewUint(30)))
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

	_, ok := zkgm.GetTokenOrigin(quoteToken)
	uassert.False(t, ok, "market-maker fill must not set token origin")

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
	uassert.NoError(t, zkgm.MintVoucher(cross(cur), quoteToken, "base", [32]byte{}, "", "", 0, maker, u256.NewUint(3)))
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

func TestAckConstantConstructorsReturnIndependentInstances(cur realm, t *testing.T) {
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
	assetClassOf = bptree.NewBPTree32()
	zkgm.UpdateImpl(cross(cur), zkgm.NewUpdateRequest(cross(cur), &ZkgmV1{}, nil))
}

func registerImplTestGRC20(cur realm, slug string) (string, *grc20.Token, *grc20.PrivateLedger) {
	token, ledger := grc20.NewToken(0, cur, "Impl Test Token", "IZT", 0)
	grc20reg.Register(cross(cur), token, slug)
	return "gno.land/r/onbloc/unionibc/v1/apps/zkgm/v0/impl." + slug, token, ledger
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

func mustEncodeTokenInitializer(ti z.TokenInitializer) []byte {
	bz, err := z.EncodeTokenInitializer(ti)
	if err != nil {
		panic(err)
	}
	return bz
}

func TestTokenOrderVerifySolveReturnsError(cur realm, t *testing.T) {
	resetTokenOrderTest(cur)

	order := z.TokenOrderV2{
		Sender:      []byte(testAddress("solve-sender")),
		BaseToken:   []byte("ugnot"),
		BaseAmount:  u256.NewUint(1),
		QuoteToken:  []byte("ibc/solve"),
		QuoteAmount: u256.NewUint(1),
		Kind:        z.TOKEN_ORDER_KIND_SOLVE,
	}

	err := (&ZkgmV1{}).verifyTokenOrderV2(cur, core.ChannelId(80), testAddress("solve-sender"), newSentCoinBudget(nil), u256.Zero(), order)

	uassert.ErrorContains(t, err, "not implemented")
}

func TestChannelBalanceKeyV2Isolation(t *testing.T) {
	base := []byte("ugnot")
	quote := []byte("ibc/abc")
	path := u256.Zero()
	chanA := core.ChannelId(1)
	chanB := core.ChannelId(2)

	keyRef := ChannelBalanceKeyV2(chanA, path, base, quote)

	// Each dimension change must produce a distinct key.
	uassert.NotEqual(t, keyRef, ChannelBalanceKeyV2(chanB, path, base, quote))
	uassert.NotEqual(t, keyRef, ChannelBalanceKeyV2(chanA, u256.NewUint(1), base, quote))
	uassert.NotEqual(t, keyRef, ChannelBalanceKeyV2(chanA, path, []byte("atom"), quote))
	uassert.NotEqual(t, keyRef, ChannelBalanceKeyV2(chanA, path, base, []byte("ibc/xyz")))

	// Same inputs must be deterministic.
	uassert.Equal(t, keyRef, ChannelBalanceKeyV2(chanA, path, base, quote))
}

func mustDecodeTokenMetadata(bz []byte) z.TokenMetadata {
	meta, err := z.DecodeTokenMetadata(bz)
	if err != nil {
		panic(err)
	}
	return meta
}

func TestAmountInt64Boundaries(t *testing.T) {
	// 0 → success
	got, err := amountInt64(u256.NewUint(0))
	uassert.NoError(t, err)
	uassert.Equal(t, int64(0), got)

	// MaxInt64 → success
	got, err = amountInt64(u256.NewUint(uint64(math.MaxInt64)))
	uassert.NoError(t, err)
	uassert.Equal(t, int64(math.MaxInt64), got)

	// MaxInt64+1 → overflow (fits uint64 but exceeds int64)
	_, err = amountInt64(u256.NewUint(uint64(math.MaxInt64) + 1))
	uassert.Error(t, err)

	// u256 > 2^64 → overflow (does not fit uint64)
	overUint64 := new(u256.Uint).Add(u256.NewUint(math.MaxUint64), u256.NewUint(1))
	_, err = amountInt64(overUint64)
	uassert.Error(t, err)
}
