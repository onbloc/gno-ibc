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
	order := z.TokenOrderV2{
		Sender:      []byte(testAddress("native-noscale-sndr")),
		BaseToken:   []byte("ugnot"),
		BaseAmount:  u256.NewUint(uint64(N)),
		QuoteToken:  []byte("ibc/out-native"),
		QuoteAmount: u256.NewUint(uint64(N)),
		Kind:        z.TOKEN_ORDER_KIND_INITIALIZE,
	}
	f := newFunds(chain.NewCoins(chain.NewCoin("ugnot", N)))

	err := v.verifyTokenOrderV2(0, cur, f, chanId, u256.Zero(), order)

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
	err := v.verifyTokenOrderV2(0, cur, newFunds(chain.NewCoins(chain.NewCoin("ugnot", math.MaxInt64))), chanA, u256.Zero(), orderA)
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
	err = v.verifyTokenOrderV2(0, cur, newFunds(chain.NewCoins(chain.NewCoin("ugnot", math.MaxInt64))), chanB, u256.Zero(), orderB)
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

	// First creation: decimals=18.
	uassert.NoError(t, v.mintVoucher(0, cur, ibcDenom, [32]byte{}, "Token", "TKN", 18, rx, amt))
	uassert.Equal(t, 18, voucherDecimalsOf(ibcDenom))

	// Second call with decimals=6 must reuse the existing voucher without changing it.
	uassert.NoError(t, v.mintVoucher(0, cur, ibcDenom, [32]byte{}, "Token", "TKN", 6, rx, amt))
	uassert.Equal(t, 18, voucherDecimalsOf(ibcDenom))
	uassert.Equal(t, int64(20), voucherBalanceOf(ibcDenom, address(rx)))
}

func TestTrimAmount(cur realm, t *testing.T) {
	tests := []struct {
		name            string
		tokenDecimals   uint8
		amount          uint64
		expectedTrimmed uint64
		expectedDust    uint64
	}{
		{"with dust", 18, 123456700000000000, 123456000000000000, 700000000000},
		{"no dust", 18, 1000000000000000000, 1000000000000000000, 0},
		{"target decimals only", 6, 1234560, 1234560, 0},
		{"less than target decimals", 4, 12345, 12345, 0},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			amount := u256.NewUint(tc.amount)
			result := trimAmount(tc.tokenDecimals, amount)

			expectedTrimmed := u256.NewUint(tc.expectedTrimmed)
			expectedDust := u256.NewUint(tc.expectedDust)

			uassert.Equal(t, expectedTrimmed.ToString(), result.Trimmed.ToString())
			uassert.Equal(t, expectedDust.ToString(), result.Dust.ToString())
		})
	}
}

func TestParseTokenInfo(cur realm, t *testing.T) {
	v := newTestImpl()

	// Create an 18-dec voucher first
	denom := "ibc/ABCDEF"
	v.mintVoucher(0, cur, denom, [32]byte{}, "Test Voucher", "TVST", 18, "sender", u256.NewUint(1000000))

	tests := []struct {
		denom          string
		expectVoucher  bool
		expectDecimals uint8
	}{
		{denom, true, 18},
		{"ugnot", false, 6},   // native tokens use target decimals
		{"unknown", false, 6}, // unknown tokens use target decimals
	}

	for _, tc := range tests {
		t.Run(tc.denom, func(t *testing.T) {
			info := v.parseTokenInfo(0, cur, []byte(tc.denom))
			uassert.Equal(t, tc.expectVoucher, info.isVoucher)
			uassert.Equal(t, tc.expectDecimals, info.decimals)
		})
	}
}

func TestScaleOutgoingTokenOrderInstruction(cur realm, t *testing.T) {
	v := newTestImpl()

	denom := "ibc/SCALE"
	sender := testAddress("scale-sender")
	v.mintVoucher(0, cur, denom, [32]byte{}, "Voucher", "VOU", 18, sender, u256.NewUint(1000000000000000000))

	tests := []struct {
		name        string
		version     uint8
		baseAmount  uint64
		quoteAmount uint64
		expectError string
		expectBase  uint64
		expectQuote uint64
	}{
		{
			name:        "scales voucher amounts",
			version:     z.INSTR_VERSION_2,
			baseAmount:  123456,
			quoteAmount: 123000,
			expectBase:  123456000000000000,
			expectQuote: 123000000000000000,
		},
		{
			name:        "unsupported version rejected",
			version:     z.INSTR_VERSION_0,
			baseAmount:  123456,
			quoteAmount: 123000,
			expectError: "unsupported token order version",
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			order := z.TokenOrderV2{
				Sender:      []byte(sender),
				Receiver:    []byte(testAddress("scale-receiver")),
				BaseToken:   []byte(denom),
				BaseAmount:  u256.NewUint(tc.baseAmount),
				QuoteToken:  []byte("ibc/OUT"),
				QuoteAmount: u256.NewUint(tc.quoteAmount),
				Kind:        z.TOKEN_ORDER_KIND_INITIALIZE,
			}

			instruction := z.Instruction{
				Version: tc.version,
				Opcode:  z.OP_TOKEN_ORDER,
				Operand: mustEncodeTokenOrderV2(order),
			}

			scaled, err := v.scaleOutgoingTokenOrderInstruction(0, cur, instruction)
			if tc.expectError != "" {
				uassert.ErrorContains(t, err, tc.expectError)
				return
			}

			uassert.NoError(t, err)

			got, err := z.DecodeTokenOrderV2(scaled.Operand)
			uassert.NoError(t, err)
			uassert.Equal(t, u256.NewUint(tc.expectBase).ToString(), got.BaseAmount.ToString())
			uassert.Equal(t, u256.NewUint(tc.expectQuote).ToString(), got.QuoteAmount.ToString())
		})
	}
}

