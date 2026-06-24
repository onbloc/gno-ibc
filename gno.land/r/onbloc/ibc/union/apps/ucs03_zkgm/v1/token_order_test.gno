package impl

import (
	"bytes"
	"chain"
	"testing"
	"time"

	types "gno.land/p/onbloc/ibc/union/types"

	"gno.land/p/demo/tokens/grc20"
	u256 "gno.land/p/gnoswap/uint256"
	"gno.land/p/nt/uassert/v0"
	z "gno.land/p/onbloc/ibc/union/zkgm"
	tb "gno.land/p/onbloc/ibc/union/zkgm/tokenbucket"
	"gno.land/r/demo/defi/grc20reg"
	core "gno.land/r/onbloc/ibc/union/core"
)

func TestTokenOrderAckFailureUnderflowDoesNotReleaseEscrowedVoucher(cur realm, t *testing.T) {
	v := newTestImpl()

	sender := testAddress("underflow-vouch-snd")
	baseToken := "ibc/v1-underflow-voucher"
	channelId := types.ChannelId(10)
	amount := u256.NewUint(13)
	uassert.NoError(t, v.mintVoucher(0, cur, baseToken, [32]byte{}, "", "", 0, cur.Address().String(), amount))

	order := z.TokenOrderV2{
		Sender:      []byte(sender),
		BaseToken:   []byte(baseToken),
		BaseAmount:  amount,
		QuoteToken:  []byte("quote"),
		QuoteAmount: amount,
		Kind:        z.TOKEN_ORDER_KIND_ESCROW,
	}

	err := v.acknowledgeTokenOrderV2(0, cur, core.NewPacket(channelId, 0, nil, 0), address(""), [32]byte{}, u256.Zero(), order, z.TokenOrderAck{}, false)

	uassert.ErrorContains(t, err, "underflow")
	uassert.Equal(t, int64(0), voucherBalanceOf(baseToken, address(sender)))
	uassert.Equal(t, int64(13), voucherBalanceOf(baseToken, cur.Address()))
}

// A market-maker ack naming the canonical zero burn address burns the escrowed
// voucher instead of releasing it to the maker, mirroring union's burn-address
// branch in acknowledge_token_order_v2 (contract.rs L1030-1042).
func TestTokenOrderAckMarketMakerBurnAddressBurnsEscrowedVoucher(cur realm, t *testing.T) {
	v := newTestImpl()

	baseToken := "ibc/burn-voucher"
	channelId := types.ChannelId(11)
	amount := u256.NewUint(13)

	// Escrowed voucher held by the proxy, plus the channel balance the ack decrease
	// will draw down.
	uassert.NoError(t, v.mintVoucher(0, cur, baseToken, [32]byte{}, "", "", 0, cur.Address().String(), amount))

	order := z.TokenOrderV2{
		Sender:      []byte(testAddress("burn-snd")),
		BaseToken:   []byte(baseToken),
		BaseAmount:  amount,
		QuoteToken:  []byte("quote"),
		QuoteAmount: amount,
		Kind:        z.TOKEN_ORDER_KIND_ESCROW,
	}
	v.increaseChannelBalanceV2(0, cur, channelId, u256.Zero(), order.BaseToken, order.QuoteToken, amount)

	orderAck := z.TokenOrderAck{FillType: fillTypeMarketMaker(), MarketMaker: []byte(z.BURN_ADDRESS)}
	err := v.acknowledgeTokenOrderV2(0, cur, core.NewPacket(channelId, 0, nil, 0), address(""), [32]byte{}, u256.Zero(), order, orderAck, true)

	uassert.NoError(t, err)
	// Burned: drained from the proxy escrow and NOT delivered to the burn address.
	uassert.Equal(t, int64(0), voucherBalanceOf(baseToken, cur.Address()))
	uassert.Equal(t, int64(0), voucherBalanceOf(baseToken, address(z.BURN_ADDRESS)))
}

