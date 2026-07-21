package ucs03_zkgm

import (
	"chain"
	"math"
	"testing"

	types "gno.land/p/onbloc/ibc/union/types"

	u256 "gno.land/p/gnoswap/uint256"
	"gno.land/p/nt/uassert/v0"
	z "gno.land/p/onbloc/ibc/union/zkgm"
	core "gno.land/r/onbloc/ibc/union/core"
)

func scaledWire(whole uint64, decimals uint8) *u256.Uint {
	return u256.Zero().Mul(u256.NewUint(whole), z.Pow10(scaleExpForDecimals(decimals)))
}

func TestInitializeDownscalesToCanonical(cur realm, t *testing.T) {
	v := newTestImpl()

	const whole = uint64(77)
	base := []byte("uatom")
	relayer := address(testAddress("dag-rly"))

	for _, tc := range []struct {
		decimals uint8
		sym      string
		path     uint64
		dest     uint32
		rxSuffix string
	}{
		{0, "T0", 110, 120, "dag-rx-0"},
		{6, "T6", 111, 121, "dag-rx-6"},
		{18, "TK", 112, 122, "dag-rx-18"},
	} {
		meta := mustEncodeTokenMetadata(z.TokenMetadata{
			Implementation: []byte("grc20"),
			Initializer:    mustEncodeTokenInitializer(z.TokenInitializer{Name: "T", Symbol: tc.sym, Decimals: tc.decimals}),
		})
		denom := z.PredictWrappedTokenV2(u256.NewUint(tc.path), tc.dest, base, z.MetadataImage(mustDecodeTokenMetadata(meta)))
		rx := testAddress(tc.rxSuffix)
		// Wire carries source-precision units; the ledger holds them downscaled to
		// canonicalDecimals, so `whole` canonical units mint regardless of decimals.
		wire := scaledWire(whole, tc.decimals)
		res, err := v.executeTokenOrderV2(0, cur,
			core.NewPacket(types.ChannelId(1), types.ChannelId(tc.dest), nil, 0),
			relayer, nil, [32]byte{}, u256.NewUint(tc.path),
			z.TokenOrderV2{
				Sender: []byte("s"), Receiver: []byte(rx), BaseToken: base,
				BaseAmount: wire, QuoteToken: []byte(denom), QuoteAmount: wire,
				Kind: z.TOKEN_ORDER_KIND_INITIALIZE, Metadata: meta,
			}, false)
		uassert.NoError(t, err)
		uassert.True(t, res.Status == types.PacketStatusSuccess)
		uassert.Equal(t, int64(whole), voucherBalanceOf(denom, address(rx)))

		expDecimals := int(tc.decimals)
		if expDecimals > canonicalDecimals {
			expDecimals = canonicalDecimals
		}
		uassert.Equal(t, expDecimals, voucherDecimalsOf(denom))
	}
}

func TestInitializeIndivisibleAmountFailsClosedNoMint(cur realm, t *testing.T) {
	v := newTestImpl()

	metaBytes := mustEncodeTokenMetadata(z.TokenMetadata{
		Implementation: []byte("grc20"),
		Initializer:    mustEncodeTokenInitializer(z.TokenInitializer{Name: "IDV", Symbol: "IDV", Decimals: 18}),
	})
	const destChan = types.ChannelId(155)
	ibcDenom := z.PredictWrappedTokenV2(u256.Zero(), uint32(destChan), []byte("uatom"), z.MetadataImage(mustDecodeTokenMetadata(metaBytes)))
	rx := testAddress("idv-rx")

	// 77 raw units carry precision below the 6-dec ledger for an 18-dec token, so
	// the fill is rejected rather than silently truncating the low-order digits.
	data := mustZkgmPacketBytes(batchMustOrderInstruction(z.TokenOrderV2{
		Sender:      []byte("sender"),
		Receiver:    []byte(rx),
		BaseToken:   []byte("uatom"),
		BaseAmount:  u256.NewUint(77),
		QuoteToken:  []byte(ibcDenom),
		QuoteAmount: u256.NewUint(77),
		Kind:        z.TOKEN_ORDER_KIND_INITIALIZE,
		Metadata:    metaBytes,
	}))
	packet := core.NewPacket(types.ChannelId(1), destChan, data, 0)

	testing.SetRealm(testing.NewCodeRealm(zkgmProxyRealmPath))
	res := v.OnRecvPacket(0, cur, packet, address(testAddress("idv-rly")), nil)

	uassert.True(t, res.Status == types.PacketStatusFailure)
	uassert.Equal(t, int64(0), voucherBalanceOf(ibcDenom, address(rx)))
}

