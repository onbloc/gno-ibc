package impl

import (
	"errors"
	"math"
	"testing"

	types "gno.land/p/onbloc/ibc/union/types"

	u256 "gno.land/p/gnoswap/uint256"
	"gno.land/p/nt/uassert/v0"
	z "gno.land/p/onbloc/ibc/union/zkgm"
	core "gno.land/r/onbloc/ibc/union/core"
)

func TestMustEncodeUniversalErrorAck(t *testing.T) {
	ack, err := z.DecodeAck(mustEncodeUniversalErrorAck())

	uassert.NoError(t, err)
	uassert.True(t, ack.Tag.Eq(tagAckFailure()))
	uassert.Equal(t, "", string(ack.InnerAck))
}

func TestFailureResult(t *testing.T) {
	res := failureResult([]byte("ack"))

	uassert.True(t, res.Status == types.PacketStatusFailure)
	uassert.Equal(t, "ack", string(res.Acknowledgement))
}

func TestUniversalErrorAck(t *testing.T) {
	got := universalErrorAck()
	want := mustEncodeUniversalErrorAck()

	uassert.Equal(t, string(want), string(got))
}

func TestDispatchExecutePacket(cur realm, t *testing.T) {
	v := newTestImpl()
	packet := core.NewPacket(types.ChannelId(1), types.ChannelId(2), nil, 0)

	cases := []struct {
		name    string
		instr   z.Instruction
		wantErr string
	}{
		{
			name:    "unsupported opcode",
			instr:   z.Instruction{Version: z.INSTR_VERSION_0, Opcode: 0xFF},
			wantErr: "unsupported opcode",
		},
		{
			name:    "malformed call",
			instr:   z.Instruction{Version: z.INSTR_VERSION_0, Opcode: z.OP_CALL, Operand: []byte{0x01}},
			wantErr: "invalid",
		},
		{
			name:    "malformed batch",
			instr:   z.Instruction{Version: z.INSTR_VERSION_0, Opcode: z.OP_BATCH, Operand: []byte{0x01}},
			wantErr: "invalid",
		},
		{
			name:    "malformed forward",
			instr:   z.Instruction{Version: z.INSTR_VERSION_0, Opcode: z.OP_FORWARD, Operand: []byte{0x01}},
			wantErr: "invalid",
		},
		{
			name:    "wrong token order version",
			instr:   z.Instruction{Version: z.INSTR_VERSION_0, Opcode: z.OP_TOKEN_ORDER, Operand: []byte{0x01}},
			wantErr: "unsupported token order version",
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			res, err := v.dispatchExecutePacket(0, cur, packet, address(testAddress("dispatch-relayer")), nil, [32]byte{}, u256.Zero(), tc.instr, false)

			uassert.ErrorContains(t, err, tc.wantErr)
			uassert.True(t, res.Status == types.PacketStatusUnknown)
			uassert.Equal(t, "", string(res.Acknowledgement))
		})
	}
}

func TestAcknowledgeInternal(cur realm, t *testing.T) {
	v := newTestImpl()
	packet := core.NewPacket(types.ChannelId(1), types.ChannelId(2), nil, 0)

	cases := []struct {
		name    string
		instr   z.Instruction
		success bool
		ack     []byte
		wantErr string
	}{
		{
			name:    "unsupported opcode",
			instr:   z.Instruction{Version: z.INSTR_VERSION_0, Opcode: 0xFF},
			wantErr: "unsupported opcode",
		},
		{
			name:    "malformed call",
			instr:   z.Instruction{Version: z.INSTR_VERSION_0, Opcode: z.OP_CALL, Operand: []byte{0x01}},
			wantErr: "invalid",
		},
		{
			name:    "call eureka",
			instr:   batchMustCallInstruction(z.Call{Eureka: true}),
			wantErr: "eureka mode not supported",
		},
		{
			name:    "successful call",
			instr:   batchMustCallInstruction(z.Call{}),
			wantErr: "",
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			err := v.acknowledgeInternal(0, cur, packet, address(testAddress("ack-relayer")), [32]byte{}, u256.Zero(), tc.instr, tc.success, tc.ack)
			if tc.wantErr != "" {
				uassert.ErrorContains(t, err, tc.wantErr)
				return
			}
			uassert.NoError(t, err)
		})
	}
}

