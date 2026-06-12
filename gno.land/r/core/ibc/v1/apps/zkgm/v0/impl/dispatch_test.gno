package impl

import (
	"math"
	"testing"

	u256 "gno.land/p/gnoswap/uint256"
	"gno.land/p/nt/uassert/v0"
	z "gno.land/p/onbloc/unionibc/zkgm"
	zkgm "gno.land/r/onbloc/unionibc/v1/apps/zkgm"
	"gno.land/r/onbloc/unionibc/v1/apps/zkgm/testing/mock"
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

func TestRecvCallReceiverPanicReturnsFailureAck(cur realm, t *testing.T) {
	mock.Reset(cross(cur))
	mock.SetPanic(cross(cur), "boom")
	data := mustZkgmPacketBytes(batchMustCallInstruction(z.Call{
		Sender:          []byte("sender"),
		ContractAddress: []byte(mockReceiverPath),
	}))
	packet := core.NewPacket(cross(cur), core.ChannelId(7), core.ChannelId(8), data, 0, 0)

	res := (&ZkgmV1{}).Recv(cur, packet, address(testAddress("relayer")), nil)

	uassert.True(t, res.Status == core.PacketStatusFailure)
	ack, err := z.DecodeAck(res.Ack)
	uassert.NoError(t, err)
	uassert.True(t, ack.Tag.Eq(tagAckFailure()))
	uassert.Equal(t, "zkgm/v1: receiver panicked: boom", string(ack.InnerAck))
}

func TestDispatchAckTokenOrderOnlyMakerOrBadAckRefunds(cur realm, t *testing.T) {
	cases := []struct {
		name string
		key  string
		ack  []byte
	}{
		{"only-maker", "om", cloneBytes(z.ACK_ERR_ONLY_MAKER)},
		{"garbage", "bad", []byte{0x01, 0x02}},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			resetTokenOrderTest(cur)
			path := u256.NewUint(30)
			packet := core.NewPacket(cross(cur), core.ChannelId(7), core.ChannelId(8), nil, 0, 0)
			order := batchRefundOrder("t-"+tc.key, "ibc/t-"+tc.key, "quote", 11)
			increaseChannelBalanceV2(cross(cur), packet.SourceChannelId, path, order.BaseToken, order.QuoteToken, order.BaseAmount)
			instr := batchMustOrderInstruction(order)

			err := (&ZkgmV1{}).dispatchAck(cur, packet, path, [32]byte{0x30}, instr, tc.ack)

			uassert.NoError(t, err)
			assertNoChannelBalance(t, packet.SourceChannelId, path, order)
			uassert.Equal(t, int64(11), VoucherBalanceOf(string(order.BaseToken), address(string(order.Sender))))
		})
	}
}

func TestDispatchAckBatchOnlyMakerOrBadOuterAckRefundsTokenOrder(cur realm, t *testing.T) {
	cases := []struct {
		name string
		key  string
		ack  []byte
	}{
		{"only-maker", "om", cloneBytes(z.ACK_ERR_ONLY_MAKER)},
		{"garbage", "bad", []byte{0x01, 0x02}},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			resetTokenOrderTest(cur)
			path := u256.NewUint(31)
			packet := core.NewPacket(cross(cur), core.ChannelId(7), core.ChannelId(8), nil, 0, 0)
			order := batchRefundOrder("b-"+tc.key, "ibc/b-"+tc.key, "quote", 13)
			increaseChannelBalanceV2(cross(cur), packet.SourceChannelId, path, order.BaseToken, order.QuoteToken, order.BaseAmount)
			batch := z.Batch{Instructions: []z.Instruction{batchMustOrderInstruction(order)}}
			instr := batchMustBatchInstruction(batch)

			err := (&ZkgmV1{}).dispatchAck(cur, packet, path, [32]byte{0x31}, instr, tc.ack)

			uassert.NoError(t, err)
			assertNoChannelBalance(t, packet.SourceChannelId, path, order)
			uassert.Equal(t, int64(13), VoucherBalanceOf(string(order.BaseToken), address(string(order.Sender))))
		})
	}
}

