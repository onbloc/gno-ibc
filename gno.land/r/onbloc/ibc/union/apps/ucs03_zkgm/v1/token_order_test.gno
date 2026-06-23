package impl

import (
	"bytes"
	"chain"
	"testing"
	"time"

	types "gno.land/p/onbloc/ibc/union/types"

	u256 "gno.land/p/gnoswap/uint256"
	"gno.land/p/nt/uassert/v0"
	z "gno.land/p/onbloc/ibc/union/zkgm"
	tb "gno.land/p/onbloc/ibc/union/zkgm/tokenbucket"
	core "gno.land/r/onbloc/ibc/union/core"
)

const tokenOrderTestRealmPath = "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/v1"

func TestIsZeroImage(t *testing.T) {
	uassert.True(t, isZeroImage([32]byte{}))
	uassert.False(t, isZeroImage([32]byte{31: 0x01}))
}

func TestEncodeTokenOrderSuccessAck(t *testing.T) {
	ackBytes, err := encodeTokenOrderSuccessAck(fillTypeMarketMaker(), []byte("maker"))
	uassert.NoError(t, err)

	outerAck, err := z.DecodeAck(ackBytes)
	uassert.NoError(t, err)
	uassert.True(t, outerAck.Tag.Eq(tagAckSuccess()))

	orderAck, err := z.DecodeTokenOrderAck(outerAck.InnerAck)
	uassert.NoError(t, err)
	uassert.True(t, orderAck.FillType.Eq(fillTypeMarketMaker()))
	uassert.Equal(t, "maker", string(orderAck.MarketMaker))
}

func TestProtocolFillMint(cur realm, t *testing.T) {
	v := newTestImpl()
	wrapped := "ibc/direct-protocol-mint"
	meta := z.TokenMetadata{
		Implementation: []byte("grc20"),
		Initializer:    mustEncodeTokenInitializer(z.TokenInitializer{Name: "Direct Token", Symbol: "DIR", Decimals: 6}),
	}
	path := u256.NewUint(9)
	receiver := testAddress("direct-mint-rx")
	relayer := testAddress("direct-mint-rly")

	res, err := v.protocolFillMint(0, cur, types.ChannelId(15), path, []byte("ugnot"), wrapped, address(receiver), address(relayer), u256.NewUint(100), u256.NewUint(95), &meta, true)

	uassert.NoError(t, err)
	uassert.True(t, res.Status == types.PacketStatusSuccess)
	assertProtocolAck(t, res.Acknowledgement)
	uassert.Equal(t, int64(95), voucherBalanceOf(wrapped, address(receiver)))
	uassert.Equal(t, int64(5), voucherBalanceOf(wrapped, address(relayer)))

	foreign, ok := testStore.GetForeignToken(wrapped)
	uassert.True(t, ok)
	uassert.Equal(t, "ugnot", string(foreign))
	_, ok = testStore.GetTokenOrigin(wrapped)
	uassert.True(t, ok)
	image, ok := testStore.GetMetadataImageOf(wrapped)
	uassert.True(t, ok)
	uassert.True(t, image == MetadataImage(meta))
}

func TestMarketMakerFillV2(cur realm, t *testing.T) {
	v := newTestImpl()
	maker := testAddress("direct-mm-maker")
	receiver := testAddress("direct-mm-rx")

	cases := []struct {
		name       string
		quoteDenom string
		seed       bool
		relayerMsg []byte
		wantAck    string
	}{
		{"unknown quote token", "native-mm-quote", false, nil, "only-maker"},
		{"voucher quote token", "ibc/direct-mm-quote", true, []byte("maker-bytes"), "market-maker"},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			if tc.seed {
				uassert.NoError(t, v.mintVoucher(0, cur, tc.quoteDenom, [32]byte{}, "", "", 0, maker, u256.NewUint(30)))
			}

			res, err := v.marketMakerFillV2(0, cur, address(maker), tc.relayerMsg, z.TokenOrderV2{
				Receiver:    []byte(receiver),
				QuoteToken:  []byte(tc.quoteDenom),
				QuoteAmount: u256.NewUint(12),
			})

			uassert.NoError(t, err)
			uassert.True(t, res.Status == types.PacketStatusSuccess)
			if tc.wantAck == "only-maker" {
				uassert.True(t, bytes.Equal(z.ACK_ERR_ONLY_MAKER, res.Acknowledgement))
				return
			}

			assertMarketMakerAck(t, res.Acknowledgement, string(tc.relayerMsg))
			uassert.Equal(t, int64(18), voucherBalanceOf(tc.quoteDenom, address(maker)))
			uassert.Equal(t, int64(12), voucherBalanceOf(tc.quoteDenom, address(receiver)))
		})
	}
}

