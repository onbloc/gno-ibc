package v1

import (
	"bytes"
	"chain"
	"chain/banker"
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
	uassert.NoError(t, v.mintVoucher(0, cur, baseToken, [32]byte{}, "", "", 0, cur.Address(), amount))

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
	uassert.NoError(t, v.mintVoucher(0, cur, baseToken, [32]byte{}, "", "", 0, cur.Address(), amount))

	order := z.TokenOrderV2{
		Sender:      []byte(testAddress("burn-snd")),
		BaseToken:   []byte(baseToken),
		BaseAmount:  amount,
		QuoteToken:  []byte("quote"),
		QuoteAmount: amount,
		Kind:        z.TOKEN_ORDER_KIND_ESCROW,
	}
	v.increaseChannelBalanceV2(0, cur, channelId, u256.Zero(), order.BaseToken, order.QuoteToken, amount.Int64())

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
	v.increaseChannelBalanceV2(0, cur, channelId, u256.Zero(), order.BaseToken, order.QuoteToken, amount.Int64())

	orderAck := z.TokenOrderAck{FillType: fillTypeMarketMaker(), MarketMaker: []byte(z.BURN_ADDRESS)}
	err := v.acknowledgeTokenOrderV2(0, cur, core.NewPacket(channelId, 0, nil, 0), address(""), [32]byte{}, u256.Zero(), order, orderAck, true)

	uassert.NoError(t, err)
	// Channel balance decremented (escrow no longer backs anything) and the native
	// is recorded as permanently locked — no sendNative to the burn address, no
	// orphaned surplus.
	balance, _ := testStore.GetChannelBalanceV2(ChannelBalanceKeyV2(channelId, u256.Zero(), order.BaseToken, order.QuoteToken))
	uassert.True(t, balance.IsZero())
	locked, ok := testStore.GetLockedTokenAmount("ugnot")
	uassert.True(t, ok)
	uassert.Equal(t, "13", locked.ToString())
}

// A registered grc20 base cannot be supply-burned either (zkgm holds no mint/burn
// capability over it, only a Teller), so the burn branch locks it exactly like
// native: channel balance decremented, balance left parked at the proxy, and the
// amount recorded in lockedTokenAmounts.
func TestTokenOrderAckMarketMakerBurnAddressLocksGRC20(cur realm, t *testing.T) {
	testStore = newMockStore()
	v := newTestImpl()

	const (
		grc20Slug = "burn-lock-grc20"
		grc20Key  = "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/v1." + grc20Slug
	)
	token, ledger := grc20.NewToken(0, cur, "Foo", "FOO", 6)
	grc20reg.Register(cross(cur), token, grc20Slug)

	// Custody already sits at the proxy address, mirroring what a prior escrow
	// would have left behind.
	uassert.NoError(t, ledger.Mint(cur.Address(), 13))

	channelId := types.ChannelId(13)
	amount := u256.NewUint(13)
	order := z.TokenOrderV2{
		Sender:      []byte(testAddress("burn-grc20-snd")),
		BaseToken:   []byte(grc20Key),
		BaseAmount:  amount,
		QuoteToken:  []byte("quote-grc20"),
		QuoteAmount: amount,
		Kind:        z.TOKEN_ORDER_KIND_ESCROW,
	}
	v.increaseChannelBalanceV2(0, cur, channelId, u256.Zero(), order.BaseToken, order.QuoteToken, amount.Int64())

	orderAck := z.TokenOrderAck{FillType: fillTypeMarketMaker(), MarketMaker: []byte(z.BURN_ADDRESS)}
	err := v.acknowledgeTokenOrderV2(0, cur, core.NewPacket(channelId, 0, nil, 0), address(""), [32]byte{}, u256.Zero(), order, orderAck, true)

	uassert.NoError(t, err)
	balance, _ := testStore.GetChannelBalanceV2(ChannelBalanceKeyV2(channelId, u256.Zero(), order.BaseToken, order.QuoteToken))
	uassert.True(t, balance.IsZero())
	locked, ok := testStore.GetLockedTokenAmount(grc20Key)
	uassert.True(t, ok)
	uassert.Equal(t, "13", locked.ToString())
	uassert.Equal(t, int64(13), token.BalanceOf(cur.Address()))
}

// A token order whose base denom is a foreign GRC20 (registered in grc20reg, not
// a zkgm ibc/ voucher) pulls custody via TransferFrom once the sender has
// pre-approved this realm, exactly like a real allowance-gated ERC20 pull.
func TestLocalTokenEscrowGRC20PullsApprovedFunds(cur realm, t *testing.T) {
	testStore = newMockStore()
	v := newTestImpl()

	// grc20reg keys are fqname(callerPkgPath, slug) = pkgpath + "." + slug; the
	// registrant here is this v1 realm, so a sender would reference the token by
	// that full key as the order's base denom.
	const (
		grc20Slug = "foo-grc20-escrow"
		grc20Key  = "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/v1." + grc20Slug
	)
	token, ledger := grc20.NewToken(0, cur, "Foo", "FOO", 6)
	grc20reg.Register(cross(cur), token, grc20Slug)

	sender := address(testAddress("grc20-escrow-sender"))
	uassert.NoError(t, ledger.Mint(sender, 10))
	uassert.NoError(t, ledger.Approve(sender, cur.Address(), 6))

	uassert.NoError(t, v.localTokenEscrow(0, cur, grc20Key, sender, newFunds(nil), u256.NewUint(6)))
	uassert.Equal(t, int64(6), token.BalanceOf(cur.Address()))
	uassert.Equal(t, int64(4), token.BalanceOf(sender))
}

// Without a prior Approve, TransferFrom has no allowance to spend and the
// escrow is rejected instead of silently falling back to native handling.
func TestLocalTokenEscrowGRC20WithoutApprovalRejected(cur realm, t *testing.T) {
	testStore = newMockStore()
	v := newTestImpl()

	const (
		grc20Slug = "foo-grc20-escrow-noapprove"
		grc20Key  = "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/v1." + grc20Slug
	)
	token, ledger := grc20.NewToken(0, cur, "Foo", "FOO", 6)
	grc20reg.Register(cross(cur), token, grc20Slug)

	sender := address(testAddress("grc20-noapprove-snd"))
	uassert.NoError(t, ledger.Mint(sender, 10))

	err := v.localTokenEscrow(0, cur, grc20Key, sender, newFunds(nil), u256.NewUint(6))

	uassert.ErrorContains(t, err, "insufficient allowance")
	uassert.Equal(t, int64(10), token.BalanceOf(sender))
}