// For a native base the burn branch cannot destroy supply, so it decrements the
// channel balance (matching union's accounting) and leaves the native locked in
// the proxy — no coins are shipped to the burn address.
func TestTokenOrderAckMarketMakerBurnAddressLocksNative(cur realm, t *testing.T) {
	v := newTestImpl()

	channelId := types.ChannelId(12)
	amount := u256.NewUint(13)
	order := z.TokenOrderV2{
		Sender:      []byte(testAddress("burn-native-snd")),
		BaseToken:   []byte("ugnot"),
		BaseAmount:  amount,
		QuoteToken:  []byte("quote-native"),
		QuoteAmount: amount,
		Kind:        z.TOKEN_ORDER_KIND_ESCROW,
	}
	v.increaseChannelBalanceV2(0, cur, channelId, u256.Zero(), order.BaseToken, order.QuoteToken, amount)

	orderAck := z.TokenOrderAck{FillType: fillTypeMarketMaker(), MarketMaker: []byte(z.BURN_ADDRESS)}
	err := v.acknowledgeTokenOrderV2(0, cur, core.NewPacket(channelId, 0, nil, 0), address(""), [32]byte{}, u256.Zero(), order, orderAck, true)

	uassert.NoError(t, err)
	// Channel balance decremented (escrow no longer backs anything) and the native
	// is recorded as permanently locked — no sendNative to the burn address, no
	// orphaned surplus.
	balance, _ := testStore.GetChannelBalanceV2(ChannelBalanceKeyV2(channelId, u256.Zero(), order.BaseToken, order.QuoteToken))
	uassert.True(t, balance.IsZero())
	locked, ok := testStore.GetLockedNative("ugnot")
	uassert.True(t, ok)
	uassert.Equal(t, "13", locked.ToString())
}

// A token order whose base denom is a foreign GRC20 (registered in grc20reg, not
// a zkgm ibc/ voucher) is rejected on send with a clear "grc20 not yet supported"
// error rather than being misclassified as native and surfacing errCoinMismatch.
func TestTokenOrderEscrowGRC20BaseRejectedWithClearError(cur realm, t *testing.T) {
	v := newTestImpl()

	// grc20reg keys are fqname(callerPkgPath, slug) = pkgpath + "." + slug; the
	// registrant here is this v1 realm, so a sender would reference the token by
	// that full key as the order's base denom.
	const (
		grc20Slug = "foo-grc20-escrow"
		grc20Key  = "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/v1." + grc20Slug
	)
	token, _ := grc20.NewToken(0, cur, "Foo", "FOO", 6)
	grc20reg.Register(cross(cur), token, grc20Slug)

	order := z.TokenOrderV2{
		Sender:      []byte(testAddress("grc20-snd")),
		BaseToken:   []byte(grc20Key),
		BaseAmount:  u256.NewUint(10),
		QuoteToken:  []byte("quote"),
		QuoteAmount: u256.NewUint(10),
		Kind:        z.TOKEN_ORDER_KIND_ESCROW,
	}

	err := v.verifyTokenOrderV2(0, cur, newFunds(nil), types.ChannelId(1), u256.Zero(), order)

	uassert.ErrorContains(t, err, "grc20 token escrow not yet supported")
}

func TestTokenOrderVerifyNativeRequiresSentCoin(cur realm, t *testing.T) {
	v := newTestImpl()
	order := z.TokenOrderV2{
		Sender:     []byte(testAddress("v1-native-sender")),
		BaseToken:  []byte("ugnot"),
		BaseAmount: u256.NewUint(13),
		QuoteToken: []byte("quote"),
		Kind:       z.TOKEN_ORDER_KIND_INITIALIZE,
	}

	err := v.verifyTokenOrderV2(0, cur, newFunds(chain.NewCoins(chain.NewCoin("ugnot", 13))), types.ChannelId(4), u256.Zero(), order)

	uassert.NoError(t, err)
}

func TestTokenOrderVerifyNativeEscrowConsumesFundsAndIncreasesChannelBalance(cur realm, t *testing.T) {
	v := newTestImpl()

	sender := testAddress("native-escrow-sender")
	const channelId = types.ChannelId(20)
	order := z.TokenOrderV2{
		Sender:      []byte(sender),
		BaseToken:   []byte("ugnot"),
		BaseAmount:  u256.NewUint(13),
		QuoteToken:  []byte("quote-native"),
		QuoteAmount: u256.NewUint(13),
		Kind:        z.TOKEN_ORDER_KIND_ESCROW,
	}
	f := newFunds(chain.NewCoins(chain.NewCoin("ugnot", 13)))

	err := v.verifyTokenOrderV2(0, cur, f, channelId, u256.Zero(), order)

	uassert.NoError(t, err)
	uassert.True(t, f.isEmpty())
	balance, _ := testStore.GetChannelBalanceV2(ChannelBalanceKeyV2(channelId, u256.Zero(), order.BaseToken, order.QuoteToken))
	uassert.Equal(t, "13", balance.ToString())
}

func TestTokenOrderVerifyVoucherBurnInsufficientBalanceRejected(cur realm, t *testing.T) {
	v := newTestImpl()

	sender := testAddress("burn-insuf-sender")
	baseToken := "ibc/burn-insuf"
	uassert.NoError(t, v.mintVoucher(0, cur, baseToken, [32]byte{}, "", "", 0, sender, u256.NewUint(10)))

	order := z.TokenOrderV2{
		Sender:      []byte(sender),
		BaseToken:   []byte(baseToken),
		BaseAmount:  u256.NewUint(50),
		QuoteToken:  []byte("quote"),
		QuoteAmount: u256.NewUint(50),
		Kind:        z.TOKEN_ORDER_KIND_ESCROW,
	}

	err := v.verifyTokenOrderV2(0, cur, newFunds(nil), types.ChannelId(21), u256.Zero(), order)

	uassert.Error(t, err)
	uassert.Equal(t, int64(10), voucherBalanceOf(baseToken, address(sender)))
}

