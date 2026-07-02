package impl

import (
	"chain"
	"math"
	"testing"

	"gno.land/p/nt/uassert/v0"

	u256 "gno.land/p/gnoswap/uint256"
	"gno.land/p/onbloc/ibc/union/types"

	z "gno.land/p/onbloc/ibc/union/zkgm"
	"gno.land/r/onbloc/ibc/union/core"
)

func TestInitializeDecimalsAgnosticAccounting(cur realm, t *testing.T) {
	v := newTestImpl()

	const N = uint64(77)
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
		res, err := v.executeTokenOrderV2(0, cur,
			core.NewPacket(types.ChannelId(1), types.ChannelId(tc.dest), nil, 0),
			relayer, nil, [32]byte{}, u256.NewUint(tc.path),
			z.TokenOrderV2{
				Sender: []byte("s"), Receiver: []byte(rx), BaseToken: base,
				BaseAmount: u256.NewUint(N), QuoteToken: []byte(denom), QuoteAmount: u256.NewUint(N),
				Kind: z.TOKEN_ORDER_KIND_INITIALIZE, Metadata: meta,
			}, false)
		uassert.NoError(t, err)
		uassert.True(t, res.Status == types.PacketStatusSuccess)
		uassert.Equal(t, int64(N), voucherBalanceOf(denom, address(rx)))
		uassert.Equal(t, int(tc.decimals), voucherDecimalsOf(denom))
	}
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

func TestAcknowledgeNativeOrderWithMetadataDoesNotTrimEscrow(cur realm, t *testing.T) {
	v := newTestImpl()

	amount := u256.NewUint(1_000_000_000_000)
	meta := mustEncodeTokenMetadata(z.TokenMetadata{
		Implementation: []byte("grc20"),
		Initializer:    mustEncodeTokenInitializer(z.TokenInitializer{Name: "USDC", Symbol: "USDC", Decimals: 18}),
	})
	order := z.TokenOrderV2{
		Sender:      []byte(testAddress("ack-native-sender")),
		BaseToken:   []byte("ugnot"),
		BaseAmount:  amount,
		QuoteToken:  []byte("ibc/ack-native"),
		QuoteAmount: amount,
		Kind:        z.TOKEN_ORDER_KIND_INITIALIZE,
		Metadata:    meta,
	}
	key := ChannelBalanceKeyV2(types.ChannelId(170), u256.Zero(), order.BaseToken, order.QuoteToken)
	testStore.SetChannelBalanceV2(0, cur, key, amount)

	innerAck, err := z.EncodeTokenOrderAck(z.TokenOrderAck{
		FillType:    fillTypeMarketMaker(),
		MarketMaker: []byte(z.BURN_ADDRESS),
	})
	uassert.NoError(t, err)

	err = v.acknowledgeInternal(
		0, cur,
		core.NewPacket(types.ChannelId(170), types.ChannelId(171), nil, 0),
		address(testAddress("ack-native-relayer")),
		[32]byte{}, u256.Zero(), batchMustOrderInstruction(order), true, innerAck,
	)
	uassert.NoError(t, err)

	bal, _ := testStore.GetChannelBalanceV2(key)
	uassert.Equal(t, u256.Zero().ToString(), bal.ToString())

	locked, ok := testStore.GetLockedNative("ugnot")
	uassert.True(t, ok)
	uassert.Equal(t, amount.ToString(), locked.ToString())
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
	testing.SetRealm(testing.NewUserRealm(address(senderB)))
	err = v.verifyTokenOrderV2X(cross(cur), newFunds(chain.NewCoins(chain.NewCoin("ugnot", math.MaxInt64))), chanB, u256.Zero(), orderB)
	uassert.Error(t, err)
}