// An allowance covering the amount does not bypass the sender's actual
// balance: TransferFrom checks balance before spending the allowance.
func TestLocalTokenEscrowGRC20InsufficientBalanceRejected(cur realm, t *testing.T) {
	testStore = newMockStore()
	v := newTestImpl()

	const (
		grc20Slug = "foo-grc20-escrow-short"
		grc20Key  = "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/v1." + grc20Slug
	)
	token, ledger := grc20.NewToken(0, cur, "Foo", "FOO", 6)
	grc20reg.Register(cross(cur), token, grc20Slug)

	sender := address(testAddress("grc20-short-snd"))
	uassert.NoError(t, ledger.Mint(sender, 4))
	uassert.NoError(t, ledger.Approve(sender, cur.Address(), 6))

	err := v.localTokenEscrow(0, cur, grc20Key, sender, newFunds(nil), u256.NewUint(6))

	uassert.ErrorContains(t, err, "insufficient balance")
	uassert.Equal(t, int64(4), token.BalanceOf(sender))
}

// localTokenUnescrow releases a registered grc20 token straight from proxy
// custody: no allowance needed, since RealmTeller.Transfer moves the proxy's
// own balance rather than pulling from someone else's.
func TestLocalTokenUnescrowGRC20ReleasesProxyFunds(cur realm, t *testing.T) {
	testStore = newMockStore()
	v := newTestImpl()

	const (
		grc20Slug = "foo-grc20-unescrow"
		grc20Key  = "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/v1." + grc20Slug
	)
	token, ledger := grc20.NewToken(0, cur, "Foo", "FOO", 6)
	grc20reg.Register(cross(cur), token, grc20Slug)

	// Proxy custody is simulated by minting straight to this realm's own
	// address, mirroring how escrow leaves funds parked at cur.Address().
	uassert.NoError(t, ledger.Mint(cur.Address(), 10))

	recipient := address(testAddress("grc20-unescrow-rx"))
	uassert.NoError(t, v.localTokenUnescrow(0, cur, grc20Key, recipient, u256.NewUint(6)))

	uassert.Equal(t, int64(4), token.BalanceOf(cur.Address()))
	uassert.Equal(t, int64(6), token.BalanceOf(recipient))
}

// A drained (or never-funded) proxy balance rejects the release instead of
// silently falling back to native handling.
func TestLocalTokenUnescrowGRC20InsufficientBalanceRejected(cur realm, t *testing.T) {
	testStore = newMockStore()
	v := newTestImpl()

	const (
		grc20Slug = "foo-grc20-unescrow-short"
		grc20Key  = "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/v1." + grc20Slug
	)
	token, ledger := grc20.NewToken(0, cur, "Foo", "FOO", 6)
	grc20reg.Register(cross(cur), token, grc20Slug)

	uassert.NoError(t, ledger.Mint(cur.Address(), 4))

	recipient := address(testAddress("grc20-unesc-short-rx"))
	err := v.localTokenUnescrow(0, cur, grc20Key, recipient, u256.NewUint(6))

	uassert.ErrorContains(t, err, "insufficient balance")
	uassert.Equal(t, int64(4), token.BalanceOf(cur.Address()))
	uassert.Equal(t, int64(0), token.BalanceOf(recipient))
}

// verifyMetadataDecimals guards an INITIALIZE order's declared metadata
// decimals against the locally-known ground truth for its base denom: a
// registered grc20's real decimals, or a held voucher's recorded
// OriginDecimals when forwarding it onward. Native (or otherwise unknown)
// denoms are out of scope.

func TestVerifyMetadataDecimalsSkipsUnknownDenom(cur realm, t *testing.T) {
	v := newTestImpl()

	// "ugnot" is neither a registered grc20 nor a held voucher, so the check
	// is a no-op regardless of what the (here nonsense) metadata claims.
	uassert.NoError(t, v.verifyMetadataDecimals("ugnot", []byte("not even valid metadata")))
}

func TestVerifyMetadataDecimalsRejectsGRC20Mismatch(cur realm, t *testing.T) {
	testStore = newMockStore()
	v := newTestImpl()

	const (
		grc20Slug = "foo-grc20-meta-mismatch"
		grc20Key  = "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/v1." + grc20Slug
	)
	token, _ := grc20.NewToken(0, cur, "Foo", "FOO", 6)
	grc20reg.Register(cross(cur), token, grc20Slug)

	metaBytes := mustEncodeTokenMetadata(z.TokenMetadata{
		Implementation: zkgmERC20Impl,
		Initializer:    mustEncodeTokenInitializer(z.TokenInitializer{Name: "Foo", Symbol: "FOO", Decimals: 18}),
	})

	err := v.verifyMetadataDecimals(grc20Key, metaBytes)

	uassert.ErrorContains(t, err, "metadata decimals do not match")
}

func TestVerifyMetadataDecimalsAcceptsGRC20Match(cur realm, t *testing.T) {
	testStore = newMockStore()
	v := newTestImpl()

	const (
		grc20Slug = "foo-grc20-meta-match"
		grc20Key  = "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/v1." + grc20Slug
	)
	token, _ := grc20.NewToken(0, cur, "Foo", "FOO", 6)
	grc20reg.Register(cross(cur), token, grc20Slug)

	metaBytes := mustEncodeTokenMetadata(z.TokenMetadata{
		Implementation: zkgmERC20Impl,
		Initializer:    mustEncodeTokenInitializer(z.TokenInitializer{Name: "Foo", Symbol: "FOO", Decimals: 6}),
	})

	uassert.NoError(t, v.verifyMetadataDecimals(grc20Key, metaBytes))
}

func TestVerifyMetadataDecimalsRejectsVoucherForwardMismatch(cur realm, t *testing.T) {
	testStore = newMockStore()
	v := newTestImpl()

	ibcDenom := "ibc/voucher-meta-mismatch"
	uassert.NoError(t, v.mintVoucher(0, cur, ibcDenom, [32]byte{}, "Foo", "FOO", 18, cur.Address(), scaledWire(20, 18)))

	metaBytes := mustEncodeTokenMetadata(z.TokenMetadata{
		Implementation: zkgmERC20Impl,
		Initializer:    mustEncodeTokenInitializer(z.TokenInitializer{Name: "Foo", Symbol: "FOO", Decimals: 6}),
	})

	err := v.verifyMetadataDecimals(ibcDenom, metaBytes)

	uassert.ErrorContains(t, err, "metadata decimals do not match")
}

func TestVerifyMetadataDecimalsAcceptsVoucherForwardMatch(cur realm, t *testing.T) {
	testStore = newMockStore()
	v := newTestImpl()

	ibcDenom := "ibc/voucher-meta-match"
	uassert.NoError(t, v.mintVoucher(0, cur, ibcDenom, [32]byte{}, "Foo", "FOO", 18, cur.Address(), scaledWire(20, 18)))

	metaBytes := mustEncodeTokenMetadata(z.TokenMetadata{
		Implementation: zkgmERC20Impl,
		Initializer:    mustEncodeTokenInitializer(z.TokenInitializer{Name: "Foo", Symbol: "FOO", Decimals: 18}),
	})

	uassert.NoError(t, v.verifyMetadataDecimals(ibcDenom, metaBytes))
}