func TestTimeoutInternal(cur realm, t *testing.T) {
	v := newTestImpl()
	packet := core.NewPacket(types.ChannelId(1), types.ChannelId(2), nil, 0)

	cases := []struct {
		name    string
		instr   z.Instruction
		wantErr string
	}{
		{
			name:    "unsupported opcode",
			instr:   z.Instruction{Version: z.INSTR_VERSION_0, Opcode: 0xFF},
			wantErr: "unsupported opcode",
		},
		{
			name:    "malformed call",
			instr:   z.Instruction{Version: z.INSTR_VERSION_0, Opcode: z.OP_CALL, Operand: []byte{0x01}},
			wantErr: "invalid",
		},
		{
			name:    "call eureka",
			instr:   batchMustCallInstruction(z.Call{Eureka: true}),
			wantErr: "eureka mode not supported",
		},
		{
			name:    "successful call",
			instr:   batchMustCallInstruction(z.Call{}),
			wantErr: "",
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			err := v.timeoutInternal(0, cur, packet, [32]byte{}, u256.Zero(), tc.instr)
			if tc.wantErr != "" {
				uassert.ErrorContains(t, err, tc.wantErr)
				return
			}
			uassert.NoError(t, err)
		})
	}
}

func TestRecvForwardExecuteErrorReturnsFailure(cur realm, t *testing.T) {
	data := mustZkgmPacketBytes(z.Instruction{
		Version: z.INSTR_VERSION_0,
		Opcode:  z.OP_FORWARD,
		Operand: mustForwardBytes(z.Forward{
			Path:             u256.Zero(),
			TimeoutTimestamp: 1,
			Instruction: z.Instruction{
				Version: z.INSTR_VERSION_0,
				Opcode:  z.OP_CALL,
				Operand: mustCallBytes(z.Call{}),
			},
		}),
	})
	packet := core.NewPacket(types.ChannelId(1), types.ChannelId(2), data, 0)

	res := newTestImpl().OnRecvPacket(0, cur, packet, address(testAddress("relayer")), nil)

	uassert.True(t, res.Status == types.PacketStatusFailure)
	uassert.Equal(t, string(universalErrorAck()), string(res.Acknowledgement))
}

func TestRecvMalformedPacketReturnsFailure(cur realm, t *testing.T) {
	packet := core.NewPacket(types.ChannelId(1), types.ChannelId(2), []byte{0x01}, 0)

	res := newTestImpl().OnRecvPacket(0, cur, packet, address(testAddress("relayer")), nil)

	uassert.True(t, res.Status == types.PacketStatusFailure)
	uassert.True(t, len(res.Acknowledgement) > 0)
}

func TestAckUnsupportedOpcodeAborts(cur realm, t *testing.T) {
	data := mustZkgmPacketBytes(z.Instruction{
		Version: z.INSTR_VERSION_0,
		Opcode:  0xFF,
	})
	packet := core.NewPacket(types.ChannelId(1), types.ChannelId(2), data, 0)

	// Provide a decodable ack so dispatch reaches the opcode switch; the unknown
	// opcode (0xFF) is what must abort, not the ack decoding.
	uassert.AbortsContains(t, cur, "unsupported opcode", func(cur realm) {
		newTestImpl().OnAcknowledgementPacket(0, cur, packet, mustSuccessAck(), address(testAddress("relayer")))
	})
}

func TestPacketResolutionRejectsMalformedInputs(cur realm, t *testing.T) {
	validCallPacket := core.NewPacket(types.ChannelId(1), types.ChannelId(2), mustZkgmPacketBytes(batchMustCallInstruction(batchCall("sender", ""))), 0)
	malformedPacket := core.NewPacket(types.ChannelId(1), types.ChannelId(2), []byte{0x01}, 0)

	cases := []struct {
		name    string
		run     func(cur realm)
		wantErr string
	}{
		{
			"ack malformed packet",
			func(cur realm) {
				newTestImpl().OnAcknowledgementPacket(0, cur, malformedPacket, mustSuccessAck(), address(testAddress("relayer")))
			},
			"invalid",
		},
		{
			"ack malformed outer ack",
			func(cur realm) {
				newTestImpl().OnAcknowledgementPacket(0, cur, validCallPacket, []byte{0x01}, address(testAddress("relayer")))
			},
			"invalid",
		},
		{
			"timeout malformed packet",
			func(cur realm) {
				newTestImpl().OnTimeoutPacket(0, cur, malformedPacket, address(testAddress("relayer")))
			},
			"invalid",
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			uassert.AbortsContains(t, cur, tc.wantErr, func(cur realm) {
				tc.run(cur)
			})
		})
	}
}