func TestRefundV2(cur realm, t *testing.T) {
	v := newTestImpl()
	path := u256.NewUint(3)
	sourceChannel := types.ChannelId(16)
	baseToken := "ibc/direct-refund"
	sender := testAddress("direct-refund-sender")
	order := z.TokenOrderV2{
		Kind:        z.TOKEN_ORDER_KIND_ESCROW,
		Sender:      []byte(sender),
		BaseToken:   []byte(baseToken),
		BaseAmount:  u256.NewUint(7),
		QuoteToken:  []byte("quote"),
		QuoteAmount: u256.NewUint(7),
	}
	v.increaseChannelBalanceV2(0, cur, sourceChannel, path, order.BaseToken, order.QuoteToken, order.BaseAmount)
	uassert.NoError(t, v.mintVoucher(0, cur, baseToken, [32]byte{}, "", "", 0, cur.Address().String(), order.BaseAmount))

	err := v.refundV2(0, cur, path, sourceChannel, order)

	uassert.NoError(t, err)
	assertNoChannelBalance(t, sourceChannel, path, order)
	uassert.Equal(t, int64(7), voucherBalanceOf(baseToken, address(sender)))

	err = v.refundV2(0, cur, path, sourceChannel, z.TokenOrderV2{Kind: 99})
	uassert.ErrorContains(t, err, "unsupported token order kind for refund")
}

func TestSettleEscrowedV2(cur realm, t *testing.T) {
	v := newTestImpl()
	path := u256.NewUint(4)
	sourceChannel := types.ChannelId(17)
	baseToken := "ibc/direct-settle"
	recipient := testAddress("direct-settle-rx")
	order := z.TokenOrderV2{
		BaseToken:   []byte(baseToken),
		BaseAmount:  u256.NewUint(9),
		QuoteToken:  []byte("quote"),
		QuoteAmount: u256.NewUint(9),
	}
	v.increaseChannelBalanceV2(0, cur, sourceChannel, path, order.BaseToken, order.QuoteToken, order.BaseAmount)
	uassert.NoError(t, v.mintVoucher(0, cur, baseToken, [32]byte{}, "", "", 0, cur.Address().String(), order.BaseAmount))

	err := v.settleEscrowedV2(0, cur, sourceChannel, path, order, recipient)

	uassert.NoError(t, err)
	assertNoChannelBalance(t, sourceChannel, path, order)
	uassert.Equal(t, int64(9), voucherBalanceOf(baseToken, address(recipient)))
}

func TestLocalTokenEscrow(cur realm, t *testing.T) {
	v := newTestImpl()
	denom := "ibc/direct-local-escrow"
	sender := testAddress("direct-escrow-snd")
	uassert.NoError(t, v.mintVoucher(0, cur, denom, [32]byte{}, "", "", 0, sender, u256.NewUint(11)))

	err := v.localTokenEscrow(0, cur, denom, sender, newFunds(nil), u256.NewUint(5))

	uassert.NoError(t, err)
	uassert.Equal(t, int64(6), voucherBalanceOf(denom, address(sender)))
	uassert.Equal(t, int64(5), voucherBalanceOf(denom, cur.Address()))

	f := newFunds(parseCoins("7ugnot"))
	err = v.localTokenEscrow(0, cur, "ugnot", sender, f, u256.NewUint(7))
	uassert.NoError(t, err)
	uassert.True(t, f.isEmpty())
}