// verifyTokenOrderV2 wires the check in ahead of any escrow side effect, so a
// mismatched INITIALIZE order is rejected before it ever reaches localTokenEscrow.
func TestTokenOrderVerifyGRC20InitializeDecimalsMismatchRejectedBeforeEscrow(cur realm, t *testing.T) {
	testStore = newMockStore()
	v := newTestImpl()

	const (
		grc20Slug = "foo-grc20-verify-mismatch"
		grc20Key  = "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/v1." + grc20Slug
	)
	token, ledger := grc20.NewToken(0, cur, "Foo", "FOO", 6)
	grc20reg.Register(cross(cur), token, grc20Slug)

	sender := address(testAddress("grc20-verify-mis-snd"))
	uassert.NoError(t, ledger.Mint(sender, 40))
	uassert.NoError(t, ledger.Approve(sender, cur.Address(), 40))

	metaBytes := mustEncodeTokenMetadata(z.TokenMetadata{
		Implementation: zkgmERC20Impl,
		Initializer:    mustEncodeTokenInitializer(z.TokenInitializer{Name: "Foo", Symbol: "FOO", Decimals: 18}),
	})

	order := z.TokenOrderV2{
		Sender:      []byte(sender),
		BaseToken:   []byte(grc20Key),
		BaseAmount:  u256.NewUint(40),
		QuoteToken:  []byte("remote-foo"),
		QuoteAmount: u256.NewUint(40),
		Kind:        z.TOKEN_ORDER_KIND_INITIALIZE,
		Metadata:    metaBytes,
	}

	testing.SetRealm(testing.NewUserRealm(address(sender)))
	err := v.verifyTokenOrderV2X(cross(cur), newFunds(nil), types.ChannelId(1), u256.Zero(), order)

	uassert.ErrorContains(t, err, "metadata decimals do not match")
	// Escrow never ran: the sender's full minted balance is untouched.
	uassert.Equal(t, int64(40), token.BalanceOf(sender))
}

// verifyTokenOrderV2 applies the same guard when the base is a held voucher
// being forwarded onward, rejecting before transferVoucher ever runs.
func TestTokenOrderVerifyVoucherInitializeDecimalsMismatchRejectedBeforeEscrow(cur realm, t *testing.T) {
	testStore = newMockStore()
	v := newTestImpl()

	ibcDenom := "ibc/voucher-verify-mismatch"
	sender := address(testAddress("voucher-verify-snd"))
	uassert.NoError(t, v.mintVoucher(0, cur, ibcDenom, [32]byte{}, "Foo", "FOO", 18, sender, scaledWire(20, 18)))

	metaBytes := mustEncodeTokenMetadata(z.TokenMetadata{
		Implementation: zkgmERC20Impl,
		Initializer:    mustEncodeTokenInitializer(z.TokenInitializer{Name: "Foo", Symbol: "FOO", Decimals: 6}),
	})

	order := z.TokenOrderV2{
		Sender:      []byte(sender),
		BaseToken:   []byte(ibcDenom),
		BaseAmount:  scaledWire(20, 18),
		QuoteToken:  []byte("remote-foo-hop2"),
		QuoteAmount: scaledWire(20, 18),
		Kind:        z.TOKEN_ORDER_KIND_INITIALIZE,
		Metadata:    metaBytes,
	}

	testing.SetRealm(testing.NewUserRealm(address(sender)))
	err := v.verifyTokenOrderV2X(cross(cur), newFunds(nil), types.ChannelId(1), u256.Zero(), order)

	uassert.ErrorContains(t, err, "metadata decimals do not match")
	// Escrow never ran: the sender's full minted balance is untouched.
	uassert.Equal(t, int64(20), voucherBalanceOf(ibcDenom, sender))
}

func TestTokenOrderVerifyNativeRequiresSentCoin(cur realm, t *testing.T) {
	v := newTestImpl()
	sender := testAddress("v1-native-sender")
	order := z.TokenOrderV2{
		Sender:     []byte(sender),
		BaseToken:  []byte("ugnot"),
		BaseAmount: u256.NewUint(13),
		QuoteToken: []byte("quote"),
		Kind:       z.TOKEN_ORDER_KIND_INITIALIZE,
	}

	testing.SetRealm(testing.NewUserRealm(address(sender)))
	err := v.verifyTokenOrderV2X(cross(cur), newFunds(chain.NewCoins(chain.NewCoin("ugnot", 13))), types.ChannelId(4), u256.Zero(), order)

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

	testing.SetRealm(testing.NewUserRealm(address(sender)))
	err := v.verifyTokenOrderV2X(cross(cur), f, channelId, u256.Zero(), order)

	uassert.NoError(t, err)
	uassert.True(t, f.isEmpty())
	balance, _ := testStore.GetChannelBalanceV2(ChannelBalanceKeyV2(channelId, u256.Zero(), order.BaseToken, order.QuoteToken))
	uassert.Equal(t, "13", balance.ToString())
}

func TestTokenOrderVerifyVoucherBurnInsufficientBalanceRejected(cur realm, t *testing.T) {
	v := newTestImpl()

	sender := testAddress("burn-insuf-sender")
	baseToken := "ibc/burn-insuf"
	uassert.NoError(t, v.mintVoucher(0, cur, baseToken, [32]byte{}, "", "", 0, address(sender), u256.NewUint(10)))

	order := z.TokenOrderV2{
		Sender:      []byte(sender),
		BaseToken:   []byte(baseToken),
		BaseAmount:  u256.NewUint(50),
		QuoteToken:  []byte("quote"),
		QuoteAmount: u256.NewUint(50),
		Kind:        z.TOKEN_ORDER_KIND_ESCROW,
	}

	testing.SetRealm(testing.NewUserRealm(address(sender)))
	err := v.verifyTokenOrderV2X(cross(cur), newFunds(nil), types.ChannelId(21), u256.Zero(), order)

	uassert.Error(t, err)
	uassert.Equal(t, int64(10), voucherBalanceOf(baseToken, address(sender)))
}

