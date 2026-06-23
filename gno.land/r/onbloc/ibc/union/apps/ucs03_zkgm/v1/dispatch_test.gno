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

// Each decode* helper accepts exactly one instruction version and rejects all
// others with a version-specific error, before any operand decoding.
func TestDecodeInstructionVersionGate(t *testing.T) {
	cases := []struct {
		name    string
		version uint8
		decode  func(z.Instruction) error
		wantErr string
	}{
		{"order rejects v0", z.INSTR_VERSION_0, func(i z.Instruction) error { _, e := decodeOrderInstruction(i); return e }, "unsupported token order version"},
		{"order rejects v1", z.INSTR_VERSION_1, func(i z.Instruction) error { _, e := decodeOrderInstruction(i); return e }, "unsupported token order version"},
		{"call rejects v1", z.INSTR_VERSION_1, func(i z.Instruction) error { _, e := decodeCallInstruction(i); return e }, "unsupported call version"},
		{"call rejects v2", z.INSTR_VERSION_2, func(i z.Instruction) error { _, e := decodeCallInstruction(i); return e }, "unsupported call version"},
		{"batch rejects v1", z.INSTR_VERSION_1, func(i z.Instruction) error { _, e := decodeBatchInstruction(i); return e }, "unsupported batch version"},
		{"batch rejects v2", z.INSTR_VERSION_2, func(i z.Instruction) error { _, e := decodeBatchInstruction(i); return e }, "unsupported batch version"},
		{"forward rejects v1", z.INSTR_VERSION_1, func(i z.Instruction) error { _, e := decodeForwardInstruction(i); return e }, "unsupported forward version"},
		{"forward rejects v2", z.INSTR_VERSION_2, func(i z.Instruction) error { _, e := decodeForwardInstruction(i); return e }, "unsupported forward version"},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			err := tc.decode(z.Instruction{Version: tc.version, Operand: []byte("anything")})
			uassert.ErrorContains(t, err, tc.wantErr)
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

// extractPanicMessage renders string, error, and arbitrary recovered values.
func TestExtractPanicMessage(t *testing.T) {
	uassert.Equal(t, "boom", extractPanicMessage("boom"))
	uassert.Equal(t, "wrapped", extractPanicMessage(errors.New("wrapped")))
	uassert.Equal(t, "42", extractPanicMessage(42))
}