func TestTokenOrderVerifyUnescrowNativeRejectedBeforeFundsConsume(cur realm, t *testing.T) {
	v := newTestImpl()
	baseDenom := "native-unescrow"
	testStore.SetTokenOrigin(0, cur, baseDenom, u256.Zero())
	order := z.TokenOrderV2{
		Sender:      []byte(testAddress("native-unescrow")),
		BaseToken:   []byte(baseDenom),
		BaseAmount:  u256.NewUint(13),
		QuoteToken:  []byte("ugnot"),
		QuoteAmount: u256.NewUint(13),
		Kind:        z.TOKEN_ORDER_KIND_UNESCROW,
	}
	f := newFunds(chain.NewCoins(chain.NewCoin(baseDenom, 13)))

	err := v.verifyTokenOrderV2(0, cur, f, types.ChannelId(0), u256.Zero(), order)

	uassert.ErrorContains(t, err, "invalid token order unescrow")
	uassert.False(t, f.isEmpty())
}

// The reference applies the token-order rate limit only on the receive/execute
// side (contract.rs L2184, L2265), never in verify_token_order_v2. This test
// exercises the INITIALIZE mint path, which rate-limits the quote denom.
func TestTokenOrderExecuteAppliesRateLimit(cur realm, t *testing.T) {
	defer enableRateLimit(cur)()
	v := newTestImpl()

	metaBytes := mustEncodeTokenMetadata(z.TokenMetadata{
		Implementation: []byte("grc20"),
		Initializer:    mustEncodeTokenInitializer(z.TokenInitializer{Name: "Gno Token", Symbol: "GNOT", Decimals: 6}),
	})
	image := z.MetadataImage(mustDecodeTokenMetadata(metaBytes))
	ibcDenom := z.PredictWrappedTokenV2(u256.NewUint(7), 5, []byte("ugnot"), image)

	now := u256.NewUint(uint64(time.Now().Unix()))
	bucket, err := tb.New(u256.NewUint(10), u256.NewUint(1), now)
	if err != nil {
		t.Fatal(err)
	}
	testStore.SetTokenBucket(0, cur, ibcDenom, bucket)

	order := z.TokenOrderV2{
		Sender:      []byte("sender"),
		Receiver:    []byte(testAddress("rate-limit-receiver")),
		BaseToken:   []byte("ugnot"),
		BaseAmount:  u256.NewUint(7),
		QuoteToken:  []byte(ibcDenom),
		QuoteAmount: u256.NewUint(7),
		Kind:        z.TOKEN_ORDER_KIND_INITIALIZE,
		Metadata:    metaBytes,
	}
	packet := core.NewPacket(types.ChannelId(1), types.ChannelId(5), nil, 0)

	res, err := v.executeTokenOrderV2(0, cur, packet, address(testAddress("rate-limit-relayer")), nil, [32]byte{}, u256.NewUint(7), order, false)
	uassert.NoError(t, err)
	uassert.True(t, res.Status == types.PacketStatusSuccess)

	// The bucket (capacity 10) is now drained to 3; a second 7-unit fill exceeds it.
	res, err = v.executeTokenOrderV2(0, cur, packet, address(testAddress("rate-limit-relayer")), nil, [32]byte{}, u256.NewUint(7), order, false)
	uassert.NoError(t, err)
	uassert.True(t, res.Status == types.PacketStatusFailure)

	testStore.RemoveTokenBucket(0, cur, ibcDenom)
}

func TestTokenOrderExecuteInitializeMintsVoucherAndSuccessAck(cur realm, t *testing.T) {
	v := newTestImpl()

	metaBytes := mustEncodeTokenMetadata(z.TokenMetadata{
		Implementation: []byte("grc20"),
		Initializer:    mustEncodeTokenInitializer(z.TokenInitializer{Name: "Gno Token", Symbol: "GNOT", Decimals: 6}),
	})
	image := z.MetadataImage(mustDecodeTokenMetadata(metaBytes))
	ibcDenom := z.PredictWrappedTokenV2(u256.NewUint(7), 5, []byte("ugnot"), image)
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
	packet := core.NewPacket(types.ChannelId(1), types.ChannelId(5), nil, 0)

	res, err := v.executeTokenOrderV2(0, cur, packet, address(testAddress("v1-relayer")), nil, [32]byte{}, u256.NewUint(7), order, false)

	uassert.NoError(t, err)
	uassert.True(t, res.Status == types.PacketStatusSuccess)
	assertProtocolAck(t, res.Acknowledgement)

	uassert.Equal(t, int64(95), voucherBalanceOf(ibcDenom, address(order.Receiver)))

	storedImage, ok := testStore.GetMetadataImageOf(ibcDenom)
	uassert.True(t, ok)
	uassert.True(t, image == storedImage)

	origin, ok := testStore.GetTokenOrigin(ibcDenom)
	uassert.True(t, ok)
	uassert.Equal(t, "21474836487", origin.ToString())

	foreignToken, ok := testStore.GetForeignToken(ibcDenom)
	uassert.True(t, ok)
	uassert.Equal(t, "ugnot", string(foreignToken))

	uassert.Equal(t, "Gno Token", voucherNameOf(ibcDenom))
	uassert.Equal(t, "GNOT", voucherSymbolOf(ibcDenom))
	uassert.Equal(t, 6, voucherDecimalsOf(ibcDenom))
}