func TestTokenOrderVerifyUnescrowNativeRejectedBeforeFundsConsume(cur realm, t *testing.T) {
	v := newTestImpl()
	baseDenom := "native-unescrow"
	testStore.SetTokenOrigin(0, cur, baseDenom, u256.Zero())
	sender := testAddress("native-unescrow")
	order := z.TokenOrderV2{
		Sender:      []byte(sender),
		BaseToken:   []byte(baseDenom),
		BaseAmount:  u256.NewUint(13),
		QuoteToken:  []byte("ugnot"),
		QuoteAmount: u256.NewUint(13),
		Kind:        z.TOKEN_ORDER_KIND_UNESCROW,
	}
	f := newFunds(chain.NewCoins(chain.NewCoin(baseDenom, 13)))

	testing.SetRealm(testing.NewUserRealm(address(sender)))
	err := v.verifyTokenOrderV2X(cross(cur), f, types.ChannelId(0), u256.Zero(), order)

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
		Implementation: zkgmERC20Impl,
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
		Implementation: zkgmERC20Impl,
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
		Implementation: zkgmERC20Impl,
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
		Implementation: zkgmERC20Impl,
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
	v.getOrCreateVoucher(0, cur, quoteDenom, [32]byte{}, "T", "T", canonicalDecimals)
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
		Implementation: zkgmERC20Impl,
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
	v.increaseChannelBalanceV2(0, cur, destChan, u256.Zero(), quoteToken, baseToken, int64(50))
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

func TestTokenOrderExecuteUnescrowNativeFeeDistribution(cur realm, t *testing.T) {
	v := newTestImpl()

	const destChan = types.ChannelId(41)
	relayer := testAddress("unescrow-fee-rly")
	receiver := testAddress("unescrow-fee-rx")
	baseToken := []byte("ibc/unescrow-fee")
	quoteToken := []byte("ufee")
	order := z.TokenOrderV2{
		Sender:      []byte("sender"),
		Receiver:    []byte(receiver),
		BaseToken:   baseToken,
		BaseAmount:  u256.NewUint(55),
		QuoteToken:  quoteToken,
		QuoteAmount: u256.NewUint(50),
		Kind:        z.TOKEN_ORDER_KIND_UNESCROW,
	}
	packet := core.NewPacket(types.ChannelId(1), destChan, nil, 0)
	key := ChannelBalanceKeyV2(destChan, u256.Zero(), quoteToken, baseToken)
	testStore.SetChannelBalanceV2(0, cur, key, order.BaseAmount)
	testing.IssueCoins(cur.Address(), chain.NewCoins(chain.NewCoin(string(quoteToken), 55)))

	res, err := v.executeTokenOrderV2(0, cur, packet, address(relayer), nil, [32]byte{}, u256.Zero(), order, false)

	uassert.NoError(t, err)
	uassert.True(t, res.Status == types.PacketStatusSuccess)
	bk := banker.NewReadonlyBanker()
	uassert.Equal(t, int64(50), bk.GetCoins(address(receiver)).AmountOf(string(quoteToken)))
	uassert.Equal(t, int64(5), bk.GetCoins(address(relayer)).AmountOf(string(quoteToken)))
	balance, ok := testStore.GetChannelBalanceV2(key)
	uassert.True(t, ok)
	uassert.True(t, balance.IsZero())
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
	v.getOrCreateVoucher(0, cur, quoteDenom, [32]byte{}, "T", "T", canonicalDecimals)
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
	v.getOrCreateVoucher(0, cur, quoteDenom, [32]byte{}, "T", "T", canonicalDecimals)
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
	v.getOrCreateVoucher(0, cur, quoteDenom, [32]byte{}, "T", "T", canonicalDecimals)
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

func TestTokenOrderExecuteEscrowUninitializedVoucherReturnsFailureAck(cur realm, t *testing.T) {
	testStore = newMockStore()
	v := newTestImpl()

	path := u256.Zero()
	const destChan = types.ChannelId(63)
	receiver := testAddress("uninit-escrow-rx")
	// No prior INITIALIZE: the wrapped voucher does not exist. A same-quote ESCROW
	// must not lazily mint it at decimals=0 (an unredeemable orphan whose scale
	// would then diverge from a later INITIALIZE); it is rejected with a failure
	// ack so the source refunds.
	quoteDenom := z.PredictWrappedToken(path, uint32(destChan), []byte("ugnot"))
	order := z.TokenOrderV2{
		Sender:      []byte("sender"),
		Receiver:    []byte(receiver),
		BaseToken:   []byte("ugnot"),
		BaseAmount:  u256.NewUint(100),
		QuoteToken:  []byte(quoteDenom),
		QuoteAmount: u256.NewUint(100),
		Kind:        z.TOKEN_ORDER_KIND_ESCROW,
	}
	packet := core.NewPacket(types.ChannelId(1), destChan, nil, 0)

	res, err := v.executeTokenOrderV2(0, cur, packet, address(testAddress("uninit-escrow-rly")), nil, [32]byte{}, path, order, false)

	uassert.NoError(t, err)
	uassert.True(t, res.Status == types.PacketStatusFailure)
	uassert.Equal(t, string(universalErrorAck()), string(res.Acknowledgement))
	uassert.False(t, testStore.HasVoucher(quoteDenom), "rejected escrow must not create a voucher")
	uassert.Equal(t, int64(0), voucherBalanceOf(quoteDenom, address(receiver)))
	_, ok := testStore.GetTokenOrigin(quoteDenom)
	uassert.False(t, ok, "rejected escrow must not set token origin")
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
	uassert.NoError(t, v.mintVoucher(0, cur, baseDenom, [32]byte{}, "", "", 0, address(sender), u256.NewUint(100)))

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
	uassert.NoError(t, v.mintVoucher(0, cur, baseDenom, image, "", "", 0, address(sender), u256.NewUint(100)))

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
	uassert.NoError(t, v.mintVoucher(0, cur, baseDenom, imageWrong, "", "", 0, address(sender), u256.NewUint(100)))

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
	uassert.NoError(t, v.mintVoucher(0, cur, quoteToken, [32]byte{}, "", "", 0, address(maker), u256.NewUint(30)))
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
	uassert.NoError(t, v.mintVoucher(0, cur, quoteToken, [32]byte{}, "", "", 0, address(maker), u256.NewUint(3)))
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

	testing.SetRealm(testing.NewUserRealm(address(string(order.Sender))))
	err := v.verifyTokenOrderV2X(cross(cur), newFunds(nil), types.ChannelId(80), u256.Zero(), order)

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

func TestIsZeroImage(t *testing.T) {
	var zero [32]byte
	nonzero := zero
	nonzero[31] = 1

	cases := []struct {
		name  string
		image [32]byte
		want  bool
	}{
		{"zero", zero, true},
		{"nonzero first byte", [32]byte{1}, false},
		{"nonzero last byte", nonzero, false},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			uassert.Equal(t, tc.want, isZeroImage(tc.image))
		})
	}
}

func TestLocalTokenEscrow(cur realm, t *testing.T) {
	cases := []struct {
		name          string
		denom         string
		sender        address
		funds         *funds
		seedVoucher   bool
		amount        *u256.Uint
		wantErr       string
		wantFundsLeft bool
		wantEscrowBal int64
	}{
		{
			name:          "native funds deduct",
			denom:         "ugnot",
			sender:        testAddress("native-sender"),
			funds:         newFunds(chain.NewCoins(chain.NewCoin("ugnot", 10))),
			amount:        u256.NewUint(4),
			wantFundsLeft: true,
		},
		{
			name:    "native insufficient funds",
			denom:   "ugnot",
			sender:  testAddress("native-short"),
			funds:   newFunds(chain.NewCoins(chain.NewCoin("ugnot", 3))),
			amount:  u256.NewUint(4),
			wantErr: errCoinMismatch,
		},
		{
			name:          "voucher transfers to proxy escrow",
			denom:         "ibc/local-escrow",
			sender:        testAddress("voucher-sender"),
			funds:         newFunds(nil),
			seedVoucher:   true,
			amount:        u256.NewUint(6),
			wantEscrowBal: 6,
		},
		{
			name:        "voucher insufficient balance",
			denom:       "ibc/local-escrow-short",
			sender:      testAddress("voucher-short"),
			funds:       newFunds(nil),
			seedVoucher: true,
			amount:      u256.NewUint(20),
			wantErr:     "insufficient",
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			testStore = newMockStore()
			v := newTestImpl()
			if tc.seedVoucher {
				uassert.NoError(t, v.mintVoucher(0, cur, tc.denom, [32]byte{}, "Escrow", "ESC", 0, tc.sender, u256.NewUint(10)))
			}

			err := v.localTokenEscrow(0, cur, tc.denom, tc.sender, tc.funds, tc.amount)
			if tc.wantErr != "" {
				uassert.ErrorContains(t, err, tc.wantErr)
				return
			}

			uassert.NoError(t, err)
			if tc.seedVoucher {
				uassert.Equal(t, tc.wantEscrowBal, voucherBalanceOf(tc.denom, cur.Address()))
			} else {
				uassert.Equal(t, tc.wantFundsLeft, !tc.funds.isEmpty())
			}
		})
	}
}

