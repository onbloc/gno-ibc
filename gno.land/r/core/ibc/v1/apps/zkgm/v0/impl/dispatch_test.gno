package impl

import (
	"math"
	"testing"

	u256 "gno.land/p/gnoswap/uint256"
	"gno.land/p/nt/uassert/v0"
	z "gno.land/p/onbloc/ibc/zkgm"
	zkgm "gno.land/r/onbloc/unionibc/v1/apps/zkgm"
	core "gno.land/r/onbloc/unionibc/v1/core"
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
	packet := core.NewPacket(cross(cur), core.ChannelId(1), core.ChannelId(2), data, 0, 0)

	res := (&ZkgmV1{}).Recv(cur, packet, address(testAddress("relayer")), nil)

	uassert.True(t, res.Status == core.PacketStatusFailure)
	uassert.Equal(t, string(universalErrorAck()), string(res.Ack))
}

func TestRecvMalformedPacketReturnsFailure(cur realm, t *testing.T) {
	packet := core.NewPacket(cross(cur), core.ChannelId(1), core.ChannelId(2), []byte{0x01}, 0, 0)

	res := (&ZkgmV1{}).Recv(cur, packet, address(testAddress("relayer")), nil)

	uassert.True(t, res.Status == core.PacketStatusFailure)
	uassert.True(t, len(res.Ack) > 0)
}

func TestAckUnsupportedOpcodeAborts(cur realm, t *testing.T) {
	data := mustZkgmPacketBytes(z.Instruction{
		Version: z.INSTR_VERSION_0,
		Opcode:  0xFF,
	})
	packet := core.NewPacket(cross(cur), core.ChannelId(1), core.ChannelId(2), data, 0, 0)

	uassert.AbortsContains(t, cur, "unsupported opcode", func(cur realm) {
		(&ZkgmV1{}).Ack(cur, packet, nil, address(testAddress("relayer")))
	})
}

// TestRecvTokenOrderInitializeMissingMetadataReturnsFailureAck verifies that
// an error occurring before any state mutation produces a universalErrorAck
// rather than aborting the transaction.
func TestRecvTokenOrderInitializeMissingMetadataReturnsFailureAck(cur realm, t *testing.T) {
	resetTokenOrderTest(cur)

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
	packet := core.NewPacket(cross(cur), core.ChannelId(1), core.ChannelId(1), data, 0, 0)

	res := (&ZkgmV1{}).Recv(cur, packet, address(testAddress("relayer")), nil)

	uassert.True(t, res.Status == core.PacketStatusFailure)
	uassert.Equal(t, string(universalErrorAck()), string(res.Ack))
}

// TestRecvTokenOrderEscrowFeeVoucherMintFailureAborts verifies that an error
// occurring after a state mutation (receiver voucher already minted) propagates
// as execFatal and aborts the transaction rather than returning a failure ack.
func TestRecvTokenOrderEscrowFeeVoucherMintFailureAborts(cur realm, t *testing.T) {
	resetTokenOrderTest(cur)

	const destChan = core.ChannelId(5)
	baseToken := []byte("uatom-fee-fatal")
	path := u256.Zero()
	// Pre-minting sets metadataImage=[32]byte{} for ibcDenom, so ESCROW will
	// use PredictWrappedTokenV2 for validation — use the same function here.
	ibcDenom := PredictWrappedTokenV2(path, uint32(destChan), baseToken, [32]byte{})

	// Saturate supply to MaxInt64-1. After receiver mint (+1) total = MaxInt64.
	// Fee mint (+1) then overflows int64 → GRC20 returns error → execFatal.
	fillAmt := u256.NewUint(uint64(math.MaxInt64) - 1)
	uassert.NoError(t, zkgm.MintVoucher(cross(cur), ibcDenom, string(baseToken), [32]byte{}, "", "", 0, testAddress("sat"), fillAmt))

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
	packet := core.NewPacket(cross(cur), core.ChannelId(1), destChan, data, 0, 0)

	uassert.AbortsContains(t, cur, "mint overflow", func(cur realm) {
		(&ZkgmV1{}).Recv(cur, packet, address(testAddress("fee-fatal-relayer")), nil)
	})

	// SetTokenOrigin is called after the fee mint — the abort must prevent it.
	// (State rollback of the receiver mint is guaranteed by the VM on a real tx
	// abort, but is not replicated in the test harness's AbortsContains.)
	_, hasOrigin := zkgm.GetTokenOrigin(ibcDenom)
	uassert.False(t, hasOrigin)
}

func TestRecvTokenOrderSolveReturnsFailureAck(cur realm, t *testing.T) {
	resetTokenOrderTest(cur)

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
	packet := core.NewPacket(cross(cur), core.ChannelId(1), core.ChannelId(1), data, 0, 0)

	res := (&ZkgmV1{}).Recv(cur, packet, address("g1relayer"), nil)

	uassert.True(t, res.Status == core.PacketStatusFailure)
	uassert.Equal(t, string(universalErrorAck()), string(res.Ack))
}

func TestDecodeOrderInstructionRejectsV1(t *testing.T) {
	_, err := decodeOrderInstruction(z.Instruction{
		Version: z.INSTR_VERSION_1,
		Opcode:  z.OP_TOKEN_ORDER,
		Operand: []byte("anything"),
	})
	uassert.ErrorContains(t, err, "unsupported token order version")
}

func mustZkgmPacketBytes(instr z.Instruction) []byte {
	out, err := z.EncodeZkgmPacket(z.ZkgmPacket{
		Salt:        [32]byte{},
		Path:        u256.Zero(),
		Instruction: instr,
	})
	if err != nil {
		panic(err)
	}
	return out
}

func mustCallBytes(call z.Call) []byte {
	out, err := z.EncodeCall(call)
	if err != nil {
		panic(err)
	}
	return out
}

func mustForwardBytes(forward z.Forward) []byte {
	out, err := z.EncodeForward(forward)
	if err != nil {
		panic(err)
	}
	return out
}