func TestTokenOrderExecuteInitializeMalformedInitializerUsesDefaults(cur realm, t *testing.T) {
	v := newTestImpl()

	// Initializer is raw bytes that cannot be decoded as TokenInitializer.
	// The protocol must fall back to ibcDenom-derived name/symbol and 0 decimals.
	metaBytes := mustEncodeTokenMetadata(z.TokenMetadata{
		Implementation: []byte("grc20"),
		Initializer:    []byte("not-valid-abi"),
	})
	image := z.MetadataImage(mustDecodeTokenMetadata(metaBytes))
	ibcDenom := z.PredictWrappedTokenV2(u256.NewUint(3), 4, []byte("ugnot"), image)
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
	packet := core.NewPacket(types.ChannelId(1), types.ChannelId(4), nil, 0)

	res, err := v.executeTokenOrderV2(0, cur, packet, address(testAddress("fallback-relayer")), nil, [32]byte{}, u256.NewUint(3), order, false)

	uassert.NoError(t, err)
	uassert.True(t, res.Status == types.PacketStatusSuccess)

	uassert.Equal(t, 0, voucherDecimalsOf(ibcDenom))
}

func TestTokenOrderExecuteInitializeEmptyInitializerUsesDefaults(cur realm, t *testing.T) {
	v := newTestImpl()

	// Empty Initializer: decimals must default to 0, symbol derived from ibcDenom.
	metaBytes := mustEncodeTokenMetadata(z.TokenMetadata{
		Implementation: []byte("grc20"),
		Initializer:    []byte{},
	})
	image := z.MetadataImage(mustDecodeTokenMetadata(metaBytes))
	ibcDenom := z.PredictWrappedTokenV2(u256.NewUint(5), 6, []byte("ugnot"), image)
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
	packet := core.NewPacket(types.ChannelId(1), types.ChannelId(6), nil, 0)

	res, err := v.executeTokenOrderV2(0, cur, packet, address(testAddress("empty-init-relayer")), nil, [32]byte{}, u256.NewUint(5), order, false)

	uassert.NoError(t, err)
	uassert.True(t, res.Status == types.PacketStatusSuccess)

	uassert.Equal(t, 0, voucherDecimalsOf(ibcDenom))
}

func TestTokenOrderExecuteInitializeMintErrorDoesNotSetOrigin(cur realm, t *testing.T) {
	v := newTestImpl()

	metaBytes := mustEncodeTokenMetadata(z.TokenMetadata{
		Implementation: []byte("grc20-invalid-rx"),
		Initializer:    []byte("init-invalid-rx"),
	})

	image := z.MetadataImage(mustDecodeTokenMetadata(metaBytes))
	ibcDenom := z.PredictWrappedTokenV2(u256.NewUint(9), 7, []byte("ugnot"), image)
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
	packet := core.NewPacket(types.ChannelId(1), types.ChannelId(7), nil, 0)

	_, err := v.executeTokenOrderV2(0, cur, packet, address(testAddress("invalid-rx-relayer")), nil, [32]byte{}, u256.NewUint(9), order, false)
	uassert.ErrorContains(t, err, "invalid address")

	_, ok := testStore.GetTokenOrigin(ibcDenom)
	uassert.False(t, ok, "mint error must not set token origin")
	_, ok = testStore.GetForeignToken(ibcDenom)
	uassert.False(t, ok, "mint error must not set foreign token")
	_, ok = testStore.GetMetadataImageOf(ibcDenom)
	uassert.False(t, ok, "mint error must not set metadata image")
}