func TestPacketAcknowledgementRejectsUnknownTokenOrderFillType(cur realm, t *testing.T) {
	order := z.TokenOrderV2{
		Kind:        z.TOKEN_ORDER_KIND_ESCROW,
		Sender:      []byte(testAddress("unknown-fill-sender")),
		BaseToken:   []byte("ibc/unknown-fill"),
		BaseAmount:  u256.NewUint(10),
		QuoteToken:  []byte("quote"),
		QuoteAmount: u256.NewUint(10),
	}
	packet := core.NewPacket(types.ChannelId(1), types.ChannelId(2), mustZkgmPacketBytes(batchMustOrderInstruction(order)), 0)
	ack := mustTokenOrderOuterAck(z.TokenOrderAck{
		FillType:    u256.NewUint(99),
		MarketMaker: []byte(testAddress("maker")),
	})

	uassert.AbortsContains(t, cur, "unknown fill type", func(cur realm) {
		newTestImpl().OnAcknowledgementPacket(0, cur, packet, ack, address(testAddress("relayer")))
	})
}

// TestRecvTokenOrderInitializeMissingMetadataReturnsFailureAck verifies that an
// error occurring before any state mutation produces a universalErrorAck rather
// than aborting the transaction.
func TestRecvTokenOrderInitializeMissingMetadataReturnsFailureAck(cur realm, t *testing.T) {
	order := z.TokenOrderV2{
		Kind:        z.TOKEN_ORDER_KIND_INITIALIZE,
		Sender:      []byte(testAddress("init-err-sender")),
		Receiver:    []byte(testAddress("init-err-receiver")),
		BaseToken:   []byte("uatom"),
		BaseAmount:  u256.NewUint(10),
		QuoteToken:  []byte("ibc/test"),
		QuoteAmount: u256.NewUint(10),
		// Metadata absent → error returned before any state mutation
	}
	data := mustZkgmPacketBytes(batchMustOrderInstruction(order))
	packet := core.NewPacket(types.ChannelId(1), types.ChannelId(1), data, 0)

	res := newTestImpl().OnRecvPacket(0, cur, packet, address(testAddress("relayer")), nil)

	uassert.True(t, res.Status == types.PacketStatusFailure)
	uassert.Equal(t, string(universalErrorAck()), string(res.Acknowledgement))
}

// TestRecvTokenOrderEscrowFeeVoucherMintFailureAborts verifies that an error
// occurring after a state mutation (receiver voucher already minted) propagates
// as execFatal and aborts the transaction rather than returning a failure ack.
func TestRecvTokenOrderEscrowFeeVoucherMintFailureAborts(cur realm, t *testing.T) {
	v := newTestImpl()

	const destChan = types.ChannelId(5)
	baseToken := []byte("uatom-fee-fatal")
	path := u256.Zero()
	// Store a non-zero metadataImage so ESCROW takes the V2 prediction path
	// (union uses V1 only when the image is zero) and the quote denom matches.
	image := [32]byte{0x01}
	ibcDenom := z.PredictWrappedTokenV2(path, uint32(destChan), baseToken, image)
	testStore.SetMetadataImageOf(0, cur, ibcDenom, image)

	// Saturate supply to MaxInt64-1. After receiver mint (+1) total = MaxInt64.
	// Fee mint (+1) then overflows int64 → GRC20 returns error → execFatal.
	fillAmt := u256.NewUint(uint64(math.MaxInt64) - 1)
	uassert.NoError(t, v.mintVoucher(0, cur, ibcDenom, image, "", "", 0, testAddress("sat"), fillAmt))

	order := z.TokenOrderV2{
		Kind:        z.TOKEN_ORDER_KIND_ESCROW,
		Sender:      []byte(testAddress("fee-fatal-sender")),
		Receiver:    []byte(testAddress("fee-fatal-receiver")),
		BaseToken:   baseToken,
		BaseAmount:  u256.NewUint(2),
		QuoteToken:  []byte(ibcDenom),
		QuoteAmount: u256.NewUint(1),
	}
	data := mustZkgmPacketBytes(batchMustOrderInstruction(order))
	packet := core.NewPacket(types.ChannelId(1), destChan, data, 0)

	uassert.AbortsContains(t, cur, "mint overflow", func(cur realm) {
		newTestImpl().OnRecvPacket(0, cur, packet, address(testAddress("fee-fatal-relayer")), nil)
	})

	// SetTokenOrigin is called after the fee mint — the abort must prevent it.
	// (State rollback of the receiver mint is guaranteed by the VM on a real tx
	// abort, but is not replicated in the test harness's AbortsContains.)
	_, hasOrigin := testStore.GetTokenOrigin(ibcDenom)
	uassert.False(t, hasOrigin)
}