func TestLocalTokenUnescrow(cur realm, t *testing.T) {
	v := newTestImpl()
	denom := "ibc/direct-local-unescrow"
	recipient := testAddress("direct-unescrow-rx")
	uassert.NoError(t, v.mintVoucher(0, cur, denom, [32]byte{}, "", "", 0, cur.Address().String(), u256.NewUint(13)))

	err := v.localTokenUnescrow(0, cur, denom, recipient, u256.NewUint(8))

	uassert.NoError(t, err)
	uassert.Equal(t, int64(5), voucherBalanceOf(denom, cur.Address()))
	uassert.Equal(t, int64(8), voucherBalanceOf(denom, address(recipient)))
}

func TestRefundIBCVoucher(cur realm, t *testing.T) {
	v := newTestImpl()
	denom := "ibc/direct-refund-voucher"
	recipient := testAddress("direct-refund-rx")
	image := [32]byte{0x44}
	testStore.SetMetadataImageOf(0, cur, denom, image)

	err := v.refundIBCVoucher(0, cur, []byte(denom), recipient, u256.NewUint(6))

	uassert.NoError(t, err)
	uassert.Equal(t, int64(6), voucherBalanceOf(denom, address(recipient)))
	stored, ok := testStore.GetMetadataImageOf(denom)
	uassert.True(t, ok)
	uassert.True(t, stored == image)
}

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