func TestTokenOrderExecuteEscrowMintErrorDoesNotSetOrigin(cur realm, t *testing.T) {
	v := newTestImpl()

	path := u256.NewUint(11)
	destChan := uint32(8)
	quoteDenom := z.PredictWrappedToken(path, destChan, []byte("ugnot"))
	order := z.TokenOrderV2{
		Sender:      []byte("sender"),
		Receiver:    []byte("not-a-valid-address"),
		BaseToken:   []byte("ugnot"),
		BaseAmount:  u256.NewUint(100),
		QuoteToken:  []byte(quoteDenom),
		QuoteAmount: u256.NewUint(95),
		Kind:        z.TOKEN_ORDER_KIND_ESCROW,
	}
	packet := core.NewPacket(types.ChannelId(1), types.ChannelId(destChan), nil, 0)

	_, err := v.executeTokenOrderV2(0, cur, packet, address(testAddress("escrow-rx-relayer")), nil, [32]byte{}, path, order, false)

	uassert.ErrorContains(t, err, "invalid address")
	_, ok := testStore.GetTokenOrigin(quoteDenom)
	uassert.False(t, ok, "mint error must not set token origin")
}

func TestTokenOrderExecuteInitializeUnderQuoteFallsBackToMarketMaker(cur realm, t *testing.T) {
	v := newTestImpl()

	metaBytes := mustEncodeTokenMetadata(z.TokenMetadata{
		Implementation: []byte("grc20"),
		Initializer:    []byte("init"),
	})
	image := z.MetadataImage(mustDecodeTokenMetadata(metaBytes))
	path := u256.NewUint(30)
	const destChan = types.ChannelId(30)
	ibcDenom := z.PredictWrappedTokenV2(path, uint32(destChan), []byte("ugnot"), image)
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
	packet := core.NewPacket(types.ChannelId(1), destChan, nil, 0)

	// base < quote with a matching quote denom: union does not hard-fail, it falls
	// back to a market-maker fill. No voucher exists yet, so it is maker-only.
	res, err := v.executeTokenOrderV2(0, cur, packet, address(testAddress("quote-exceeds-rly")), nil, [32]byte{}, path, order, false)

	uassert.NoError(t, err)
	uassert.True(t, res.Status == types.PacketStatusSuccess)
	uassert.Equal(t, string(z.ACK_ERR_ONLY_MAKER), string(res.Acknowledgement))
	uassert.Equal(t, int64(0), voucherBalanceOf(ibcDenom, address(receiver)))
}

func TestTokenOrderExecuteUnescrowChannelBalanceUnderflow(cur realm, t *testing.T) {
	v := newTestImpl()

	const destChan = types.ChannelId(40)
	baseToken := []byte("ibc/unescrow-test")
	quoteToken := []byte("ugnot")

	// decreaseChannelBalanceV2 uses (QuoteToken, BaseToken); seed 50 so the 100-withdraw underflows.
	v.increaseChannelBalanceV2(0, cur, destChan, u256.Zero(), quoteToken, baseToken, u256.NewUint(50))
	seeded, _ := testStore.GetChannelBalanceV2(ChannelBalanceKeyV2(destChan, u256.Zero(), quoteToken, baseToken))
	uassert.Equal(t, int64(50), seeded.Int64())

	order := z.TokenOrderV2{
		Sender:      []byte("sender"),
		Receiver:    []byte(testAddress("unescrow-rx")),
		BaseToken:   baseToken,
		BaseAmount:  u256.NewUint(100),
		QuoteToken:  quoteToken,
		QuoteAmount: u256.NewUint(100),
		Kind:        z.TOKEN_ORDER_KIND_UNESCROW,
	}
	packet := core.NewPacket(types.ChannelId(1), destChan, nil, 0)

	_, err := v.executeTokenOrderV2(0, cur, packet, address(testAddress("unescrow-rly")), nil, [32]byte{}, u256.Zero(), order, false)

	uassert.ErrorContains(t, err, "underflow")
}

func TestTokenOrderExecuteEscrowQuoteDenomMismatchFallsBackToMarketMaker(cur realm, t *testing.T) {
	v := newTestImpl()

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
	packet := core.NewPacket(types.ChannelId(1), types.ChannelId(50), nil, 0)

	// quote != predicted wrapped denom: the order falls back to a market-maker
	// fill rather than hard-failing. No voucher exists, so it is maker-only.
	res, err := v.executeTokenOrderV2(0, cur, packet, address(testAddress("escrow-mismatch-rly")), nil, [32]byte{}, u256.Zero(), order, false)

	uassert.NoError(t, err)
	uassert.True(t, res.Status == types.PacketStatusSuccess)
	uassert.Equal(t, string(z.ACK_ERR_ONLY_MAKER), string(res.Acknowledgement))
	uassert.Equal(t, int64(0), voucherBalanceOf("ibc/wrong-denom", address(receiver)))
}