func TestRecvTokenOrderSolveFallsBackToMarketMaker(cur realm, t *testing.T) {
	// A solve order is maker-only (union routes it to market_maker_fill_v2). With
	// no voucher for the quote denom, the fill is maker-only.
	order := z.TokenOrderV2{
		Kind:        z.TOKEN_ORDER_KIND_SOLVE,
		Sender:      []byte(testAddress("solve-recv-sndr")),
		Receiver:    []byte(testAddress("solve-recv-rx")),
		BaseToken:   []byte("uatom"),
		BaseAmount:  u256.NewUint(10),
		QuoteToken:  []byte("ibc/solve"),
		QuoteAmount: u256.NewUint(10),
	}
	data := mustZkgmPacketBytes(batchMustOrderInstruction(order))
	packet := core.NewPacket(types.ChannelId(1), types.ChannelId(1), data, 0)

	res := newTestImpl().OnRecvPacket(0, cur, packet, address("g1relayer"), nil)

	uassert.True(t, res.Status == types.PacketStatusSuccess)
	uassert.Equal(t, string(z.ACK_ERR_ONLY_MAKER), string(res.Acknowledgement))
}

func TestDecodeOrderInstruction(t *testing.T) {
	validOrder := z.TokenOrderV2{
		Kind:        z.TOKEN_ORDER_KIND_ESCROW,
		Sender:      []byte("decode-order-sender"),
		BaseToken:   []byte("ugnot"),
		BaseAmount:  u256.NewUint(10),
		QuoteToken:  []byte("quote"),
		QuoteAmount: u256.NewUint(10),
	}
	validInstruction := batchMustOrderInstruction(validOrder)

	cases := []struct {
		name    string
		input   z.Instruction
		wantErr string
	}{
		{"accepts v2 token order", validInstruction, ""},
		{"rejects v0", z.Instruction{Version: z.INSTR_VERSION_0, Operand: []byte("anything")}, "unsupported token order version"},
		{"rejects v1", z.Instruction{Version: z.INSTR_VERSION_1, Operand: []byte("anything")}, "unsupported token order version"},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got, err := decodeOrderInstruction(tc.input)
			if tc.wantErr != "" {
				uassert.ErrorContains(t, err, tc.wantErr)
				return
			}
			uassert.NoError(t, err)
			uassert.Equal(t, string(validOrder.Sender), string(got.Sender))
			uassert.Equal(t, validOrder.Kind, got.Kind)
		})
	}
}

func TestDecodeCallInstruction(t *testing.T) {
	validCall := z.Call{
		Sender:           []byte("decode-call-sender"),
		ContractAddress:  []byte("decode-call-receiver"),
		ContractCalldata: []byte("payload"),
	}

	cases := []struct {
		name    string
		input   z.Instruction
		wantErr string
	}{
		{"accepts v0 call", batchMustCallInstruction(validCall), ""},
		{"rejects v1", z.Instruction{Version: z.INSTR_VERSION_1, Operand: []byte("anything")}, "unsupported call version"},
		{"rejects v2", z.Instruction{Version: z.INSTR_VERSION_2, Operand: []byte("anything")}, "unsupported call version"},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got, err := decodeCallInstruction(tc.input)
			if tc.wantErr != "" {
				uassert.ErrorContains(t, err, tc.wantErr)
				return
			}
			uassert.NoError(t, err)
			uassert.Equal(t, string(validCall.Sender), string(got.Sender))
			uassert.Equal(t, string(validCall.ContractAddress), string(got.ContractAddress))
			uassert.Equal(t, string(validCall.ContractCalldata), string(got.ContractCalldata))
		})
	}
}