func TestDispatchAckForwardOnlyMakerOrBadOuterAckRefundsTokenOrder(cur realm, t *testing.T) {
	cases := []struct {
		name string
		key  string
		ack  []byte
	}{
		{"only-maker", "om", cloneBytes(z.ACK_ERR_ONLY_MAKER)},
		{"garbage", "bad", []byte{0x03, 0x04}},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			resetTokenOrderTest(cur)
			path := forwardPath(1, 2)
			packet := core.NewPacket(cross(cur), core.ChannelId(9), core.ChannelId(10), nil, 0, 0)
			order := batchRefundOrder("f-"+tc.key, "ibc/f-"+tc.key, "quote", 17)
			increaseChannelBalanceV2(cross(cur), packet.SourceChannelId, path, order.BaseToken, order.QuoteToken, order.BaseAmount)
			forward := z.Forward{
				Path:        path,
				Instruction: batchMustOrderInstruction(order),
			}
			instr := z.Instruction{
				Version: z.INSTR_VERSION_0,
				Opcode:  z.OP_FORWARD,
				Operand: mustForwardBytes(forward),
			}

			err := (&ZkgmV1{}).dispatchAck(cur, packet, u256.Zero(), [32]byte{0x32}, instr, tc.ack)

			uassert.NoError(t, err)
			assertNoChannelBalance(t, packet.SourceChannelId, path, order)
			uassert.Equal(t, int64(17), VoucherBalanceOf(string(order.BaseToken), address(string(order.Sender))))
		})
	}
}

func TestDispatchAckBatchBadChildTokenOrderAckRefunds(cur realm, t *testing.T) {
	cases := []struct {
		name string
		key  string
		ack  []byte
	}{
		{"only-maker", "om", cloneBytes(z.ACK_ERR_ONLY_MAKER)},
		{"garbage", "bad", []byte{0x05, 0x06}},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			resetTokenOrderTest(cur)
			path := u256.NewUint(33)
			packet := core.NewPacket(cross(cur), core.ChannelId(7), core.ChannelId(8), nil, 0, 0)
			order := batchRefundOrder("bc-"+tc.key, "ibc/bc-"+tc.key, "quote", 19)
			increaseChannelBalanceV2(cross(cur), packet.SourceChannelId, path, order.BaseToken, order.QuoteToken, order.BaseAmount)
			instr := batchMustBatchInstruction(z.Batch{Instructions: []z.Instruction{batchMustOrderInstruction(order)}})
			outerAck := mustAckBytes(z.Ack{
				Tag:      tagAckSuccess(),
				InnerAck: mustBatchAckBytes([][]byte{tc.ack}),
			})

			err := (&ZkgmV1{}).dispatchAck(cur, packet, path, [32]byte{0x33}, instr, outerAck)

			uassert.NoError(t, err)
			assertNoChannelBalance(t, packet.SourceChannelId, path, order)
			uassert.Equal(t, int64(19), VoucherBalanceOf(string(order.BaseToken), address(string(order.Sender))))
		})
	}
}

func TestDispatchAckForwardBadInnerTokenOrderAckRefunds(cur realm, t *testing.T) {
	cases := []struct {
		name string
		key  string
		ack  []byte
	}{
		{"only-maker", "om", cloneBytes(z.ACK_ERR_ONLY_MAKER)},
		{"garbage", "bad", []byte{0x07, 0x08}},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			resetTokenOrderTest(cur)
			path := forwardPath(1, 2)
			packet := core.NewPacket(cross(cur), core.ChannelId(9), core.ChannelId(10), nil, 0, 0)
			order := batchRefundOrder("fc-"+tc.key, "ibc/fc-"+tc.key, "quote", 23)
			increaseChannelBalanceV2(cross(cur), packet.SourceChannelId, path, order.BaseToken, order.QuoteToken, order.BaseAmount)
			forward := z.Forward{
				Path:        path,
				Instruction: batchMustOrderInstruction(order),
			}
			instr := z.Instruction{
				Version: z.INSTR_VERSION_0,
				Opcode:  z.OP_FORWARD,
				Operand: mustForwardBytes(forward),
			}
			outerAck := mustAckBytes(z.Ack{
				Tag:      tagAckSuccess(),
				InnerAck: tc.ack,
			})

			err := (&ZkgmV1{}).dispatchAck(cur, packet, u256.Zero(), [32]byte{0x34}, instr, outerAck)

			uassert.NoError(t, err)
			assertNoChannelBalance(t, packet.SourceChannelId, path, order)
			uassert.Equal(t, int64(23), VoucherBalanceOf(string(order.BaseToken), address(string(order.Sender))))
		})
	}
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

func mustBatchAckBytes(acks [][]byte) []byte {
	out, err := z.EncodeBatchAck(z.BatchAck{Acknowledgements: acks})
	if err != nil {
		panic(err)
	}
	return out
}

func mustAckBytes(ack z.Ack) []byte {
	out, err := z.EncodeAck(ack)
	if err != nil {
		panic(err)
	}
	return out
}
