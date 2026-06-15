package impl

import (
	"chain"
	"math"
	"testing"

	u256 "gno.land/p/gnoswap/uint256"
	"gno.land/p/nt/uassert/v0"
	z "gno.land/p/onbloc/ibc/zkgm"
	zkgm "gno.land/r/onbloc/ibc/apps/ucs03_zkgm"
	core "gno.land/r/onbloc/ibc/core"
)

func TestInitializeDecimalsAgnosticAccounting(cur realm, t *testing.T) {
	resetTokenOrderTest(cur)

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
		res, err := (&ZkgmV1{}).executeTokenOrderV2(cur,
			core.NewPacket(cross(cur), core.ChannelId(1), core.ChannelId(tc.dest), nil, 0, 0),
			relayer, u256.NewUint(tc.path),
			z.TokenOrderV2{
				Sender: []byte("s"), Receiver: []byte(rx), BaseToken: base,
				BaseAmount: u256.NewUint(N), QuoteToken: []byte(denom), QuoteAmount: u256.NewUint(N),
				Kind: z.TOKEN_ORDER_KIND_INITIALIZE, Metadata: meta,
			}, false)
		uassert.NoError(t, err)
		uassert.True(t, res.Status == core.PacketStatusSuccess)
		uassert.Equal(t, int64(N), VoucherBalanceOf(denom, address(rx)))
		uassert.Equal(t, int(tc.decimals), VoucherDecimalsOf(denom))
	}
}

func TestBaseAmountPreservedThroughLockAndRefund(cur realm, t *testing.T) {
	resetTokenOrderTest(cur)

	const N = uint64(100)
	const chanSrc = core.ChannelId(130)
	path := u256.Zero()
	ibcBase := "ibc/rt-base"
	sender := testAddress("rt-sender")

	uassert.NoError(t, zkgm.MintVoucher(cross(cur), ibcBase, ibcBase, [32]byte{}, "", "", 0, sender, u256.NewUint(N)))

	metaBytes := mustEncodeTokenMetadata(z.TokenMetadata{
		Implementation: []byte("grc20"),
		Initializer:    mustEncodeTokenInitializer(z.TokenInitializer{Name: "RT", Symbol: "RT", Decimals: 6}),
	})
	ibcDest := PredictWrappedTokenV2(path, uint32(core.ChannelId(131)), []byte(ibcBase), MetadataImage(mustDecodeTokenMetadata(metaBytes)))

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

	err := (&ZkgmV1{}).verifyTokenOrderV2(cur, chanSrc, sender, newSentCoinBudget(nil), path, order)
	uassert.NoError(t, err)
	uassert.Equal(t, int64(0), VoucherBalanceOf(ibcBase, address(sender)))
	srcBal := zkgm.GetChannelBalanceV2(ChannelBalanceKeyV2(chanSrc, path, order.BaseToken, order.QuoteToken))
	uassert.Equal(t, u256.NewUint(N).ToString(), srcBal.ToString())

	err = (&ZkgmV1{}).acknowledgeTokenOrderV2(cur, chanSrc, path, order, z.Ack{Tag: tagAckFailure()})
	uassert.NoError(t, err)
	uassert.Equal(t, int64(N), VoucherBalanceOf(ibcBase, address(sender)))
	srcBalAfter := zkgm.GetChannelBalanceV2(ChannelBalanceKeyV2(chanSrc, path, order.BaseToken, order.QuoteToken))
	uassert.True(t, srcBalAfter == nil || srcBalAfter.IsZero())
}

func TestBaseAmountPreservedThroughMint(cur realm, t *testing.T) {
	resetTokenOrderTest(cur)

	const N = uint64(100)
	const chanSrc = core.ChannelId(132)
	const chanDest = core.ChannelId(133)
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

	res, err := (&ZkgmV1{}).executeTokenOrderV2(cur,
		core.NewPacket(cross(cur), chanSrc, chanDest, nil, 0, 0),
		address(testAddress("rt-rly-mint")), path, order, false)
	uassert.NoError(t, err)
	uassert.True(t, res.Status == core.PacketStatusSuccess)
	uassert.Equal(t, int64(N), VoucherBalanceOf(ibcDest, address(receiver)))
}

func TestNativeBaseAmountNotUpscaled(cur realm, t *testing.T) {
	resetTokenOrderTest(cur)

	const N = int64(1_000_000) // 1 ugnot (6-dec representation)
	const chanId = core.ChannelId(140)
	order := z.TokenOrderV2{
		Sender:      []byte(testAddress("native-noscale-sndr")),
		BaseToken:   []byte("ugnot"),
		BaseAmount:  u256.NewUint(uint64(N)),
		QuoteToken:  []byte("ibc/out-native"),
		QuoteAmount: u256.NewUint(uint64(N)),
		Kind:        z.TOKEN_ORDER_KIND_INITIALIZE,
	}
	budget := newSentCoinBudget(chain.NewCoins(chain.NewCoin("ugnot", N)))

	err := (&ZkgmV1{}).verifyTokenOrderV2(cur, chanId, testAddress("native-noscale-sndr"), budget, u256.Zero(), order)

	uassert.NoError(t, err)
	uassert.True(t, budget.drained())
	bal := zkgm.GetChannelBalanceV2(ChannelBalanceKeyV2(chanId, u256.Zero(), order.BaseToken, order.QuoteToken))
	uassert.Equal(t, u256.NewUint(uint64(N)).ToString(), bal.ToString())
}