func TestVerifyTokenOrderV2(cur realm, t *testing.T) {
	cases := []struct {
		name        string
		channelId   types.ChannelId
		path        *u256.Uint
		funds       *funds
		crossSender string
		setup       func(cur realm, t *testing.T, v *ucs03ZkgmV1) z.TokenOrderV2
		wantErr     string
		after       func(t *testing.T, order z.TokenOrderV2, funds *funds)
	}{
		{
			name:      "native initialize requires sent coin",
			channelId: types.ChannelId(4),
			path:      u256.Zero(),
			funds:     newFunds(chain.NewCoins(chain.NewCoin("ugnot", 13))),
			setup: func(cur realm, t *testing.T, v *ucs03ZkgmV1) z.TokenOrderV2 {
				return z.TokenOrderV2{
					Sender:     []byte(testAddress("v1-native-sender")),
					BaseToken:  []byte("ugnot"),
					BaseAmount: u256.NewUint(13),
					QuoteToken: []byte("quote"),
					Kind:       z.TOKEN_ORDER_KIND_INITIALIZE,
				}
			},
		},
		{
			name:      "native escrow consumes funds and increases channel balance",
			channelId: types.ChannelId(20),
			path:      u256.Zero(),
			funds:     newFunds(chain.NewCoins(chain.NewCoin("ugnot", 13))),
			setup: func(cur realm, t *testing.T, v *ucs03ZkgmV1) z.TokenOrderV2 {
				return z.TokenOrderV2{
					Sender:      []byte(testAddress("native-escrow-sender")),
					BaseToken:   []byte("ugnot"),
					BaseAmount:  u256.NewUint(13),
					QuoteToken:  []byte("quote-native"),
					QuoteAmount: u256.NewUint(13),
					Kind:        z.TOKEN_ORDER_KIND_ESCROW,
				}
			},
			after: func(t *testing.T, order z.TokenOrderV2, funds *funds) {
				uassert.True(t, funds.isEmpty())
				balance, _ := testStore.GetChannelBalanceV2(ChannelBalanceKeyV2(types.ChannelId(20), u256.Zero(), order.BaseToken, order.QuoteToken))
				uassert.Equal(t, "13", balance.ToString())
			},
		},
		{
			name:      "voucher burn insufficient balance rejected",
			channelId: types.ChannelId(21),
			path:      u256.Zero(),
			funds:     newFunds(nil),
			setup: func(cur realm, t *testing.T, v *ucs03ZkgmV1) z.TokenOrderV2 {
				sender := testAddress("burn-insuf-sender")
				baseToken := "ibc/burn-insuf"
				uassert.NoError(t, v.mintVoucher(0, cur, baseToken, [32]byte{}, "", "", 0, sender, u256.NewUint(10)))
				return z.TokenOrderV2{
					Sender:      []byte(sender),
					BaseToken:   []byte(baseToken),
					BaseAmount:  u256.NewUint(50),
					QuoteToken:  []byte("quote"),
					QuoteAmount: u256.NewUint(50),
					Kind:        z.TOKEN_ORDER_KIND_ESCROW,
				}
			},
			wantErr: "error",
			after: func(t *testing.T, order z.TokenOrderV2, funds *funds) {
				uassert.Equal(t, int64(10), voucherBalanceOf(string(order.BaseToken), address(order.Sender)))
			},
		},
		{
			name:      "native unescrow rejected before funds consume",
			channelId: types.ChannelId(0),
			path:      u256.Zero(),
			funds:     newFunds(chain.NewCoins(chain.NewCoin("native-unescrow", 13))),
			setup: func(cur realm, t *testing.T, v *ucs03ZkgmV1) z.TokenOrderV2 {
				baseDenom := "native-unescrow"
				testStore.SetTokenOrigin(0, cur, baseDenom, u256.Zero())
				return z.TokenOrderV2{
					Sender:      []byte(testAddress("native-unescrow")),
					BaseToken:   []byte(baseDenom),
					BaseAmount:  u256.NewUint(13),
					QuoteToken:  []byte("ugnot"),
					QuoteAmount: u256.NewUint(13),
					Kind:        z.TOKEN_ORDER_KIND_UNESCROW,
				}
			},
			wantErr: "invalid token order unescrow",
			after: func(t *testing.T, order z.TokenOrderV2, funds *funds) {
				uassert.False(t, funds.isEmpty())
			},
		},
		{
			name:        "unescrow v1 prediction passes",
			channelId:   types.ChannelId(70),
			path:        u256.Zero(),
			funds:       newFunds(nil),
			crossSender: testAddress("v1-predict-sender"),
			setup: func(cur realm, t *testing.T, v *ucs03ZkgmV1) z.TokenOrderV2 {
				const destChan = types.ChannelId(70)
				sender := testAddress("v1-predict-sender")
				quoteToken := []byte("ugnot")
				baseDenom := PredictWrappedToken(u256.Zero(), uint32(destChan), quoteToken)
				origin, err := z.UpdateChannelPath(u256.Zero(), uint32(destChan))
				uassert.NoError(t, err)
				testStore.SetTokenOrigin(0, cur, baseDenom, origin)
				uassert.NoError(t, v.mintVoucher(0, cur, baseDenom, [32]byte{}, "", "", 0, sender, u256.NewUint(100)))
				return z.TokenOrderV2{
					Sender:      []byte(sender),
					BaseToken:   []byte(baseDenom),
					BaseAmount:  u256.NewUint(50),
					QuoteToken:  quoteToken,
					QuoteAmount: u256.NewUint(50),
					Kind:        z.TOKEN_ORDER_KIND_UNESCROW,
				}
			},
			after: func(t *testing.T, order z.TokenOrderV2, funds *funds) {
				uassert.Equal(t, int64(50), voucherBalanceOf(string(order.BaseToken), address(order.Sender)))
			},
		},
		{
			name:        "unescrow v2 prediction with image passes",
			channelId:   types.ChannelId(71),
			path:        u256.Zero(),
			funds:       newFunds(nil),
			crossSender: testAddress("v2-predict-sender"),
			setup: func(cur realm, t *testing.T, v *ucs03ZkgmV1) z.TokenOrderV2 {
				const destChan = types.ChannelId(71)
				sender := testAddress("v2-predict-sender")
				quoteToken := []byte("ugnot")
				image := [32]byte{0x01}
				baseDenom := PredictWrappedTokenV2(u256.Zero(), uint32(destChan), quoteToken, image)
				origin, err := z.UpdateChannelPath(u256.Zero(), uint32(destChan))
				uassert.NoError(t, err)
				testStore.SetTokenOrigin(0, cur, baseDenom, origin)
				testStore.SetMetadataImageOf(0, cur, baseDenom, image)
				uassert.NoError(t, v.mintVoucher(0, cur, baseDenom, image, "", "", 0, sender, u256.NewUint(100)))
				return z.TokenOrderV2{
					Sender:      []byte(sender),
					BaseToken:   []byte(baseDenom),
					BaseAmount:  u256.NewUint(50),
					QuoteToken:  quoteToken,
					QuoteAmount: u256.NewUint(50),
					Kind:        z.TOKEN_ORDER_KIND_UNESCROW,
				}
			},
			after: func(t *testing.T, order z.TokenOrderV2, funds *funds) {
				uassert.Equal(t, int64(50), voucherBalanceOf(string(order.BaseToken), address(order.Sender)))
			},
		},
		{
			name:        "unescrow wrong image rejected",
			channelId:   types.ChannelId(72),
			path:        u256.Zero(),
			funds:       newFunds(nil),
			crossSender: testAddress("wrong-image-sender"),
			setup: func(cur realm, t *testing.T, v *ucs03ZkgmV1) z.TokenOrderV2 {
				const destChan = types.ChannelId(72)
				sender := testAddress("wrong-image-sender")
				quoteToken := []byte("ugnot")
				imageCorrect := [32]byte{0x01}
				imageWrong := [32]byte{0x02}
				baseDenom := PredictWrappedTokenV2(u256.Zero(), uint32(destChan), quoteToken, imageCorrect)
				origin, err := z.UpdateChannelPath(u256.Zero(), uint32(destChan))
				uassert.NoError(t, err)
				testStore.SetTokenOrigin(0, cur, baseDenom, origin)
				testStore.SetMetadataImageOf(0, cur, baseDenom, imageWrong)
				uassert.NoError(t, v.mintVoucher(0, cur, baseDenom, imageWrong, "", "", 0, sender, u256.NewUint(100)))
				return z.TokenOrderV2{
					Sender:      []byte(sender),
					BaseToken:   []byte(baseDenom),
					BaseAmount:  u256.NewUint(50),
					QuoteToken:  quoteToken,
					QuoteAmount: u256.NewUint(50),
					Kind:        z.TOKEN_ORDER_KIND_UNESCROW,
				}
			},
			wantErr: "invalid token order unescrow",
		},
		{
			name:      "solve returns error",
			channelId: types.ChannelId(80),
			path:      u256.Zero(),
			funds:     newFunds(nil),
			setup: func(cur realm, t *testing.T, v *ucs03ZkgmV1) z.TokenOrderV2 {
				return z.TokenOrderV2{
					Sender:      []byte(testAddress("solve-sender")),
					BaseToken:   []byte("ugnot"),
					BaseAmount:  u256.NewUint(1),
					QuoteToken:  []byte("ibc/solve"),
					QuoteAmount: u256.NewUint(1),
					Kind:        z.TOKEN_ORDER_KIND_SOLVE,
				}
			},
			wantErr: "not implemented",
		},
	}

	for _, tc := range cases {
		testing.SetRealm(testing.NewCodeRealm(tokenOrderTestRealmPath))
		testStore = newMockStore()
		v := newTestImpl()
		order := tc.setup(cur, t, v)
		var err error
		if tc.crossSender != "" {
			testing.SetRealm(testing.NewUserRealm(address(tc.crossSender)))
			err = v.verifyTokenOrderV2X(cross(cur), tc.funds, tc.channelId, tc.path, order)
		} else {
			err = v.verifyTokenOrderV2(0, cur, tc.funds, tc.channelId, tc.path, order)
		}
		if tc.wantErr == "" {
			uassert.NoError(t, err, tc.name)
		} else if tc.wantErr == "error" {
			uassert.Error(t, err, tc.name)
		} else {
			uassert.ErrorContains(t, err, tc.wantErr, tc.name)
		}
		if tc.after != nil {
			tc.after(t, order, tc.funds)
		}
	}
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
	image := MetadataImage(mustDecodeTokenMetadata(metaBytes))
	ibcDenom := PredictWrappedTokenV2(u256.NewUint(7), 5, []byte("ugnot"), image)

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

func TestExecuteTokenOrderV2Initialize(cur realm, t *testing.T) {
	cases := []struct {
		name           string
		path           *u256.Uint
		destChannel    types.ChannelId
		receiver       string
		relayer        string
		implementation []byte
		initializer    []byte
		baseAmount     *u256.Uint
		quoteAmount    *u256.Uint
		wantErr        string
		wantBalance    int64
		wantName       string
		wantSymbol     string
		wantDecimals   int
		checkFullMeta  bool
		checkNoState   bool
	}{
		{
			name:           "mints voucher and success ack",
			path:           u256.NewUint(7),
			destChannel:    types.ChannelId(5),
			receiver:       testAddress("v1-receiver"),
			relayer:        testAddress("v1-relayer"),
			implementation: []byte("grc20"),
			initializer:    mustEncodeTokenInitializer(z.TokenInitializer{Name: "Gno Token", Symbol: "GNOT", Decimals: 6}),
			baseAmount:     u256.NewUint(100),
			quoteAmount:    u256.NewUint(95),
			wantBalance:    95,
			wantName:       "Gno Token",
			wantSymbol:     "GNOT",
			wantDecimals:   6,
			checkFullMeta:  true,
		},
		{
			name:           "malformed initializer uses defaults",
			path:           u256.NewUint(3),
			destChannel:    types.ChannelId(4),
			receiver:       testAddress("fallback-receiver"),
			relayer:        testAddress("fallback-relayer"),
			implementation: []byte("grc20"),
			initializer:    []byte("not-valid-abi"),
			baseAmount:     u256.NewUint(50),
			quoteAmount:    u256.NewUint(50),
			wantBalance:    50,
			wantDecimals:   0,
		},
		{
			name:           "empty initializer uses defaults",
			path:           u256.NewUint(5),
			destChannel:    types.ChannelId(6),
			receiver:       testAddress("empty-init-receiver"),
			relayer:        testAddress("empty-init-relayer"),
			implementation: []byte("grc20"),
			initializer:    []byte{},
			baseAmount:     u256.NewUint(20),
			quoteAmount:    u256.NewUint(20),
			wantBalance:    20,
			wantDecimals:   0,
		},
		{
			name:           "mint error does not set origin",
			path:           u256.NewUint(9),
			destChannel:    types.ChannelId(7),
			receiver:       "not-a-valid-address",
			relayer:        testAddress("invalid-rx-relayer"),
			implementation: []byte("grc20-invalid-rx"),
			initializer:    []byte("init-invalid-rx"),
			baseAmount:     u256.NewUint(100),
			quoteAmount:    u256.NewUint(95),
			wantErr:        "invalid address",
			checkNoState:   true,
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			testStore = newMockStore()
			v := newTestImpl()
			metaBytes := mustEncodeTokenMetadata(z.TokenMetadata{
				Implementation: tc.implementation,
				Initializer:    tc.initializer,
			})
			image := MetadataImage(mustDecodeTokenMetadata(metaBytes))
			ibcDenom := PredictWrappedTokenV2(tc.path, uint32(tc.destChannel), []byte("ugnot"), image)
			order := z.TokenOrderV2{
				Sender:      []byte("sender"),
				Receiver:    []byte(tc.receiver),
				BaseToken:   []byte("ugnot"),
				BaseAmount:  tc.baseAmount,
				QuoteToken:  []byte(ibcDenom),
				QuoteAmount: tc.quoteAmount,
				Kind:        z.TOKEN_ORDER_KIND_INITIALIZE,
				Metadata:    metaBytes,
			}
			packet := core.NewPacket(types.ChannelId(1), tc.destChannel, nil, 0)

			res, err := v.executeTokenOrderV2(0, cur, packet, address(tc.relayer), nil, [32]byte{}, tc.path, order, false)
			if tc.wantErr != "" {
				uassert.ErrorContains(t, err, tc.wantErr)
				if tc.checkNoState {
					_, ok := testStore.GetTokenOrigin(ibcDenom)
					uassert.False(t, ok, "mint error must not set token origin")
					_, ok = testStore.GetForeignToken(ibcDenom)
					uassert.False(t, ok, "mint error must not set foreign token")
					_, ok = testStore.GetMetadataImageOf(ibcDenom)
					uassert.False(t, ok, "mint error must not set metadata image")
				}
				return
			}

			uassert.NoError(t, err)
			uassert.True(t, res.Status == types.PacketStatusSuccess)
			assertProtocolAck(t, res.Acknowledgement)
			uassert.Equal(t, tc.wantBalance, voucherBalanceOf(ibcDenom, address(order.Receiver)))
			uassert.Equal(t, tc.wantDecimals, voucherDecimalsOf(ibcDenom))

			if tc.checkFullMeta {
				storedImage, ok := testStore.GetMetadataImageOf(ibcDenom)
				uassert.True(t, ok)
				uassert.True(t, image == storedImage)

				origin, ok := testStore.GetTokenOrigin(ibcDenom)
				uassert.True(t, ok)
				uassert.Equal(t, "21474836487", origin.ToString())

				foreignToken, ok := testStore.GetForeignToken(ibcDenom)
				uassert.True(t, ok)
				uassert.Equal(t, "ugnot", string(foreignToken))
				uassert.Equal(t, tc.wantName, voucherNameOf(ibcDenom))
				uassert.Equal(t, tc.wantSymbol, voucherSymbolOf(ibcDenom))
			}
		})
	}
}