func TestScaleOutgoingForwardInstruction(cur realm, t *testing.T) {
	v := newTestImpl()

	denom := "ibc/FORWARD-SCALE"
	sender := testAddress("fwd-scale-sender")
	v.mintVoucher(0, cur, denom, [32]byte{}, "Forward", "FWD", 18, sender, u256.NewUint(1000000000000000000))

	order := z.TokenOrderV2{
		Sender:      []byte(sender),
		Receiver:    []byte(testAddress("fwd-scale-receiver")),
		BaseToken:   []byte(denom),
		BaseAmount:  u256.NewUint(123456),
		QuoteToken:  []byte("ibc/FORWARD-OUT"),
		QuoteAmount: u256.NewUint(123000),
		Kind:        z.TOKEN_ORDER_KIND_ESCROW,
	}

	forward := z.Forward{
		Path:             u256.NewUint(12),
		TimeoutTimestamp: 999,
		Instruction:      batchMustOrderInstruction(order),
	}

	instruction := z.Instruction{
		Version: z.INSTR_VERSION_0,
		Opcode:  z.OP_FORWARD,
		Operand: mustForwardBytes(forward),
	}

	scaled, err := v.scaleOutgoingInstructionAmounts(0, cur, instruction)
	uassert.NoError(t, err)

	gotForward, err := z.DecodeForward(scaled.Operand)
	uassert.NoError(t, err)

	gotOrder, err := z.DecodeTokenOrderV2(gotForward.Instruction.Operand)
	uassert.NoError(t, err)
	uassert.Equal(t, u256.NewUint(123456000000000000).ToString(), gotOrder.BaseAmount.ToString())
	uassert.Equal(t, u256.NewUint(123000000000000000).ToString(), gotOrder.QuoteAmount.ToString())
}

func TestScaleOutgoingForwardBatchInstruction(cur realm, t *testing.T) {
	v := newTestImpl()

	denom := "ibc/FORWARD-BATCH-SCALE"
	sender := testAddress("fwd-batch-sender")
	v.mintVoucher(0, cur, denom, [32]byte{}, "ForwardBatch", "FWDB", 18, sender, u256.NewUint(1000000000000000000))

	order := z.TokenOrderV2{
		Sender:      []byte(sender),
		Receiver:    []byte(testAddress("fwd-batch-receiver")),
		BaseToken:   []byte(denom),
		BaseAmount:  u256.NewUint(654321),
		QuoteToken:  []byte("ibc/FORWARD-BATCH-OUT"),
		QuoteAmount: u256.NewUint(654000),
		Kind:        z.TOKEN_ORDER_KIND_ESCROW,
	}

	forward := z.Forward{
		Path:             u256.NewUint(12),
		TimeoutTimestamp: 999,
		Instruction: batchMustBatchInstruction(z.Batch{Instructions: []z.Instruction{
			batchMustCallInstruction(batchCall(sender, "")),
			batchMustOrderInstruction(order),
		}}),
	}

	instruction := z.Instruction{
		Version: z.INSTR_VERSION_0,
		Opcode:  z.OP_FORWARD,
		Operand: mustForwardBytes(forward),
	}

	scaled, err := v.scaleOutgoingInstructionAmounts(0, cur, instruction)
	uassert.NoError(t, err)

	gotForward, err := z.DecodeForward(scaled.Operand)
	uassert.NoError(t, err)

	gotBatch, err := z.DecodeBatch(gotForward.Instruction.Operand)
	uassert.NoError(t, err)

	gotOrder, err := z.DecodeTokenOrderV2(gotBatch.Instructions[1].Operand)
	uassert.NoError(t, err)
	uassert.Equal(t, u256.NewUint(654321000000000000).ToString(), gotOrder.BaseAmount.ToString())
	uassert.Equal(t, u256.NewUint(654000000000000000).ToString(), gotOrder.QuoteAmount.ToString())
}