func TestInitializeOverflowAmountReturnsFailureAckNoMint(cur realm, t *testing.T) {
	resetTokenOrderTest(cur)

	metaBytes := mustEncodeTokenMetadata(z.TokenMetadata{
		Implementation: []byte("grc20"),
		Initializer:    mustEncodeTokenInitializer(z.TokenInitializer{Name: "OVF", Symbol: "OVF", Decimals: 18}),
	})
	const destChan = core.ChannelId(150)
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
	packet := core.NewPacket(cross(cur), core.ChannelId(1), destChan, data, 0, 0)

	res := (&ZkgmV1{}).Recv(cur, packet, address(testAddress("ovf-rly")), nil)

	uassert.True(t, res.Status == core.PacketStatusFailure)
	uassert.Equal(t, string(universalErrorAck()), string(res.Ack))
	uassert.Equal(t, int64(0), VoucherBalanceOf(ibcDenom, address(receiver)))
}

func TestSendBaseAmountInt64Boundary(cur realm, t *testing.T) {
	resetTokenOrderTest(cur)

	maxI64 := u256.NewUint(uint64(math.MaxInt64))

	senderA := testAddress("bnd-sndr-a")
	const chanA = core.ChannelId(160)
	orderA := z.TokenOrderV2{
		Sender:      []byte(senderA),
		BaseToken:   []byte("ugnot"),
		BaseAmount:  maxI64,
		QuoteToken:  []byte("ibc/bnd-out-a"),
		QuoteAmount: maxI64,
		Kind:        z.TOKEN_ORDER_KIND_INITIALIZE,
	}
	err := (&ZkgmV1{}).verifyTokenOrderV2(cur, chanA, senderA,
		newSentCoinBudget(chain.NewCoins(chain.NewCoin("ugnot", math.MaxInt64))), u256.Zero(), orderA)
	uassert.NoError(t, err)
	balA := zkgm.GetChannelBalanceV2(ChannelBalanceKeyV2(chanA, u256.Zero(), orderA.BaseToken, orderA.QuoteToken))
	uassert.Equal(t, maxI64.ToString(), balA.ToString())

	senderB := testAddress("bnd-sndr-b")
	const chanB = core.ChannelId(161)
	overAmt := new(u256.Uint).Add(maxI64, u256.NewUint(1))
	orderB := z.TokenOrderV2{
		Sender:      []byte(senderB),
		BaseToken:   []byte("ugnot"),
		BaseAmount:  overAmt,
		QuoteToken:  []byte("ibc/bnd-out-b"),
		QuoteAmount: overAmt,
		Kind:        z.TOKEN_ORDER_KIND_INITIALIZE,
	}
	err = (&ZkgmV1{}).verifyTokenOrderV2(cur, chanB, senderB,
		newSentCoinBudget(chain.NewCoins(chain.NewCoin("ugnot", math.MaxInt64))), u256.Zero(), orderB)
	uassert.Error(t, err)
	balB := zkgm.GetChannelBalanceV2(ChannelBalanceKeyV2(chanB, u256.Zero(), orderB.BaseToken, orderB.QuoteToken))
	uassert.True(t, balB == nil || balB.IsZero())
}

func TestVoucherDecimalsWithinLimit(cur realm, t *testing.T) {
	resetTokenOrderTest(cur)

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
		uassert.NoError(t, zkgm.MintVoucher(cross(cur), tc.denom, "base", [32]byte{}, "T", tc.sym, tc.decimals, rx, amt))
		uassert.Equal(t, int(tc.decimals), VoucherDecimalsOf(tc.denom))
	}
}

func TestInitializeDecimalsExceedMaxReturnsFailureAck(cur realm, t *testing.T) {
	resetTokenOrderTest(cur)

	metaBytes := mustEncodeTokenMetadata(z.TokenMetadata{
		Implementation: []byte("grc20"),
		Initializer: mustEncodeTokenInitializer(z.TokenInitializer{
			Name: "Over", Symbol: "OVD", Decimals: 19,
		}),
	})
	const destChan = core.ChannelId(180)
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
	packet := core.NewPacket(cross(cur), core.ChannelId(1), destChan, data, 0, 0)

	res := (&ZkgmV1{}).Recv(cur, packet, address(testAddress("ovd-rly")), nil)

	uassert.True(t, res.Status == core.PacketStatusFailure)
	uassert.Equal(t, string(universalErrorAck()), string(res.Ack))
	uassert.False(t, zkgm.HasVoucher(ibcDenom))
}

func TestReInitializeSameIBCDenomPreservesDecimals(cur realm, t *testing.T) {
	resetTokenOrderTest(cur)

	ibcDenom := "ibc/reint-test"
	rx := testAddress("reint-rx")
	amt := u256.NewUint(10)

	// First creation: decimals=18.
	uassert.NoError(t, zkgm.MintVoucher(cross(cur), ibcDenom, "base", [32]byte{}, "Token", "TKN", 18, rx, amt))
	uassert.Equal(t, 18, VoucherDecimalsOf(ibcDenom))

	// Second call with decimals=6 must reuse the existing voucher without changing it.
	uassert.NoError(t, zkgm.MintVoucher(cross(cur), ibcDenom, "base", [32]byte{}, "Token", "TKN", 6, rx, amt))
	uassert.Equal(t, 18, VoucherDecimalsOf(ibcDenom))
	uassert.Equal(t, int64(20), VoucherBalanceOf(ibcDenom, address(rx)))
}