func TestTokenOrderExecuteEscrowMintErrorDoesNotSetOrigin(cur realm, t *testing.T) {
	v := newTestImpl()

	path := u256.NewUint(11)
	destChan := uint32(8)
	quoteDenom := PredictWrappedToken(path, destChan, []byte("ugnot"))
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
	image := MetadataImage(mustDecodeTokenMetadata(metaBytes))
	path := u256.NewUint(30)
	const destChan = types.ChannelId(30)
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

func TestExecuteTokenOrderV2EscrowZeroAmounts(cur realm, t *testing.T) {
	cases := []struct {
		name            string
		destChannel     types.ChannelId
		relayer         string
		receiver        string
		baseAmount      *u256.Uint
		quoteAmount     *u256.Uint
		wantReceiver    int64
		wantRelayer     int64
		checkNoMetadata bool
	}{
		{
			name:            "zero fee skips relayer mint",
			destChannel:     types.ChannelId(60),
			relayer:         testAddress("zero-fee-relayer"),
			receiver:        testAddress("zero-fee-receiver"),
			baseAmount:      u256.NewUint(100),
			quoteAmount:     u256.NewUint(100),
			wantReceiver:    100,
			wantRelayer:     0,
			checkNoMetadata: true,
		},
		{
			name:         "zero quote skips receiver mint",
			destChannel:  types.ChannelId(61),
			relayer:      testAddress("zero-quote-relayer"),
			receiver:     testAddress("zero-quote-receiver"),
			baseAmount:   u256.NewUint(100),
			quoteAmount:  u256.NewUint(0),
			wantReceiver: 0,
			wantRelayer:  100,
		},
		{
			name:         "zero amount skips both mints",
			destChannel:  types.ChannelId(62),
			relayer:      testAddress("zero-amt-relayer"),
			receiver:     testAddress("zero-amt-receiver"),
			baseAmount:   u256.NewUint(0),
			quoteAmount:  u256.NewUint(0),
			wantReceiver: 0,
			wantRelayer:  0,
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			testStore = newMockStore()
			v := newTestImpl()
			path := u256.Zero()
			quoteDenom := PredictWrappedToken(path, uint32(tc.destChannel), []byte("ugnot"))
			order := z.TokenOrderV2{
				Sender:      []byte("sender"),
				Receiver:    []byte(tc.receiver),
				BaseToken:   []byte("ugnot"),
				BaseAmount:  tc.baseAmount,
				QuoteToken:  []byte(quoteDenom),
				QuoteAmount: tc.quoteAmount,
				Kind:        z.TOKEN_ORDER_KIND_ESCROW,
			}
			packet := core.NewPacket(types.ChannelId(1), tc.destChannel, nil, 0)

			res, err := v.executeTokenOrderV2(0, cur, packet, address(tc.relayer), nil, [32]byte{}, path, order, false)

			uassert.NoError(t, err)
			uassert.True(t, res.Status == types.PacketStatusSuccess)
			uassert.Equal(t, tc.wantReceiver, voucherBalanceOf(quoteDenom, address(tc.receiver)))
			uassert.Equal(t, tc.wantRelayer, voucherBalanceOf(quoteDenom, address(tc.relayer)))
			if tc.checkNoMetadata {
				_, ok := testStore.GetTokenOrigin(quoteDenom)
				uassert.False(t, ok, "escrow protocol fill must not set token origin")
				_, ok = testStore.GetForeignToken(quoteDenom)
				uassert.False(t, ok, "escrow protocol fill must not set foreign token")
				_, ok = testStore.GetMetadataImageOf(quoteDenom)
				uassert.False(t, ok, "escrow protocol fill must not set metadata image")
			}
		})
	}
}