func TestSendBackUpscalesToSourcePrecision(cur realm, t *testing.T) {
	v := newTestImpl()

	// A voucher created from an 18-dec source holds canonical units; sending it
	// back burns the canonical amount that the source-precision wire divides to.
	ibcDenom := "ibc/roundtrip-18"
	holder := testAddress("rt18-holder")
	uassert.NoError(t, v.mintVoucher(0, cur, ibcDenom, [32]byte{}, "Round", "RND", 18, address(holder), scaledWire(50, 18)))
	uassert.Equal(t, int64(50), voucherBalanceOf(ibcDenom, address(holder)))

	// Burning 30 canonical units requires the source-precision wire amount; the
	// same 30 units expressed raw (ignoring scale) is rejected.
	uassert.Error(t, v.burnVoucher(0, cur, ibcDenom, address(holder), u256.NewUint(30)))
	uassert.NoError(t, v.burnVoucher(0, cur, ibcDenom, address(holder), scaledWire(30, 18)))
	uassert.Equal(t, int64(20), voucherBalanceOf(ibcDenom, address(holder)))
}

func TestBaseAmountPreservedThroughMint(cur realm, t *testing.T) {
	v := newTestImpl()

	const N = uint64(100)
	const chanSrc = types.ChannelId(132)
	const chanDest = types.ChannelId(133)
	path := u256.Zero()
	ibcBase := "ibc/rt-base-mint"
	receiver := testAddress("rt-receiver-mint")

	metaBytes := mustEncodeTokenMetadata(z.TokenMetadata{
		Implementation: []byte("grc20"),
		Initializer:    mustEncodeTokenInitializer(z.TokenInitializer{Name: "RT", Symbol: "RT", Decimals: 6}),
	})
	ibcDest := z.PredictWrappedTokenV2(path, uint32(chanDest), []byte(ibcBase), z.MetadataImage(mustDecodeTokenMetadata(metaBytes)))

	order := z.TokenOrderV2{
		Sender:      []byte(testAddress("rt-sender-mint")),
		Receiver:    []byte(receiver),
		BaseToken:   []byte(ibcBase),
		BaseAmount:  u256.NewUint(N),
		QuoteToken:  []byte(ibcDest),
		QuoteAmount: u256.NewUint(N),
		Kind:        z.TOKEN_ORDER_KIND_INITIALIZE,
		Metadata:    metaBytes,
	}

	res, err := v.executeTokenOrderV2(0, cur,
		core.NewPacket(chanSrc, chanDest, nil, 0),
		address(testAddress("rt-rly-mint")), nil, [32]byte{}, path, order, false)
	uassert.NoError(t, err)
	uassert.True(t, res.Status == types.PacketStatusSuccess)
	uassert.Equal(t, int64(N), voucherBalanceOf(ibcDest, address(receiver)))
}