func TestDecodeBatchInstruction(t *testing.T) {
	validBatch := z.Batch{Instructions: []z.Instruction{
		batchMustCallInstruction(z.Call{Sender: []byte("decode-batch-sender")}),
	}}

	cases := []struct {
		name    string
		input   z.Instruction
		wantErr string
	}{
		{"accepts v0 batch", batchMustBatchInstruction(validBatch), ""},
		{"rejects v1", z.Instruction{Version: z.INSTR_VERSION_1, Operand: []byte("anything")}, "unsupported batch version"},
		{"rejects v2", z.Instruction{Version: z.INSTR_VERSION_2, Operand: []byte("anything")}, "unsupported batch version"},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got, err := decodeBatchInstruction(tc.input)
			if tc.wantErr != "" {
				uassert.ErrorContains(t, err, tc.wantErr)
				return
			}
			uassert.NoError(t, err)
			uassert.Equal(t, len(validBatch.Instructions), len(got.Instructions))
			uassert.Equal(t, validBatch.Instructions[0].Opcode, got.Instructions[0].Opcode)
		})
	}
}

func TestDecodeForwardInstruction(t *testing.T) {
	validForward := z.Forward{
		Path:             u256.NewUint(1),
		TimeoutTimestamp: 123,
		Instruction:      batchMustCallInstruction(z.Call{Sender: []byte("decode-forward-sender")}),
	}

	cases := []struct {
		name    string
		input   z.Instruction
		wantErr string
	}{
		{"accepts v0 forward", z.Instruction{Version: z.INSTR_VERSION_0, Opcode: z.OP_FORWARD, Operand: mustForwardBytes(validForward)}, ""},
		{"rejects v1", z.Instruction{Version: z.INSTR_VERSION_1, Operand: []byte("anything")}, "unsupported forward version"},
		{"rejects v2", z.Instruction{Version: z.INSTR_VERSION_2, Operand: []byte("anything")}, "unsupported forward version"},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got, err := decodeForwardInstruction(tc.input)
			if tc.wantErr != "" {
				uassert.ErrorContains(t, err, tc.wantErr)
				return
			}
			uassert.NoError(t, err)
			uassert.Equal(t, validForward.TimeoutTimestamp, got.TimeoutTimestamp)
			uassert.Equal(t, validForward.Instruction.Opcode, got.Instruction.Opcode)
		})
	}
}

// tokenOrderDestinationChannel rejects the zero-channel sentinel and passes any
// non-zero channel through unchanged.
func TestTokenOrderDestinationChannel(t *testing.T) {
	_, err := tokenOrderDestinationChannel(types.ChannelId(0))
	uassert.ErrorContains(t, err, "invalid token order destination channel")

	raw, err := tokenOrderDestinationChannel(types.ChannelId(7))
	uassert.NoError(t, err)
	uassert.Equal(t, uint32(7), raw)
}

// isOnlyMakerAck matches only the exact only-maker sentinel.
func TestIsOnlyMakerAck(t *testing.T) {
	uassert.True(t, isOnlyMakerAck(z.ACK_ERR_ONLY_MAKER))
	uassert.False(t, isOnlyMakerAck([]byte("other")))
	uassert.False(t, isOnlyMakerAck(nil))
}

func TestExtractPanicMessage(t *testing.T) {
	cases := []struct {
		name string
		in   any
		want string
	}{
		{"string panic", "boom", "boom"},
		{"error panic", errors.New("bad input"), "bad input"},
		{"numeric panic", 17, "17"},
		{"nil panic", nil, "<nil>"},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			uassert.Equal(t, tc.want, extractPanicMessage(tc.in))
		})
	}
}

func mustTokenOrderOuterAck(orderAck z.TokenOrderAck) []byte {
	inner, err := z.EncodeTokenOrderAck(orderAck)
	if err != nil {
		panic(err)
	}
	ack, err := z.EncodeAck(z.Ack{Tag: tagAckSuccess(), InnerAck: inner})
	if err != nil {
		panic(err)
	}
	return ack
}