func TestTokenOrderExecuteEscrowZeroFeeSkipsRelayerMint(cur realm, t *testing.T) {
	v := newTestImpl()

	path := u256.Zero()
	const destChan = types.ChannelId(60)
	relayer := testAddress("zero-fee-relayer")
	receiver := testAddress("zero-fee-receiver")
	quoteDenom := z.PredictWrappedToken(path, uint32(destChan), []byte("ugnot"))
	order := z.TokenOrderV2{
		Sender:      []byte("sender"),
		Receiver:    []byte(receiver),
		BaseToken:   []byte("ugnot"),
		BaseAmount:  u256.NewUint(100),
		QuoteToken:  []byte(quoteDenom),
		QuoteAmount: u256.NewUint(100), // fee = 0
		Kind:        z.TOKEN_ORDER_KIND_ESCROW,
	}
	packet := core.NewPacket(types.ChannelId(1), destChan, nil, 0)

	res, err := v.executeTokenOrderV2(0, cur, packet, address(relayer), nil, [32]byte{}, path, order, false)

	uassert.NoError(t, err)
	uassert.True(t, res.Status == types.PacketStatusSuccess)
	uassert.Equal(t, int64(100), voucherBalanceOf(quoteDenom, address(receiver)))
	uassert.Equal(t, int64(0), voucherBalanceOf(quoteDenom, address(relayer)))

	_, ok := testStore.GetTokenOrigin(quoteDenom)
	uassert.False(t, ok, "escrow protocol fill must not set token origin")
	_, ok = testStore.GetForeignToken(quoteDenom)
	uassert.False(t, ok, "escrow protocol fill must not set foreign token")
	_, ok = testStore.GetMetadataImageOf(quoteDenom)
	uassert.False(t, ok, "escrow protocol fill must not set metadata image")
}

func TestTokenOrderExecuteEscrowZeroQuoteSkipsReceiverMint(cur realm, t *testing.T) {
	v := newTestImpl()

	path := u256.Zero()
	const destChan = types.ChannelId(61)
	relayer := testAddress("zero-quote-relayer")
	receiver := testAddress("zero-quote-receiver")
	quoteDenom := z.PredictWrappedToken(path, uint32(destChan), []byte("ugnot"))
	order := z.TokenOrderV2{
		Sender:      []byte("sender"),
		Receiver:    []byte(receiver),
		BaseToken:   []byte("ugnot"),
		BaseAmount:  u256.NewUint(100),
		QuoteToken:  []byte(quoteDenom),
		QuoteAmount: u256.NewUint(0), // receiver gets nothing; all goes to relayer as fee
		Kind:        z.TOKEN_ORDER_KIND_ESCROW,
	}
	packet := core.NewPacket(types.ChannelId(1), destChan, nil, 0)

	res, err := v.executeTokenOrderV2(0, cur, packet, address(relayer), nil, [32]byte{}, path, order, false)

	uassert.NoError(t, err)
	uassert.True(t, res.Status == types.PacketStatusSuccess)
	uassert.Equal(t, int64(0), voucherBalanceOf(quoteDenom, address(receiver)))
	uassert.Equal(t, int64(100), voucherBalanceOf(quoteDenom, address(relayer)))
}

func TestTokenOrderExecuteEscrowZeroAmountSkipsBothMints(cur realm, t *testing.T) {
	v := newTestImpl()

	path := u256.Zero()
	const destChan = types.ChannelId(62)
	relayer := testAddress("zero-amt-relayer")
	receiver := testAddress("zero-amt-receiver")
	quoteDenom := z.PredictWrappedToken(path, uint32(destChan), []byte("ugnot"))
	order := z.TokenOrderV2{
		Sender:      []byte("sender"),
		Receiver:    []byte(receiver),
		BaseToken:   []byte("ugnot"),
		BaseAmount:  u256.NewUint(0),
		QuoteToken:  []byte(quoteDenom),
		QuoteAmount: u256.NewUint(0),
		Kind:        z.TOKEN_ORDER_KIND_ESCROW,
	}
	packet := core.NewPacket(types.ChannelId(1), destChan, nil, 0)

	res, err := v.executeTokenOrderV2(0, cur, packet, address(relayer), nil, [32]byte{}, path, order, false)

	uassert.NoError(t, err)
	uassert.True(t, res.Status == types.PacketStatusSuccess)
	uassert.Equal(t, int64(0), voucherBalanceOf(quoteDenom, address(receiver)))
	uassert.Equal(t, int64(0), voucherBalanceOf(quoteDenom, address(relayer)))
}

