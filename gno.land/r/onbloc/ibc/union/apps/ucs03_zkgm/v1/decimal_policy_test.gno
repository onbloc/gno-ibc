package impl

// decimal_policy_test.gno exercises token_order.gno's decimal-agnostic accounting:
// BaseAmount is preserved verbatim through lock/mint/refund regardless of the
// wrapped token's declared decimals, and out-of-range decimals/amounts fail closed.

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
		denom := PredictWrappedTokenV2(u256.NewUint(tc.path), tc.dest, base, MetadataImage(mustDecodeTokenMetadata(meta)))
		rx := testAddress(tc.rxSuffix)
		res, err := v.executeTokenOrderV2(0, cur,
			core.NewPacket(types.ChannelId(1), types.ChannelId(tc.dest), nil, 0),
			relayer, nil, u256.NewUint(tc.path),
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

func TestBaseAmountPreservedThroughLockAndRefund(cur realm, t *testing.T) {
	v := newTestImpl()

	const N = uint64(100)
	const chanSrc = types.ChannelId(130)
	path := u256.Zero()
	ibcBase := "ibc/rt-base"
	sender := testAddress("rt-sender")

	uassert.NoError(t, v.mintVoucher(0, cur, ibcBase, [32]byte{}, "", "", 0, sender, u256.NewUint(N)))

	metaBytes := mustEncodeTokenMetadata(z.TokenMetadata{
		Implementation: []byte("grc20"),
		Initializer:    mustEncodeTokenInitializer(z.TokenInitializer{Name: "RT", Symbol: "RT", Decimals: 6}),
	})
	ibcDest := PredictWrappedTokenV2(path, uint32(types.ChannelId(131)), []byte(ibcBase), MetadataImage(mustDecodeTokenMetadata(metaBytes)))

	order := z.TokenOrderV2{
		Sender:      []byte(sender),
		Receiver:    []byte(testAddress("rt-receiver")),
		BaseToken:   []byte(ibcBase),
		BaseAmount:  u256.NewUint(N),
		QuoteToken:  []byte(ibcDest),
		QuoteAmount: u256.NewUint(N),
		Kind:        z.TOKEN_ORDER_KIND_INITIALIZE,
		Metadata:    metaBytes,
	}

	err := v.verifyTokenOrderV2(0, cur, chanSrc, sender, newFunds(nil), path, order)
	uassert.NoError(t, err)
	uassert.Equal(t, int64(0), voucherBalanceOf(ibcBase, address(sender)))
	srcBal, _ := testStore.GetChannelBalanceV2(ChannelBalanceKeyV2(chanSrc, path, order.BaseToken, order.QuoteToken))
	uassert.Equal(t, u256.NewUint(N).ToString(), srcBal.ToString())

	err = v.acknowledgeTokenOrderV2(0, cur, chanSrc, path, order, z.Ack{Tag: tagAckFailure()})
	uassert.NoError(t, err)
	uassert.Equal(t, int64(N), voucherBalanceOf(ibcBase, address(sender)))
	srcBalAfter, hasBal := testStore.GetChannelBalanceV2(ChannelBalanceKeyV2(chanSrc, path, order.BaseToken, order.QuoteToken))
	uassert.True(t, !hasBal || srcBalAfter.IsZero())
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
	ibcDest := PredictWrappedTokenV2(path, uint32(chanDest), []byte(ibcBase), MetadataImage(mustDecodeTokenMetadata(metaBytes)))

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
		address(testAddress("rt-rly-mint")), nil, path, order, false)
	uassert.NoError(t, err)
	uassert.True(t, res.Status == types.PacketStatusSuccess)
	uassert.Equal(t, int64(N), voucherBalanceOf(ibcDest, address(receiver)))
}

func TestNativeBaseAmountNotUpscaled(cur realm, t *testing.T) {
	v := newTestImpl()

	const N = int64(1_000_000) // 1 ugnot (6-dec representation)
	const chanId = types.ChannelId(140)
	order := z.TokenOrderV2{
		Sender:      []byte(testAddress("native-noscale-sndr")),
		BaseToken:   []byte("ugnot"),
		BaseAmount:  u256.NewUint(uint64(N)),
		QuoteToken:  []byte("ibc/out-native"),
		QuoteAmount: u256.NewUint(uint64(N)),
		Kind:        z.TOKEN_ORDER_KIND_INITIALIZE,
	}
	f := newFunds(chain.NewCoins(chain.NewCoin("ugnot", N)))

	err := v.verifyTokenOrderV2(0, cur, chanId, testAddress("native-noscale-sndr"), f, u256.Zero(), order)

	uassert.NoError(t, err)
	uassert.True(t, f.isEmpty())
	bal, _ := testStore.GetChannelBalanceV2(ChannelBalanceKeyV2(chanId, u256.Zero(), order.BaseToken, order.QuoteToken))
	uassert.Equal(t, u256.NewUint(uint64(N)).ToString(), bal.ToString())
}

func TestInitializeOverflowAmountReturnsFailureAckNoMint(cur realm, t *testing.T) {
	v := newTestImpl()

	metaBytes := mustEncodeTokenMetadata(z.TokenMetadata{
		Implementation: []byte("grc20"),
		Initializer:    mustEncodeTokenInitializer(z.TokenInitializer{Name: "OVF", Symbol: "OVF", Decimals: 18}),
	})
	const destChan = types.ChannelId(150)
	ibcDenom := PredictWrappedTokenV2(u256.Zero(), uint32(destChan), []byte("uatom"), MetadataImage(mustDecodeTokenMetadata(metaBytes)))
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
	err := v.verifyTokenOrderV2(0, cur, chanA, senderA,
		newFunds(chain.NewCoins(chain.NewCoin("ugnot", math.MaxInt64))), u256.Zero(), orderA)
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
	err = v.verifyTokenOrderV2(0, cur, chanB, senderB,
		newFunds(chain.NewCoins(chain.NewCoin("ugnot", math.MaxInt64))), u256.Zero(), orderB)
	uassert.Error(t, err)
	balB, hasB := testStore.GetChannelBalanceV2(ChannelBalanceKeyV2(chanB, u256.Zero(), orderB.BaseToken, orderB.QuoteToken))
	uassert.True(t, !hasB || balB.IsZero())
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
		{"ibc/dl-18", "TK", 18}, // MaxDecimals; must succeed.
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
	ibcDenom := PredictWrappedTokenV2(u256.Zero(), uint32(destChan), []byte("uatom"), MetadataImage(mustDecodeTokenMetadata(metaBytes)))

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

	// First creation: decimals=18.
	uassert.NoError(t, v.mintVoucher(0, cur, ibcDenom, [32]byte{}, "Token", "TKN", 18, rx, amt))
	uassert.Equal(t, 18, voucherDecimalsOf(ibcDenom))

	// Second call with decimals=6 must reuse the existing voucher without changing it.
	uassert.NoError(t, v.mintVoucher(0, cur, ibcDenom, [32]byte{}, "Token", "TKN", 6, rx, amt))
	uassert.Equal(t, 18, voucherDecimalsOf(ibcDenom))
	uassert.Equal(t, int64(20), voucherBalanceOf(ibcDenom, address(rx)))
}