func TestNativeBaseAmountNotUpscaled(cur realm, t *testing.T) {
	v := newTestImpl()

	const N = int64(1_000_000) // 1 ugnot (6-dec representation)
	const chanId = types.ChannelId(140)
	sender := testAddress("native-noscale-sndr")
	order := z.TokenOrderV2{
		Sender:      []byte(sender),
		BaseToken:   []byte("ugnot"),
		BaseAmount:  u256.NewUint(uint64(N)),
		QuoteToken:  []byte("ibc/out-native"),
		QuoteAmount: u256.NewUint(uint64(N)),
		Kind:        z.TOKEN_ORDER_KIND_INITIALIZE,
	}
	f := newFunds(chain.NewCoins(chain.NewCoin("ugnot", N)))

	testing.SetRealm(testing.NewUserRealm(address(sender)))
	err := v.verifyTokenOrderV2X(cross(cur), f, chanId, u256.Zero(), order)

	uassert.NoError(t, err)
	uassert.True(t, f.isEmpty())
	bal, _ := testStore.GetChannelBalanceV2(ChannelBalanceKeyV2(chanId, u256.Zero(), order.BaseToken, order.QuoteToken))
	uassert.Equal(t, u256.NewUint(uint64(N)).ToString(), bal.ToString())
}

// TestChannelBalanceHeldInVaultPrecision locks the precision invariant: escrowing a
// downscaled 18-dec voucher records the LEDGER/vault amount in the channel balance,
// 1:1 with the custody that actually moved — NOT the wire amount. This matches
// Union (outstanding == vault) and keeps the balance directly reconcilable.
func TestChannelBalanceHeldInVaultPrecision(cur realm, t *testing.T) {
	v := newTestImpl()

	ibcDenom := "ibc/chbal-voucher-18"
	sender := testAddress("chbal-voucher-sndr")
	const chanId = types.ChannelId(145)

	// Sender holds 50 canonical (6-dec ledger) units of an 18-dec-origin voucher.
	uassert.NoError(t, v.mintVoucher(0, cur, ibcDenom, [32]byte{}, "CB", "CB", 18, address(sender), scaledWire(50, 18)))
	uassert.Equal(t, int64(50), voucherBalanceOf(ibcDenom, address(sender)))

	// Escrow 30 canonical units, expressed on the wire as 30 * 10^12.
	wire := scaledWire(30, 18)
	order := z.TokenOrderV2{
		Sender:      []byte(sender),
		BaseToken:   []byte(ibcDenom),
		BaseAmount:  wire,
		QuoteToken:  []byte("ibc/chbal-quote"),
		QuoteAmount: wire,
		Kind:        z.TOKEN_ORDER_KIND_ESCROW,
	}

	testing.SetRealm(testing.NewUserRealm(address(sender)))
	uassert.NoError(t, v.verifyTokenOrderV2X(cross(cur), newFunds(nil), chanId, u256.Zero(), order))

	// Custody moved the LEDGER amount (30): sender 50 -> 20.
	uassert.Equal(t, int64(20), voucherBalanceOf(ibcDenom, address(sender)))

	// Channel balance holds the LEDGER amount (30) == the custody that moved,
	// NOT the wire amount (30 * 10^12).
	bal, ok := testStore.GetChannelBalanceV2(ChannelBalanceKeyV2(chanId, u256.Zero(), order.BaseToken, order.QuoteToken))
	uassert.True(t, ok)
	uassert.Equal(t, "30", bal.ToString())
}

func TestTimeoutNativeOrderWithMetadataDoesNotTrimEscrow(cur realm, t *testing.T) {
	v := newTestImpl()

	amount := u256.NewUint(2_000_000_000_000)
	meta := mustEncodeTokenMetadata(z.TokenMetadata{
		Implementation: []byte("grc20"),
		Initializer:    mustEncodeTokenInitializer(z.TokenInitializer{Name: "USDC", Symbol: "USDC", Decimals: 18}),
	})
	order := z.TokenOrderV2{
		Sender:      []byte(testAddress("timeout-sender")),
		BaseToken:   []byte("ugnot"),
		BaseAmount:  amount,
		QuoteToken:  []byte("ibc/timeout-native"),
		QuoteAmount: amount,
		Kind:        z.TOKEN_ORDER_KIND_INITIALIZE,
		Metadata:    meta,
	}
	key := ChannelBalanceKeyV2(types.ChannelId(172), u256.Zero(), order.BaseToken, order.QuoteToken)
	testStore.SetChannelBalanceV2(0, cur, key, amount)
	testing.IssueCoins(cur.Address(), chain.NewCoins(chain.NewCoin("ugnot", 2_000_000_000_000)))

	err := v.timeoutInternal(
		0, cur,
		core.NewPacket(types.ChannelId(172), types.ChannelId(173), nil, 0),
		[32]byte{}, u256.Zero(), batchMustOrderInstruction(order),
	)
	uassert.NoError(t, err)

	bal, _ := testStore.GetChannelBalanceV2(key)
	uassert.Equal(t, u256.Zero().ToString(), bal.ToString())
}