func TestVoucherDecimalsWithinLimit(cur realm, t *testing.T) {
	v := newTestImpl()

	rx := testAddress("dec-limit-rx")
	amt := u256.NewUint(1)

	for _, tc := range []struct {
		denom    string
		sym      string
		decimals uint8
	}{
		{"ibc/dl-0", "T0", 0},
		{"ibc/dl-6", "T6", 6},
		{"ibc/dl-18", "TK", 18},
	} {
		uassert.NoError(t, v.mintVoucher(0, cur, tc.denom, [32]byte{}, "T", tc.sym, tc.decimals, rx, amt))
		uassert.Equal(t, int(tc.decimals), voucherDecimalsOf(tc.denom))
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

func TestReInitializeSameIBCDenomPreservesDecimals(cur realm, t *testing.T) {
	v := newTestImpl()

	ibcDenom := "ibc/reint-test"
	rx := testAddress("reint-rx")
	amt := u256.NewUint(10)

	uassert.NoError(t, v.mintVoucher(0, cur, ibcDenom, [32]byte{}, "Token", "TKN", 18, rx, amt))
	uassert.Equal(t, 18, voucherDecimalsOf(ibcDenom))

	uassert.NoError(t, v.mintVoucher(0, cur, ibcDenom, [32]byte{}, "Token", "TKN", 6, rx, amt))
	uassert.Equal(t, 18, voucherDecimalsOf(ibcDenom))
	uassert.Equal(t, int64(20), voucherBalanceOf(ibcDenom, address(rx)))
}

func TestScaleDownAmount(cur realm, t *testing.T) {
	tests := []struct {
		name          string
		tokenDecimals uint8
		amount        uint64
		expectedLocal uint64
		expectError   string
	}{
		{"with dust", 18, 123456700000000000, 0, "decimal dust is not allowed"},
		{"no dust", 18, 1000000000000000000, 1000000, ""},
		{"target decimals only", 6, 1234560, 1234560, ""},
		{"less than target decimals", 4, 12345, 12345, ""},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			amount := u256.NewUint(tc.amount)
			got, err := scaleDownAmount(tc.tokenDecimals, amount)
			if tc.expectError != "" {
				uassert.ErrorContains(t, err, tc.expectError)
				return
			}

			uassert.NoError(t, err)
			uassert.Equal(t, u256.NewUint(tc.expectedLocal).ToString(), got.ToString())
		})
	}
}

func TestParseTokenInfo(cur realm, t *testing.T) {
	v := newTestImpl()

	denom := "ibc/ABCDEF"
	v.mintVoucher(0, cur, denom, [32]byte{}, "Test Voucher", "TVST", 18, "sender", u256.NewUint(1000000))

	tests := []struct {
		denom          string
		expectVoucher  bool
		expectDecimals uint8
	}{
		{denom, true, 18},
		{"ugnot", false, 0},
		{"unknown", false, 0},
	}

	for _, tc := range tests {
		t.Run(tc.denom, func(t *testing.T) {
			info := v.parseTokenInfo(0, cur, []byte(tc.denom))
			uassert.Equal(t, tc.expectVoucher, info.isVoucher)
			if tc.expectVoucher {
				uassert.Equal(t, tc.expectDecimals, info.decimals)
			}
		})
	}
}

func TestScaleDownAmountMaxInt64Boundary(cur realm, t *testing.T) {
	v := newTestImpl()

	denom := "ibc/max64-boundary"
	sender := testAddress("max64-sender")
	v.mintVoucher(0, cur, denom, [32]byte{}, "Large", "LARGE", 18, sender, u256.NewUint(9223372036854775807))

	tests := []struct {
		name        string
		baseAmount  uint64
		expectLocal uint64
		expectError string
	}{
		{
			name:        "MaxInt64 - 18dec rejects dust",
			baseAmount:  9223372036854775807,
			expectError: "decimal dust is not allowed",
		},
		{
			name:        "MaxInt64/2 - 18dec rejects dust",
			baseAmount:  4611686018427387903,
			expectError: "decimal dust is not allowed",
		},
		{
			name:        "Near MaxInt64 - 18dec converts cleanly",
			baseAmount:  9000000000000000000,
			expectLocal: 9000000,
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			amount := u256.NewUint(tc.baseAmount)
			got, err := scaleDownAmount(18, amount)
			if tc.expectError != "" {
				uassert.ErrorContains(t, err, tc.expectError)
				return
			}

			uassert.NoError(t, err)
			uassert.Equal(t, u256.NewUint(tc.expectLocal).ToString(), got.ToString())
		})
	}
}

func mustEncodeTokenOrderV2(order z.TokenOrderV2) []byte {
	out, err := z.EncodeTokenOrderV2(order)
	if err != nil {
		panic(err)
	}
	return out
}