func TestTokenOrderVerifyUnescrowV1PredictionPasses(cur realm, t *testing.T) {
	v := newTestImpl()

	const destChan = types.ChannelId(70)
	sender := testAddress("v1-predict-sender")
	quoteToken := []byte("ugnot")
	baseDenom := z.PredictWrappedToken(u256.Zero(), uint32(destChan), quoteToken)
	origin, err := z.UpdateChannelPath(u256.Zero(), uint32(destChan))
	uassert.NoError(t, err)
	testStore.SetTokenOrigin(0, cur, baseDenom, origin)
	uassert.NoError(t, v.mintVoucher(0, cur, baseDenom, [32]byte{}, "", "", 0, sender, u256.NewUint(100)))

	order := z.TokenOrderV2{
		Sender:      []byte(sender),
		BaseToken:   []byte(baseDenom),
		BaseAmount:  u256.NewUint(50),
		QuoteToken:  quoteToken,
		QuoteAmount: u256.NewUint(50),
		Kind:        z.TOKEN_ORDER_KIND_UNESCROW,
	}

	testing.SetRealm(testing.NewUserRealm(address(sender)))
	err = v.verifyTokenOrderV2X(cross(cur), newFunds(nil), destChan, u256.Zero(), order)

	uassert.NoError(t, err)
	uassert.Equal(t, int64(50), voucherBalanceOf(baseDenom, address(sender)))
}

func TestTokenOrderVerifyUnescrowV2PredictionWithImagePasses(cur realm, t *testing.T) {
	v := newTestImpl()

	const destChan = types.ChannelId(71)
	sender := testAddress("v2-predict-sender")
	quoteToken := []byte("ugnot")
	image := [32]byte{0x01}
	baseDenom := z.PredictWrappedTokenV2(u256.Zero(), uint32(destChan), quoteToken, image)
	origin, err := z.UpdateChannelPath(u256.Zero(), uint32(destChan))
	uassert.NoError(t, err)
	testStore.SetTokenOrigin(0, cur, baseDenom, origin)
	testStore.SetMetadataImageOf(0, cur, baseDenom, image)
	uassert.NoError(t, v.mintVoucher(0, cur, baseDenom, image, "", "", 0, sender, u256.NewUint(100)))

	order := z.TokenOrderV2{
		Sender:      []byte(sender),
		BaseToken:   []byte(baseDenom),
		BaseAmount:  u256.NewUint(50),
		QuoteToken:  quoteToken,
		QuoteAmount: u256.NewUint(50),
		Kind:        z.TOKEN_ORDER_KIND_UNESCROW,
	}

	testing.SetRealm(testing.NewUserRealm(address(sender)))
	err = v.verifyTokenOrderV2X(cross(cur), newFunds(nil), destChan, u256.Zero(), order)

	uassert.NoError(t, err)
	uassert.Equal(t, int64(50), voucherBalanceOf(baseDenom, address(sender)))
}

func TestTokenOrderVerifyUnescrowWrongImageRejected(cur realm, t *testing.T) {
	v := newTestImpl()

	const destChan = types.ChannelId(72)
	sender := testAddress("wrong-image-sender")
	quoteToken := []byte("ugnot")
	imageCorrect := [32]byte{0x01}
	imageWrong := [32]byte{0x02}
	baseDenom := z.PredictWrappedTokenV2(u256.Zero(), uint32(destChan), quoteToken, imageCorrect)
	origin, err := z.UpdateChannelPath(u256.Zero(), uint32(destChan))
	uassert.NoError(t, err)
	testStore.SetTokenOrigin(0, cur, baseDenom, origin)
	testStore.SetMetadataImageOf(0, cur, baseDenom, imageWrong)
	// imageWrong diverges from imageCorrect used to hash baseDenom — prediction will not match.
	uassert.NoError(t, v.mintVoucher(0, cur, baseDenom, imageWrong, "", "", 0, sender, u256.NewUint(100)))

	order := z.TokenOrderV2{
		Sender:      []byte(sender),
		BaseToken:   []byte(baseDenom),
		BaseAmount:  u256.NewUint(50),
		QuoteToken:  quoteToken,
		QuoteAmount: u256.NewUint(50),
		Kind:        z.TOKEN_ORDER_KIND_UNESCROW,
	}

	testing.SetRealm(testing.NewUserRealm(address(sender)))
	err = v.verifyTokenOrderV2X(cross(cur), newFunds(nil), destChan, u256.Zero(), order)

	uassert.ErrorContains(t, err, "invalid token order unescrow")
}