func TestRefundIBCVoucher(cur realm, t *testing.T) {
	testStore = newMockStore()
	v := newTestImpl()
	denom := "ibc/refund-voucher"
	recipient := address(testAddress("refund-voucher-rx"))
	image := [32]byte{0xaa}
	testStore.SetMetadataImageOf(0, cur, denom, image)

	uassert.NoError(t, v.refundIBCVoucher(0, cur, []byte(denom), recipient, u256.NewUint(12)))
	uassert.Equal(t, int64(12), voucherBalanceOf(denom, recipient))

	gotImage, ok := testStore.GetMetadataImageOf(denom)
	uassert.True(t, ok)
	uassert.True(t, gotImage == image)

	wide := new(u256.Uint).Lsh(u256.NewUint(1), 64)
	uassert.ErrorContains(t, v.refundIBCVoucher(0, cur, []byte("ibc/refund-overflow"), recipient, wide), errAmountOverflow)
}

func TestRefundV2(cur realm, t *testing.T) {
	cases := []struct {
		name          string
		order         z.TokenOrderV2
		seed          func(*ucs03ZkgmV1, z.TokenOrderV2)
		wantErr       string
		wantRecipient int64
		wantBalance   string
	}{
		{
			name: "unescrow refunds ibc voucher",
			order: z.TokenOrderV2{
				Kind:       z.TOKEN_ORDER_KIND_UNESCROW,
				BaseToken:  []byte("ibc/refund-unescrow"),
				BaseAmount: u256.NewUint(7),
				Sender:     []byte(testAddress("refund-unescrow")),
			},
			wantRecipient: 7,
		},
		{
			name: "escrow settles escrowed voucher to sender",
			order: z.TokenOrderV2{
				Kind:        z.TOKEN_ORDER_KIND_ESCROW,
				BaseToken:   []byte("ibc/refund-escrow"),
				QuoteToken:  []byte("quote"),
				BaseAmount:  u256.NewUint(9),
				QuoteAmount: u256.NewUint(9),
				Sender:      []byte(testAddress("refund-escrow")),
			},
			seed: func(v *ucs03ZkgmV1, order z.TokenOrderV2) {
				v.increaseChannelBalanceV2(0, cur, types.ChannelId(5), u256.Zero(), order.BaseToken, order.QuoteToken, order.BaseAmount.Int64())
				uassert.NoError(t, v.mintVoucher(0, cur, string(order.BaseToken), [32]byte{}, "Escrow", "ESC", 0, cur.Address(), order.BaseAmount))
			},
			wantRecipient: 9,
			wantBalance:   "0",
		},
		{
			name: "unsupported kind",
			order: z.TokenOrderV2{
				Kind:       z.TOKEN_ORDER_KIND_SOLVE,
				BaseToken:  []byte("ibc/refund-unsupported"),
				BaseAmount: u256.NewUint(1),
				Sender:     []byte(testAddress("refund-bad")),
			},
			wantErr: errUnsupportedTokenOrderKindForRefund,
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			testStore = newMockStore()
			v := newTestImpl()
			if tc.seed != nil {
				tc.seed(v, tc.order)
			}

			err := v.refundV2(0, cur, u256.Zero(), types.ChannelId(5), tc.order)
			if tc.wantErr != "" {
				uassert.ErrorContains(t, err, tc.wantErr)
				return
			}

			uassert.NoError(t, err)
			uassert.Equal(t, tc.wantRecipient, voucherBalanceOf(string(tc.order.BaseToken), address(string(tc.order.Sender))))
			if tc.wantBalance != "" {
				bal, ok := testStore.GetChannelBalanceV2(ChannelBalanceKeyV2(types.ChannelId(5), u256.Zero(), tc.order.BaseToken, tc.order.QuoteToken))
				uassert.True(t, ok)
				uassert.Equal(t, tc.wantBalance, bal.ToString())
			}
		})
	}
}

func assertProtocolAck(t *testing.T, ackBytes []byte) {
	ack, err := z.DecodeAck(ackBytes)
	uassert.NoError(t, err)
	uassert.True(t, ack.Tag.Eq(tagAckSuccess()))

	orderAck, err := z.DecodeTokenOrderAck(ack.InnerAck)
	uassert.NoError(t, err)
	uassert.True(t, orderAck.FillType.Eq(fillTypeProtocol()))
}