func TestDecodeLocalOrderInstruction(cur realm, t *testing.T) {
	v := newTestImpl()

	meta := mustEncodeTokenMetadata(z.TokenMetadata{
		Implementation: []byte("grc20"),
		Initializer:    mustEncodeTokenInitializer(z.TokenInitializer{Name: "USD Coin", Symbol: "USDC", Decimals: 18}),
	})

	tests := []struct {
		name        string
		baseAmount  uint64
		quoteAmount uint64
		expectError string
		expectBase  uint64
		expectQuote uint64
	}{
		{
			name:        "exact wire amount converts to local",
			baseAmount:  123456000000000000,
			quoteAmount: 123000000000000000,
			expectBase:  123456,
			expectQuote: 123000,
		},
		{
			name:        "dust is rejected",
			baseAmount:  123456700000000000,
			quoteAmount: 123456000000000000,
			expectError: "decimal dust is not allowed",
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			order := z.TokenOrderV2{
				Sender:      []byte("remote-sender"),
				Receiver:    []byte(testAddress("local-receiver")),
				BaseToken:   []byte("uatom"),
				BaseAmount:  u256.NewUint(tc.baseAmount),
				QuoteToken:  []byte("ibc/local"),
				QuoteAmount: u256.NewUint(tc.quoteAmount),
				Kind:        z.TOKEN_ORDER_KIND_INITIALIZE,
				Metadata:    meta,
			}
			instruction := z.Instruction{
				Version: z.INSTR_VERSION_2,
				Opcode:  z.OP_TOKEN_ORDER,
				Operand: mustEncodeTokenOrderV2(order),
			}

			got, err := v.decodeLocalOrderInstruction(0, cur, instruction)
			if tc.expectError != "" {
				uassert.ErrorContains(t, err, tc.expectError)
				return
			}

			uassert.NoError(t, err)
			uassert.Equal(t, u256.NewUint(tc.expectBase).ToString(), got.BaseAmount.ToString())
			uassert.Equal(t, u256.NewUint(tc.expectQuote).ToString(), got.QuoteAmount.ToString())
		})
	}
}

func TestTrimAmountMaxInt64Boundary(cur realm, t *testing.T) {
	v := newTestImpl()

	denom := "ibc/max64-boundary"
	sender := testAddress("max64-sender")
	v.mintVoucher(0, cur, denom, [32]byte{}, "Large", "LARGE", 18, sender, u256.NewUint(9223372036854775807))

	tests := []struct {
		name          string
		baseAmount    uint64
		expectTrimmed uint64
		expectDust    uint64
	}{
		{
			name:          "MaxInt64 - 18dec gets trimmed",
			baseAmount:    9223372036854775807,
			expectTrimmed: 9223372000000000000,
			expectDust:    36854775807,
		},
		{
			name:          "MaxInt64/2 - 18dec gets trimmed",
			baseAmount:    4611686018427387903,
			expectTrimmed: 4611686000000000000,
			expectDust:    18427387903,
		},
		{
			name:          "Near MaxInt64 - 18dec gets trimmed",
			baseAmount:    9000000000000000000,
			expectTrimmed: 9000000000000000000,
			expectDust:    0,
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			amount := u256.NewUint(tc.baseAmount)
			result := trimAmount(18, amount)

			expectedTrimmed := u256.NewUint(tc.expectTrimmed)
			expectedDust := u256.NewUint(tc.expectDust)

			uassert.Equal(t, expectedTrimmed.ToString(), result.Trimmed.ToString())
			uassert.Equal(t, expectedDust.ToString(), result.Dust.ToString())
		})
	}
}

func TestScaleOutgoingMaxInt64Boundary(cur realm, t *testing.T) {
	v := newTestImpl()

	denom := "ibc/max64-send"
	sender := testAddress("max64-send-sender")
	v.mintVoucher(0, cur, denom, [32]byte{}, "Max64", "MAX64", 18, sender, u256.NewUint(9223372))

	order := z.TokenOrderV2{
		Sender:      []byte(sender),
		Receiver:    []byte(testAddress("max64-receiver")),
		BaseToken:   []byte(denom),
		BaseAmount:  u256.NewUint(9223372),
		QuoteToken:  []byte("ibc/out"),
		QuoteAmount: u256.NewUint(9223372),
		Kind:        z.TOKEN_ORDER_KIND_ESCROW,
	}

	instruction := z.Instruction{
		Version: z.INSTR_VERSION_2,
		Opcode:  z.OP_TOKEN_ORDER,
		Operand: mustEncodeTokenOrderV2(order),
	}

	scaled, err := v.scaleOutgoingTokenOrderInstruction(0, cur, instruction)
	uassert.NoError(t, err)

	got, err := z.DecodeTokenOrderV2(scaled.Operand)
	uassert.NoError(t, err)

	expectedTrimmed := u256.NewUint(9223372000000000000)
	uassert.Equal(t, expectedTrimmed.ToString(), got.BaseAmount.ToString())
	uassert.Equal(t, expectedTrimmed.ToString(), got.QuoteAmount.ToString())
}

func mustEncodeTokenOrderV2(order z.TokenOrderV2) []byte {
	out, err := z.EncodeTokenOrderV2(order)
	if err != nil {
		panic(err)
	}
	return out
}