// TestVerifyAndTimeoutNativeInitializeRoundTrip guards against the bug where
// verifyInternal uses scaleDownIncomingOrder (which applies metadata.Decimals) on
// the send path: escrow would store a divided amount while timeout would refund the
// original, causing a balance mismatch. verifyInternal must use scaleDownOutboundOrder
// so that native BaseToken amounts are stored and refunded at the same value.
func TestVerifyAndTimeoutNativeInitializeRoundTrip(cur realm, t *testing.T) {
	v := newTestImpl()

	amount := u256.NewUint(1_000_000_000_000)
	sender := testAddress("vt-sender")
	meta := mustEncodeTokenMetadata(z.TokenMetadata{
		Implementation: []byte("grc20"),
		Initializer:    mustEncodeTokenInitializer(z.TokenInitializer{Name: "USDC", Symbol: "USDC", Decimals: 18}),
	})
	order := z.TokenOrderV2{
		Sender:      []byte(sender),
		BaseToken:   []byte("ugnot"),
		BaseAmount:  amount,
		QuoteToken:  []byte("ibc/vt-native"),
		QuoteAmount: amount,
		Kind:        z.TOKEN_ORDER_KIND_INITIALIZE,
		Metadata:    meta,
	}
	instruction := batchMustOrderInstruction(order)
	const chanId = types.ChannelId(190)

	testing.IssueCoins(cur.Address(), chain.NewCoins(chain.NewCoin("ugnot", 1_000_000_000_000)))
	testing.IssueCoins(address(sender), chain.NewCoins(chain.NewCoin("ugnot", 1_000_000_000_000)))
	f := newFunds(chain.NewCoins(chain.NewCoin("ugnot", 1_000_000_000_000)))
	testing.SetRealm(testing.NewUserRealm(address(sender)))
	err := v.verifyInternalX(cross(cur), f, chanId, u256.Zero(), instruction)
	uassert.NoError(t, err)

	key := ChannelBalanceKeyV2(chanId, u256.Zero(), order.BaseToken, order.QuoteToken)
	bal, _ := testStore.GetChannelBalanceV2(key)
	uassert.Equal(t, amount.ToString(), bal.ToString())

	err = v.timeoutInternal(
		0, cur,
		core.NewPacket(chanId, types.ChannelId(191), nil, 0),
		[32]byte{}, u256.Zero(), instruction,
	)
	uassert.NoError(t, err)

	bal, _ = testStore.GetChannelBalanceV2(key)
	uassert.Equal(t, u256.Zero().ToString(), bal.ToString())
}