func TestTokenOrderIntentVoucherMarketMakerFillTransfersMakerFunds(cur realm, t *testing.T) {
	v := newTestImpl()

	maker := testAddress("v1-intent-maker")
	receiver := testAddress("v1-intent-receiver")
	quoteToken := "ibc/v1-intent-quote"
	uassert.NoError(t, v.mintVoucher(0, cur, quoteToken, [32]byte{}, "", "", 0, maker, u256.NewUint(30)))
	order := z.TokenOrderV2{
		Sender:      []byte("sender"),
		Receiver:    []byte(receiver),
		BaseToken:   []byte("ugnot"),
		BaseAmount:  u256.NewUint(100),
		QuoteToken:  []byte(quoteToken),
		QuoteAmount: u256.NewUint(12),
		Kind:        z.TOKEN_ORDER_KIND_ESCROW,
	}
	packet := core.NewPacket(types.ChannelId(1), types.ChannelId(5), nil, 0)

	res, err := v.executeTokenOrderV2(0, cur, packet, address(maker), nil, [32]byte{}, u256.Zero(), order, true)

	uassert.NoError(t, err)
	uassert.True(t, res.Status == types.PacketStatusSuccess)
	assertMarketMakerAck(t, res.Acknowledgement, maker)
	uassert.Equal(t, int64(18), voucherBalanceOf(quoteToken, address(maker)))
	uassert.Equal(t, int64(12), voucherBalanceOf(quoteToken, address(receiver)))

	_, ok := testStore.GetTokenOrigin(quoteToken)
	uassert.False(t, ok, "market-maker fill must not set token origin")

	balance, hasBalance := testStore.GetChannelBalanceV2(ChannelBalanceKeyV2(types.ChannelId(5), u256.Zero(), order.BaseToken, order.QuoteToken))
	uassert.True(t, !hasBalance || balance.IsZero())
}

func TestTokenOrderIntentUnknownQuoteReturnsOnlyMaker(cur realm, t *testing.T) {
	v := newTestImpl()

	order := z.TokenOrderV2{
		Receiver:    []byte(testAddress("int-unknown-rx")),
		BaseToken:   []byte("ugnot"),
		BaseAmount:  u256.NewUint(10),
		QuoteToken:  []byte("ugnot"),
		QuoteAmount: u256.NewUint(10),
		Kind:        z.TOKEN_ORDER_KIND_UNESCROW,
	}
	packet := core.NewPacket(types.ChannelId(1), types.ChannelId(5), nil, 0)

	res, err := v.executeTokenOrderV2(0, cur, packet, address(testAddress("v1-intent-maker")), nil, [32]byte{}, u256.Zero(), order, true)

	uassert.NoError(t, err)
	uassert.True(t, res.Status == types.PacketStatusSuccess)
	uassert.True(t, bytes.Equal(z.ACK_ERR_ONLY_MAKER, res.Acknowledgement))
}

func TestTokenOrderIntentInsufficientMakerBalanceReturnsOnlyMaker(cur realm, t *testing.T) {
	v := newTestImpl()

	maker := testAddress("v1-intent-poor-maker")
	receiver := testAddress("int-poor-rx")
	quoteToken := "ibc/v1-intent-poor"
	uassert.NoError(t, v.mintVoucher(0, cur, quoteToken, [32]byte{}, "", "", 0, maker, u256.NewUint(3)))
	order := z.TokenOrderV2{
		Receiver:    []byte(receiver),
		BaseToken:   []byte("ugnot"),
		BaseAmount:  u256.NewUint(10),
		QuoteToken:  []byte(quoteToken),
		QuoteAmount: u256.NewUint(9),
		Kind:        z.TOKEN_ORDER_KIND_ESCROW,
	}
	packet := core.NewPacket(types.ChannelId(1), types.ChannelId(5), nil, 0)

	res, err := v.executeTokenOrderV2(0, cur, packet, address(maker), nil, [32]byte{}, u256.Zero(), order, true)

	uassert.NoError(t, err)
	uassert.True(t, res.Status == types.PacketStatusSuccess)
	uassert.True(t, bytes.Equal(z.ACK_ERR_ONLY_MAKER, res.Acknowledgement))
	uassert.Equal(t, int64(3), voucherBalanceOf(quoteToken, address(maker)))
	uassert.Equal(t, int64(0), voucherBalanceOf(quoteToken, address(receiver)))
}

func TestTokenOrderVerifySolveReturnsError(cur realm, t *testing.T) {
	v := newTestImpl()

	order := z.TokenOrderV2{
		Sender:      []byte(testAddress("solve-sender")),
		BaseToken:   []byte("ugnot"),
		BaseAmount:  u256.NewUint(1),
		QuoteToken:  []byte("ibc/solve"),
		QuoteAmount: u256.NewUint(1),
		Kind:        z.TOKEN_ORDER_KIND_SOLVE,
	}

	err := v.verifyTokenOrderV2(0, cur, newFunds(nil), types.ChannelId(80), u256.Zero(), order)

	uassert.ErrorContains(t, err, "not implemented")
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

func marketMakerAck(marketMaker string) z.TokenOrderAck {
	return z.TokenOrderAck{
		FillType:    fillTypeMarketMaker(),
		MarketMaker: []byte(marketMaker),
	}
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

func mustDecodeTokenMetadata(bz []byte) z.TokenMetadata {
	meta, err := z.DecodeTokenMetadata(bz)
	if err != nil {
		panic(err)
	}
	return meta
}