func assertMarketMakerAck(t *testing.T, ackBytes []byte, maker address) {
	ack, err := z.DecodeAck(ackBytes)
	uassert.NoError(t, err)
	uassert.True(t, ack.Tag.Eq(tagAckSuccess()))

	orderAck, err := z.DecodeTokenOrderAck(ack.InnerAck)
	uassert.NoError(t, err)
	uassert.True(t, orderAck.FillType.Eq(fillTypeMarketMaker()))
	uassert.Equal(t, maker, address(orderAck.MarketMaker))
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

type protocolFillMintCase struct {
	name           string
	path           *u256.Uint
	channelId      types.ChannelId
	baseAmount     *u256.Uint
	quoteAmount    *u256.Uint
	metadata       *z.TokenMetadata
	canDeploy      bool
	preDeploy      bool // pre-set foreign token
	expectSuccess  bool
	expectReceiver int64
	expectRelayer  int64
	expectDeployed bool
	expectError    string // non-empty => protocolFillMint returns this error substring
}

func TestProtocolFillMint(cur realm, t *testing.T) {
	validMetadata := mustDecodeTokenMetadata(mustEncodeTokenMetadata(z.TokenMetadata{
		Implementation: zkgmERC20Impl,
		Initializer:    mustEncodeTokenInitializer(z.TokenInitializer{Name: "Test Token", Symbol: "TST", Decimals: 6}),
	}))

	invalidDecimalsMetadata := mustDecodeTokenMetadata(mustEncodeTokenMetadata(z.TokenMetadata{
		Implementation: zkgmERC20Impl,
		Initializer:    mustEncodeTokenInitializer(z.TokenInitializer{Name: "Invalid", Symbol: "INV", Decimals: 19}), // > MaxDecimals (18)
	}))

	cases := []protocolFillMintCase{
		{
			name:           "happy path - mints to receiver and relayer with deployment",
			path:           u256.NewUint(5),
			channelId:      types.ChannelId(5),
			baseAmount:     u256.NewUint(100),
			quoteAmount:    u256.NewUint(95),
			metadata:       &validMetadata,
			canDeploy:      true,
			expectSuccess:  true,
			expectReceiver: 95,
			expectRelayer:  5,
			expectDeployed: true,
		},
		{
			name:           "zero quote amount - skips receiver mint",
			path:           u256.NewUint(10),
			channelId:      types.ChannelId(10),
			baseAmount:     u256.NewUint(100),
			quoteAmount:    u256.NewUint(0),
			metadata:       &validMetadata,
			canDeploy:      true,
			expectSuccess:  true,
			expectReceiver: 0,
			expectRelayer:  100,
			expectDeployed: true,
		},
		{
			name:           "zero fee - skips relayer mint",
			path:           u256.NewUint(15),
			channelId:      types.ChannelId(15),
			baseAmount:     u256.NewUint(100),
			quoteAmount:    u256.NewUint(100),
			metadata:       &validMetadata,
			canDeploy:      true,
			expectSuccess:  true,
			expectReceiver: 100,
			expectRelayer:  0,
			expectDeployed: true,
		},
		{
			name:           "zero amounts - skips both mints but deploys state",
			path:           u256.NewUint(20),
			channelId:      types.ChannelId(20),
			baseAmount:     u256.NewUint(0),
			quoteAmount:    u256.NewUint(0),
			metadata:       &validMetadata,
			canDeploy:      true,
			expectSuccess:  true,
			expectReceiver: 0,
			expectRelayer:  0,
			expectDeployed: false, // no mint = no voucher created, cannot read metadata
		},
		{
			name:           "already deployed - skips deployment but still mints",
			path:           u256.NewUint(25),
			channelId:      types.ChannelId(25),
			baseAmount:     u256.NewUint(100),
			quoteAmount:    u256.NewUint(90),
			metadata:       &validMetadata,
			canDeploy:      true,
			preDeploy:      true,
			expectSuccess:  true,
			expectReceiver: 90,
			expectRelayer:  10,
			expectDeployed: false, // already deployed, no update
		},
		{
			name:           "canDeploy false - skips deployment but still mints",
			path:           u256.NewUint(30),
			channelId:      types.ChannelId(30),
			baseAmount:     u256.NewUint(100),
			quoteAmount:    u256.NewUint(80),
			metadata:       &validMetadata,
			canDeploy:      false,
			expectSuccess:  true,
			expectReceiver: 80,
			expectRelayer:  20,
			expectDeployed: false,
		},
		{
			name:           "invalid decimals - returns failure",
			path:           u256.NewUint(35),
			channelId:      types.ChannelId(35),
			baseAmount:     u256.NewUint(100),
			quoteAmount:    u256.NewUint(95),
			metadata:       &invalidDecimalsMetadata,
			canDeploy:      true,
			expectSuccess:  false,
			expectReceiver: 0,
			expectRelayer:  0,
			expectDeployed: false,
		},
		{
			name:        "fee underflow - quote exceeds base returns error",
			path:        u256.NewUint(36),
			channelId:   types.ChannelId(36),
			baseAmount:  u256.NewUint(50),
			quoteAmount: u256.NewUint(80), // quote > base => fee = base - quote underflows
			metadata:    &validMetadata,
			canDeploy:   true,
			expectError: "fee underflow",
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(cur realm, t *testing.T) {
			v := newTestImpl()

			baseToken := []byte("ugnot")
			path := tc.path
			channelId := tc.channelId
			receiver := testAddress("mint-rx")
			relayer := testAddress("mint-rly")

			image := z.MetadataImage(*tc.metadata)
			wrappedToken := z.PredictWrappedTokenV2(path, uint32(channelId), baseToken, image)

			// Pre-deploy if testing already-deployed case
			if tc.preDeploy {
				testStore.SetForeignToken(0, cur, wrappedToken, baseToken)
				expectedPath, _ := z.UpdateChannelPath(path, uint32(channelId))
				testStore.SetTokenOrigin(0, cur, wrappedToken, expectedPath)
				testStore.SetMetadataImageOf(0, cur, wrappedToken, image)
				uassert.NoError(t, v.mintVoucher(0, cur, wrappedToken, image, "Test Token", "TST", 6, receiver, u256.NewUint(0)))
			}

			res, err := v.protocolFillMint(0, cur, channelId, path, baseToken, wrappedToken, address(receiver), address(relayer), tc.baseAmount, tc.quoteAmount, tc.metadata, tc.canDeploy)

			if tc.expectError != "" {
				uassert.ErrorContains(t, err, tc.expectError)
				uassert.True(t, res.Status == types.PacketStatusUnknown)
				uassert.Equal(t, int64(0), voucherBalanceOf(wrappedToken, address(receiver)))
				uassert.Equal(t, int64(0), voucherBalanceOf(wrappedToken, address(relayer)))
				return
			}

			if tc.expectSuccess {
				uassert.NoError(t, err)
				uassert.True(t, res.Status == types.PacketStatusSuccess)
			} else {
				uassert.NoError(t, err)
				uassert.True(t, res.Status == types.PacketStatusFailure)
			}

			uassert.Equal(t, tc.expectReceiver, voucherBalanceOf(wrappedToken, address(receiver)))
			uassert.Equal(t, tc.expectRelayer, voucherBalanceOf(wrappedToken, address(relayer)))

			if tc.expectDeployed {
				origin, ok := testStore.GetTokenOrigin(wrappedToken)
				uassert.True(t, ok, "token origin should be set")
				expectedPath, err := z.UpdateChannelPath(path, uint32(channelId))
				uassert.NoError(t, err)
				uassert.Equal(t, expectedPath.ToString(), origin.ToString())

				_, ok = testStore.GetForeignToken(wrappedToken)
				uassert.True(t, ok, "foreign token should be set")

				_, ok = testStore.GetMetadataImageOf(wrappedToken)
				uassert.True(t, ok, "metadata image should be set")

				uassert.Equal(t, "Test Token", voucherNameOf(wrappedToken))
				uassert.Equal(t, "TST", voucherSymbolOf(wrappedToken))
				uassert.Equal(t, 6, voucherDecimalsOf(wrappedToken))
			}
		})
	}
}

type protocolFillUnescrowV2Case struct {
	name           string
	path           *u256.Uint
	channelId      types.ChannelId
	baseAmount     *u256.Uint
	quoteAmount    *u256.Uint
	initialBalance *u256.Uint // initial channel balance to set
	expectSuccess  bool
	expectReceiver int64
	expectRelayer  int64
	expectError    string // substring of error message for failure cases
}

func TestProtocolFillUnescrowV2(cur realm, t *testing.T) {
	cases := []protocolFillUnescrowV2Case{
		{
			name:           "happy path - unescrows to receiver and relayer",
			path:           u256.NewUint(40),
			channelId:      types.ChannelId(40),
			baseAmount:     u256.NewUint(100),
			quoteAmount:    u256.NewUint(95),
			initialBalance: u256.NewUint(100),
			expectSuccess:  true,
			expectReceiver: 95,
			expectRelayer:  5,
		},
		{
			name:           "zero quote amount - skips receiver unescrow",
			path:           u256.NewUint(41),
			channelId:      types.ChannelId(41),
			baseAmount:     u256.NewUint(100),
			quoteAmount:    u256.NewUint(0),
			initialBalance: u256.NewUint(100),
			expectSuccess:  true,
			expectReceiver: 0,
			expectRelayer:  100,
		},
		{
			name:           "zero fee - skips relayer unescrow",
			path:           u256.NewUint(42),
			channelId:      types.ChannelId(42),
			baseAmount:     u256.NewUint(100),
			quoteAmount:    u256.NewUint(100),
			initialBalance: u256.NewUint(100),
			expectSuccess:  true,
			expectReceiver: 100,
			expectRelayer:  0,
		},
		{
			name:           "zero amounts - skips both unescrows",
			path:           u256.NewUint(43),
			channelId:      types.ChannelId(43),
			baseAmount:     u256.NewUint(0),
			quoteAmount:    u256.NewUint(0),
			initialBalance: u256.NewUint(0),
			expectSuccess:  true,
			expectReceiver: 0,
			expectRelayer:  0,
		},
		{
			name:           "fee underflow - quote exceeds base returns error",
			path:           u256.NewUint(44),
			channelId:      types.ChannelId(44),
			baseAmount:     u256.NewUint(50),
			quoteAmount:    u256.NewUint(80), // quote > base => fee = base - quote underflows
			initialBalance: u256.NewUint(100),
			expectError:    "fee underflow",
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(cur realm, t *testing.T) {
			v := newTestImpl()

			baseToken := []byte("ugnot")
			path := tc.path
			channelId := tc.channelId
			quoteToken := []byte("ibc/test-quote-" + path.ToString())
			receiver := testAddress("unescrow-rx")
			relayer := testAddress("unescrow-rly")

			// Set token origin so localTokenUnescrow can recognize the voucher
			testStore.SetTokenOrigin(0, cur, string(quoteToken), path)
			// Mint initial voucher to proxy for unescrow
			uassert.NoError(t, v.mintVoucher(0, cur, string(quoteToken), [32]byte{}, "", "", 0, cur.Address(), tc.initialBalance))

			// Set up channel balance: decreaseChannelBalanceV2 uses (quote, base) order
			v.increaseChannelBalanceV2(0, cur, channelId, path, quoteToken, baseToken, tc.initialBalance.Int64())

			res, err := v.protocolFillUnescrowV2(0, cur, channelId, path, baseToken, string(quoteToken), address(receiver), address(relayer), tc.baseAmount, tc.quoteAmount)

			if tc.expectError != "" {
				uassert.ErrorContains(t, err, tc.expectError)
				uassert.True(t, res.Status == types.PacketStatusUnknown)
				return
			}

			if tc.expectSuccess {
				uassert.NoError(t, err)
				uassert.True(t, res.Status == types.PacketStatusSuccess)

				// Check receiver and relayer balances via voucher
				uassert.Equal(t, tc.expectReceiver, voucherBalanceOf(string(quoteToken), address(receiver)))
				uassert.Equal(t, tc.expectRelayer, voucherBalanceOf(string(quoteToken), address(relayer)))
			}
		})
	}
}

func TestEncodeTokenOrderSuccessAck(cur realm, t *testing.T) {
	protocolFT := fillTypeProtocol()
	marketMakerFT := fillTypeMarketMaker()

	// Protocol fill type without market maker
	ack1, err := encodeTokenOrderSuccessAck(protocolFT, nil)
	uassert.NoError(t, err)

	decoded1, err := z.DecodeAck(ack1)
	uassert.NoError(t, err)
	uassert.True(t, decoded1.Tag.Eq(tagAckSuccess()))

	innerAck1, err := z.DecodeTokenOrderAck(decoded1.InnerAck)
	uassert.NoError(t, err)
	uassert.True(t, innerAck1.FillType.Eq(protocolFT))
	uassert.Equal(t, 0, len(innerAck1.MarketMaker))

	// Market maker fill type with market maker address
	makerAddr := testAddress("test-maker")
	ack2, err := encodeTokenOrderSuccessAck(marketMakerFT, []byte(makerAddr))
	uassert.NoError(t, err)

	decoded2, err := z.DecodeAck(ack2)
	uassert.NoError(t, err)
	uassert.True(t, decoded2.Tag.Eq(tagAckSuccess()))

	innerAck2, err := z.DecodeTokenOrderAck(decoded2.InnerAck)
	uassert.NoError(t, err)
	uassert.True(t, innerAck2.FillType.Eq(marketMakerFT))
	uassert.Equal(t, makerAddr, address(innerAck2.MarketMaker))

	// Protocol fill type with empty market maker (should still encode)
	ack3, err := encodeTokenOrderSuccessAck(protocolFT, []byte{})
	uassert.NoError(t, err)

	decoded3, err := z.DecodeAck(ack3)
	uassert.NoError(t, err)
	uassert.True(t, decoded3.Tag.Eq(tagAckSuccess()))

	innerAck3, err := z.DecodeTokenOrderAck(decoded3.InnerAck)
	uassert.NoError(t, err)
	uassert.True(t, innerAck3.FillType.Eq(protocolFT))
	uassert.Equal(t, 0, len(innerAck3.MarketMaker))
}

type marketMakerFillV2Case struct {
	name                  string
	quoteToken            string
	makerBalance          *u256.Uint // initial balance to mint to maker
	quoteAmount           *u256.Uint
	relayerMsg            []byte
	expectSuccess         bool
	expectAckOnlyMaker    bool
	expectMakerBalance    int64
	expectReceiverBalance int64
	expectMarketMaker     string
}

func TestMarketMakerFillV2(cur realm, t *testing.T) {
	cases := []marketMakerFillV2Case{
		{
			name:                  "happy path - transfer succeeds",
			quoteToken:            "ibc/mm-happy",
			makerBalance:          u256.NewUint(50),
			quoteAmount:           u256.NewUint(50),
			relayerMsg:            nil,
			expectSuccess:         true,
			expectAckOnlyMaker:    false,
			expectMakerBalance:    0,
			expectReceiverBalance: 50,
			expectMarketMaker:     "", // will be set to relayer (maker) at runtime
		},
		{
			name:                  "no voucher exists - returns only maker",
			quoteToken:            "ibc/mm-no-voucher",
			makerBalance:          u256.NewUint(0),
			quoteAmount:           u256.NewUint(10),
			relayerMsg:            nil,
			expectSuccess:         true,
			expectAckOnlyMaker:    true,
			expectMakerBalance:    0,
			expectReceiverBalance: 0,
			expectMarketMaker:     "",
		},
		{
			name:                  "insufficient balance - returns only maker",
			quoteToken:            "ibc/mm-insuf",
			makerBalance:          u256.NewUint(10),
			quoteAmount:           u256.NewUint(50),
			relayerMsg:            nil,
			expectSuccess:         true,
			expectAckOnlyMaker:    true,
			expectMakerBalance:    10,
			expectReceiverBalance: 0,
			expectMarketMaker:     "",
		},
		{
			name:                  "with relayer msg - uses msg as market maker",
			quoteToken:            "ibc/mm-msg",
			makerBalance:          u256.NewUint(30),
			quoteAmount:           u256.NewUint(30),
			relayerMsg:            []byte("custom-mm-maker"),
			expectSuccess:         true,
			expectAckOnlyMaker:    false,
			expectMakerBalance:    0,
			expectReceiverBalance: 30,
			expectMarketMaker:     "custom-mm-maker",
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(cur realm, t *testing.T) {
			v := newTestImpl()

			maker := testAddress(tc.name[:10] + "-mk")
			receiver := testAddress(tc.name[:10] + "-rx")

			// Mint initial balance to maker
			if !tc.makerBalance.IsZero() {
				uassert.NoError(t, v.mintVoucher(0, cur, tc.quoteToken, [32]byte{}, "", "", 0, maker, tc.makerBalance))
			}

			order := z.TokenOrderV2{
				Receiver:    []byte(receiver),
				QuoteToken:  []byte(tc.quoteToken),
				QuoteAmount: tc.quoteAmount,
			}

			res, err := v.marketMakerFillV2(0, cur, address(maker), tc.relayerMsg, order)

			uassert.NoError(t, err)
			uassert.True(t, res.Status == types.PacketStatusSuccess)

			if tc.expectAckOnlyMaker {
				uassert.True(t, bytes.Equal(z.ACK_ERR_ONLY_MAKER, res.Acknowledgement))
			} else {
				ack, err := z.DecodeAck(res.Acknowledgement)
				uassert.NoError(t, err)
				uassert.True(t, ack.Tag.Eq(tagAckSuccess()))

				innerAck, err := z.DecodeTokenOrderAck(ack.InnerAck)
				uassert.NoError(t, err)
				uassert.True(t, innerAck.FillType.Eq(fillTypeMarketMaker()))
				if tc.expectMarketMaker != "" {
					uassert.Equal(t, tc.expectMarketMaker, string(innerAck.MarketMaker))
				} else {
					// When nil relayerMsg, marketMaker defaults to relayer (maker)
					uassert.Equal(t, maker, address(innerAck.MarketMaker))
				}
			}

			uassert.Equal(t, tc.expectMakerBalance, voucherBalanceOf(tc.quoteToken, address(maker)))
			uassert.Equal(t, tc.expectReceiverBalance, voucherBalanceOf(tc.quoteToken, address(receiver)))
		})
	}
}

// protocolFillMint and protocolFillUnescrowV2 compute fee = base - quote. A quote
// that exceeds base must be rejected with errTokenOrderFeeUnderflow instead of
// wrapping the subtraction around to a near-2^256 fee. The guard sits at the top
// of each fill, so no mint/escrow seeding is needed to reach it; we drive both
// fills through one table and assert the underflow branch directly.
func TestProtocolFillFeeUnderflow(cur realm, t *testing.T) {
	maxU256 := func() *u256.Uint { return new(u256.Uint).SetAllOne() }

	v := newTestImpl()
	channelId := types.ChannelId(700)
	path := u256.Zero()
	baseToken := []byte("ugnot")
	receiver := address(testAddress("fill-uf-rx"))
	relayer := address(testAddress("fill-uf-rly"))

	// fill invokes one of the two protocol-fill paths with the given amounts.
	mintFill := func(base, quote *u256.Uint) (types.RecvPacketResult, error) {
		return v.protocolFillMint(0, cur, channelId, path, baseToken, "ibc/fill-underflow", receiver, relayer, base, quote, nil, false)
	}
	unescrowFill := func(base, quote *u256.Uint) (types.RecvPacketResult, error) {
		return v.protocolFillUnescrowV2(0, cur, channelId, path, baseToken, "ugnot", receiver, relayer, base, quote)
	}

	cases := []struct {
		name          string
		fill          func(base, quote *u256.Uint) (types.RecvPacketResult, error)
		base          *u256.Uint
		quote         *u256.Uint
		wantUnderflow bool
	}{
		{"mint quote exceeds base by one", mintFill, u256.NewUint(100), u256.NewUint(101), true},
		{"mint quote far exceeds base", mintFill, u256.NewUint(1), maxU256(), true},
		{"mint zero base nonzero quote", mintFill, u256.NewUint(0), u256.NewUint(1), true},
		{"unescrow quote exceeds base by one", unescrowFill, u256.NewUint(100), u256.NewUint(101), true},
		{"unescrow quote far exceeds base", unescrowFill, u256.NewUint(1), maxU256(), true},
		{"unescrow zero base nonzero quote", unescrowFill, u256.NewUint(0), u256.NewUint(1), true},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			res, err := tc.fill(tc.base, tc.quote)

			if !tc.wantUnderflow {
				uassert.NoError(t, err)
				return
			}

			uassert.Error(t, err)
			uassert.ErrorContains(t, err, errTokenOrderFeeUnderflow)
			// the underflow branch returns the unknown status with no ack so the
			// caller treats it as a fatal decode-time failure, not a fill.
			uassert.True(t, res.Status == types.PacketStatusUnknown)
			uassert.Equal(t, 0, len(res.Acknowledgement))
		})
	}
}