func TestInitializeOverflowAmountReturnsFailureAckNoMint(cur realm, t *testing.T) {
	v := newTestImpl()

	metaBytes := mustEncodeTokenMetadata(z.TokenMetadata{
		Implementation: []byte("grc20"),
		Initializer:    mustEncodeTokenInitializer(z.TokenInitializer{Name: "OVF", Symbol: "OVF", Decimals: 18}),
	})
	const destChan = types.ChannelId(150)
	ibcDenom := z.PredictWrappedTokenV2(u256.Zero(), uint32(destChan), []byte("uatom"), z.MetadataImage(mustDecodeTokenMetadata(metaBytes)))
	overflowAmt := new(u256.Uint).Add(u256.NewUint(uint64(math.MaxInt64)), u256.NewUint(1))
	receiver := testAddress("ovf-rx")

	data := mustZkgmPacketBytes(batchMustOrderInstruction(z.TokenOrderV2{
		Sender:      []byte("sender"),
		Receiver:    []byte(receiver),
		BaseToken:   []byte("uatom"),
		BaseAmount:  overflowAmt,
		QuoteToken:  []byte(ibcDenom),
		QuoteAmount: overflowAmt,
		Kind:        z.TOKEN_ORDER_KIND_INITIALIZE,
		Metadata:    metaBytes,
	}))
	packet := core.NewPacket(types.ChannelId(1), destChan, data, 0)

	testing.SetRealm(testing.NewCodeRealm(zkgmProxyRealmPath))
	res := v.OnRecvPacket(0, cur, packet, address(testAddress("ovf-rly")), nil)

	uassert.True(t, res.Status == types.PacketStatusFailure)
	uassert.Equal(t, string(universalErrorAck()), string(res.Acknowledgement))
	uassert.Equal(t, int64(0), voucherBalanceOf(ibcDenom, address(receiver)))
}

func TestSendBaseAmountInt64Boundary(cur realm, t *testing.T) {
	v := newTestImpl()

	maxI64 := u256.NewUint(uint64(math.MaxInt64))

	senderA := testAddress("bnd-sndr-a")
	const chanA = types.ChannelId(160)
	orderA := z.TokenOrderV2{
		Sender:      []byte(senderA),
		BaseToken:   []byte("ugnot"),
		BaseAmount:  maxI64,
		QuoteToken:  []byte("ibc/bnd-out-a"),
		QuoteAmount: maxI64,
		Kind:        z.TOKEN_ORDER_KIND_INITIALIZE,
	}
	testing.SetRealm(testing.NewUserRealm(address(senderA)))
	err := v.verifyTokenOrderV2X(cross(cur), newFunds(chain.NewCoins(chain.NewCoin("ugnot", math.MaxInt64))), chanA, u256.Zero(), orderA)
	uassert.NoError(t, err)
	balA, _ := testStore.GetChannelBalanceV2(ChannelBalanceKeyV2(chanA, u256.Zero(), orderA.BaseToken, orderA.QuoteToken))
	uassert.Equal(t, maxI64.ToString(), balA.ToString())

	senderB := testAddress("bnd-sndr-b")
	const chanB = types.ChannelId(161)
	overAmt := new(u256.Uint).Add(maxI64, u256.NewUint(1))
	orderB := z.TokenOrderV2{
		Sender:      []byte(senderB),
		BaseToken:   []byte("ugnot"),
		BaseAmount:  overAmt,
		QuoteToken:  []byte("ibc/bnd-out-b"),
		QuoteAmount: overAmt,
		Kind:        z.TOKEN_ORDER_KIND_INITIALIZE,
	}
	// An int64-overflowing base amount is rejected. The reference increases the
	// channel balance before escrowing (contract.rs L511-543), so the failing
	// escrow leaves a transient balance entry; in production the verify error
	// aborts the whole Send tx (impl.gno panics), rolling that write back. Here
	// verify is called in isolation, so we only assert the rejection.
	testing.SetRealm(testing.NewUserRealm(address(senderB)))
	err = v.verifyTokenOrderV2X(cross(cur), newFunds(chain.NewCoins(chain.NewCoin("ugnot", math.MaxInt64))), chanB, u256.Zero(), orderB)
	uassert.Error(t, err)
}