func TestExecuteTokenOrderV2Intent(cur realm, t *testing.T) {
	cases := []struct {
		name                string
		maker               string
		receiver            string
		quoteToken          string
		kind                uint8
		quoteAmount         *u256.Uint
		seedMakerBalance    uint64
		wantOnlyMaker       bool
		wantMakerBalance    int64
		wantReceiverBalance int64
		checkNoOrigin       bool
		checkNoBalance      bool
	}{
		{
			name:                "voucher market maker fill transfers maker funds",
			maker:               testAddress("v1-intent-maker"),
			receiver:            testAddress("v1-intent-receiver"),
			quoteToken:          "ibc/v1-intent-quote",
			kind:                z.TOKEN_ORDER_KIND_ESCROW,
			quoteAmount:         u256.NewUint(12),
			seedMakerBalance:    30,
			wantMakerBalance:    18,
			wantReceiverBalance: 12,
			checkNoOrigin:       true,
			checkNoBalance:      true,
		},
		{
			name:          "unknown quote returns only maker",
			maker:         testAddress("v1-intent-maker"),
			receiver:      testAddress("int-unknown-rx"),
			quoteToken:    "ugnot",
			kind:          z.TOKEN_ORDER_KIND_UNESCROW,
			quoteAmount:   u256.NewUint(10),
			wantOnlyMaker: true,
		},
		{
			name:                "insufficient maker balance returns only maker",
			maker:               testAddress("v1-intent-poor-maker"),
			receiver:            testAddress("int-poor-rx"),
			quoteToken:          "ibc/v1-intent-poor",
			kind:                z.TOKEN_ORDER_KIND_ESCROW,
			quoteAmount:         u256.NewUint(9),
			seedMakerBalance:    3,
			wantOnlyMaker:       true,
			wantMakerBalance:    3,
			wantReceiverBalance: 0,
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			testStore = newMockStore()
			v := newTestImpl()
			if tc.seedMakerBalance > 0 {
				uassert.NoError(t, v.mintVoucher(0, cur, tc.quoteToken, [32]byte{}, "", "", 0, tc.maker, u256.NewUint(tc.seedMakerBalance)))
			}
			order := z.TokenOrderV2{
				Sender:      []byte("sender"),
				Receiver:    []byte(tc.receiver),
				BaseToken:   []byte("ugnot"),
				BaseAmount:  u256.NewUint(100),
				QuoteToken:  []byte(tc.quoteToken),
				QuoteAmount: tc.quoteAmount,
				Kind:        tc.kind,
			}
			packet := core.NewPacket(types.ChannelId(1), types.ChannelId(5), nil, 0)

			res, err := v.executeTokenOrderV2(0, cur, packet, address(tc.maker), nil, [32]byte{}, u256.Zero(), order, true)

			uassert.NoError(t, err)
			uassert.True(t, res.Status == types.PacketStatusSuccess)
			if tc.wantOnlyMaker {
				uassert.True(t, bytes.Equal(z.ACK_ERR_ONLY_MAKER, res.Acknowledgement))
			} else {
				assertMarketMakerAck(t, res.Acknowledgement, tc.maker)
			}
			uassert.Equal(t, tc.wantMakerBalance, voucherBalanceOf(tc.quoteToken, address(tc.maker)))
			uassert.Equal(t, tc.wantReceiverBalance, voucherBalanceOf(tc.quoteToken, address(tc.receiver)))
			if tc.checkNoOrigin {
				_, ok := testStore.GetTokenOrigin(tc.quoteToken)
				uassert.False(t, ok, "market-maker fill must not set token origin")
			}
			if tc.checkNoBalance {
				balance, hasBalance := testStore.GetChannelBalanceV2(ChannelBalanceKeyV2(types.ChannelId(5), u256.Zero(), order.BaseToken, order.QuoteToken))
				uassert.True(t, !hasBalance || balance.IsZero())
			}
		})
	}
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