func TestVoucherDecimalsWithinLimit(cur realm, t *testing.T) {
	v := newTestImpl()

	rx := testAddress("dec-limit-rx")

	for _, tc := range []struct {
		denom    string
		sym      string
		decimals uint8
		expDec   int
	}{
		{"ibc/dl-0", "DL0", 0, 0},
		{"ibc/dl-6", "DL6", 6, 6},
		{"ibc/dl-18", "DLK", 18, canonicalDecimals}, // MaxDecimals; capped to canonical.
	} {
		// One canonical unit expressed in the source precision.
		amt := scaledWire(1, tc.decimals)
		uassert.NoError(t, v.mintVoucher(0, cur, tc.denom, [32]byte{}, "T", tc.sym, tc.decimals, address(rx), amt))
		uassert.Equal(t, tc.expDec, voucherDecimalsOf(tc.denom))
		uassert.Equal(t, int64(1), voucherBalanceOf(tc.denom, address(rx)))
	}
}

func TestInitializeDecimalsExceedMaxReturnsFailureAck(cur realm, t *testing.T) {
	v := newTestImpl()

	metaBytes := mustEncodeTokenMetadata(z.TokenMetadata{
		Implementation: []byte("grc20"),
		Initializer: mustEncodeTokenInitializer(z.TokenInitializer{
			Name: "Over", Symbol: "OVD", Decimals: 19,
		}),
	})
	const destChan = types.ChannelId(180)
	ibcDenom := z.PredictWrappedTokenV2(u256.Zero(), uint32(destChan), []byte("uatom"), z.MetadataImage(mustDecodeTokenMetadata(metaBytes)))

	data := mustZkgmPacketBytes(batchMustOrderInstruction(z.TokenOrderV2{
		Sender:      []byte("sender"),
		Receiver:    []byte(testAddress("ovd-rx")),
		BaseToken:   []byte("uatom"),
		BaseAmount:  u256.NewUint(100),
		QuoteToken:  []byte(ibcDenom),
		QuoteAmount: u256.NewUint(100),
		Kind:        z.TOKEN_ORDER_KIND_INITIALIZE,
		Metadata:    metaBytes,
	}))
	packet := core.NewPacket(types.ChannelId(1), destChan, data, 0)

	testing.SetRealm(testing.NewCodeRealm(zkgmProxyRealmPath))
	res := v.OnRecvPacket(0, cur, packet, address(testAddress("ovd-rly")), nil)

	uassert.True(t, res.Status == types.PacketStatusFailure)
	uassert.Equal(t, string(universalErrorAck()), string(res.Acknowledgement))
	uassert.False(t, testStore.HasVoucher(ibcDenom))
}

func TestReInitializeSameIBCDenomPreservesScale(cur realm, t *testing.T) {
	v := newTestImpl()

	ibcDenom := "ibc/reint-test"
	rx := testAddress("reint-rx")

	// First creation: decimals=18 caps the ledger to canonicalDecimals and fixes
	// the scale exponent. 20 canonical units arrive as 20*10^scaleExp on the wire.
	uassert.NoError(t, v.mintVoucher(0, cur, ibcDenom, [32]byte{}, "Token", "TKN", 18, address(rx), scaledWire(20, 18)))
	uassert.Equal(t, canonicalDecimals, voucherDecimalsOf(ibcDenom))
	uassert.Equal(t, int64(20), voucherBalanceOf(ibcDenom, address(rx)))

	// A later call with a different decimals argument reuses the existing voucher:
	// the ledger decimals and the fixed scale are preserved. A raw amount ignoring
	// that scale is rejected...
	uassert.Error(t, v.mintVoucher(0, cur, ibcDenom, [32]byte{}, "Token", "TKN", 6, address(rx), u256.NewUint(10)))

	// ...while a correctly-scaled amount mints 10 more canonical units.
	uassert.NoError(t, v.mintVoucher(0, cur, ibcDenom, [32]byte{}, "Token", "TKN", 6, address(rx), scaledWire(10, 18)))
	uassert.Equal(t, canonicalDecimals, voucherDecimalsOf(ibcDenom))
	uassert.Equal(t, int64(30), voucherBalanceOf(ibcDenom, address(rx)))
}
