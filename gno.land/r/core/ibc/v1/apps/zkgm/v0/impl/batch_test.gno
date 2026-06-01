package impl

import (
	"testing"

	z "gno.land/p/gnoswap/ibc/zkgm"
	u256 "gno.land/p/gnoswap/uint256"
	"gno.land/p/nt/uassert/v0"
	core "gno.land/r/core/ibc/v1/core"
	zkgm "gno.land/r/gnoswap/ibc/v1/apps/zkgm"
	"gno.land/r/gnoswap/ibc/v1/apps/zkgm/testing/mock"
)

func TestVerifyBatchRejectsNestedBatch(cur realm, t *testing.T) {
	batch := z.Batch{Instructions: []z.Instruction{{
		Version: z.INSTR_VERSION_0,
		Opcode:  z.OP_BATCH,
	}}}

	err := (&ZkgmV1{}).verifyBatch(cur, core.ChannelId(1), "sender", newSentCoinBudget(nil), u256.Zero(), [32]byte{}, batch)

	uassert.ErrorContains(t, err, "invalid batch instruction")
}

func TestVerifyBatchPassesAllowedCallChildren(cur realm, t *testing.T) {
	batch := z.Batch{Instructions: []z.Instruction{
		batchMustCallInstruction(batchCall("sender", "a")),
		batchMustCallInstruction(batchCall("sender", "b")),
	}}

	err := (&ZkgmV1{}).verifyBatch(cur, core.ChannelId(1), "sender", newSentCoinBudget(nil), u256.Zero(), [32]byte{}, batch)

	uassert.NoError(t, err)
}

func TestVerifyBatchRejectsDuplicateNativeConsumption(cur realm, t *testing.T) {
	resetTokenOrderTest(cur)
	sender := testAddress("batch-dup-sender")
	instr := batchMustBatchInstruction(z.Batch{Instructions: []z.Instruction{
		batchMustOrderInstruction(batchRefundOrder("batch-dup-a", "ugnot", "quote-dup-a", 100)),
		batchMustOrderInstruction(batchRefundOrder("batch-dup-b", "ugnot", "quote-dup-b", 100)),
	}})

	_, err := (&ZkgmV1{}).Send(cur, zkgm.NewSendRequest(
		cross(cur),
		core.ChannelId(91),
		0,
		[32]byte{0x91},
		instr,
		sender,
		"100ugnot",
	))

	uassert.ErrorContains(t, err, "sent coin mismatch")
}

func TestVerifyBatchExactTotalNativeConsumptionPasses(cur realm, t *testing.T) {
	resetTokenOrderTest(cur)
	sender := testAddress("batch-exact-sender")
	orderA := batchRefundOrder("batch-exact-a", "ugnot", "quote-exact-a", 60)
	orderB := batchRefundOrder("batch-exact-b", "ugnot", "quote-exact-b", 40)
	instr := batchMustBatchInstruction(z.Batch{Instructions: []z.Instruction{
		batchMustOrderInstruction(orderA),
		batchMustOrderInstruction(orderB),
	}})

	_, err := (&ZkgmV1{}).Send(cur, zkgm.NewSendRequest(
		cross(cur),
		core.ChannelId(92),
		0,
		[32]byte{0x92},
		instr,
		sender,
		"100ugnot",
	))

	uassert.NoError(t, err)
	balanceA := zkgm.GetChannelBalanceV2(ChannelBalanceKeyV2(core.ChannelId(92), u256.Zero(), orderA.BaseToken, orderA.QuoteToken))
	uassert.Equal(t, "60", balanceA.ToString())
	balanceB := zkgm.GetChannelBalanceV2(ChannelBalanceKeyV2(core.ChannelId(92), u256.Zero(), orderB.BaseToken, orderB.QuoteToken))
	uassert.Equal(t, "40", balanceB.ToString())
}

func TestVerifyBatchLeftoverNativeRejected(cur realm, t *testing.T) {
	resetTokenOrderTest(cur)
	sender := testAddress("batch-left-sender")
	instr := batchMustBatchInstruction(z.Batch{Instructions: []z.Instruction{
		batchMustOrderInstruction(batchRefundOrder("batch-left", "ugnot", "quote-leftover", 60)),
	}})

	_, err := (&ZkgmV1{}).Send(cur, zkgm.NewSendRequest(
		cross(cur),
		core.ChannelId(93),
		0,
		[32]byte{0x93},
		instr,
		sender,
		"100ugnot",
	))

	uassert.ErrorContains(t, err, "sent coin mismatch")
}

func TestVerifyBatchMixedNativeAndVoucher(cur realm, t *testing.T) {
	resetTokenOrderTest(cur)
	sender := testAddress("batch-mixed-sender")
	voucherDenom := "ibc/batch-mixed"
	uassert.NoError(t, mintVoucher(cross(cur), voucherDenom, voucherDenom, [32]byte{}, sender, u256.NewUint(20)))
	instr := batchMustBatchInstruction(z.Batch{Instructions: []z.Instruction{
		batchMustOrderInstruction(z.TokenOrderV2{
			Sender:      []byte(sender),
			BaseToken:   []byte(voucherDenom),
			BaseAmount:  u256.NewUint(7),
			QuoteToken:  []byte("quote-mixed-voucher"),
			QuoteAmount: u256.NewUint(7),
			Kind:        z.TOKEN_ORDER_KIND_ESCROW,
		}),
		batchMustOrderInstruction(batchRefundOrder("batch-mixed-native", "ugnot", "quote-mixed-native", 100)),
	}})

	_, err := (&ZkgmV1{}).Send(cur, zkgm.NewSendRequest(
		cross(cur),
		core.ChannelId(94),
		0,
		[32]byte{0x94},
		instr,
		sender,
		"100ugnot",
	))

	uassert.NoError(t, err)
	uassert.Equal(t, int64(13), VoucherBalanceOf(voucherDenom, address(sender)))
}

func TestVerifyBatchMultiDenom(cur realm, t *testing.T) {
	resetTokenOrderTest(cur)
	sender := testAddress("batch-denom-sender")
	instr := batchMustBatchInstruction(z.Batch{Instructions: []z.Instruction{
		batchMustOrderInstruction(batchRefundOrder("batch-denom-a", "ugnot", "quote-denom-a", 100)),
		batchMustOrderInstruction(batchRefundOrder("batch-denom-b", "foo", "quote-denom-b", 50)),
	}})

	_, err := (&ZkgmV1{}).Send(cur, zkgm.NewSendRequest(
		cross(cur),
		core.ChannelId(95),
		0,
		[32]byte{0x95},
		instr,
		sender,
		"100ugnot,50foo",
	))
	uassert.NoError(t, err)

	resetTokenOrderTest(cur)
	_, err = (&ZkgmV1{}).Send(cur, zkgm.NewSendRequest(
		cross(cur),
		core.ChannelId(96),
		0,
		[32]byte{0x96},
		instr,
		sender,
		"100ugnot,40foo",
	))
	uassert.ErrorContains(t, err, "sent coin mismatch")
}

func TestExecuteBatchAggregatesChildAcks(cur realm, t *testing.T) {
	mock.Reset(cross(cur))
	packet := core.NewPacket(cross(cur), core.ChannelId(7), core.ChannelId(8), nil, 0, 0)
	batch := z.Batch{Instructions: []z.Instruction{
		batchMustCallInstruction(batchCall("sender", "first")),
		batchMustCallInstruction(batchCall("sender", "second")),
	}}

	ackBytes, err := (&ZkgmV1{}).executeBatch(cur, packet, address("g1relayer"), nil, u256.NewUint(9), [32]byte{0xAA}, batch, false)

	uassert.NoError(t, err)
	uassert.Equal(t, 2, mock.Calls(cross(cur)))
	outerAck, err := z.DecodeAck(ackBytes)
	uassert.NoError(t, err)
	uassert.True(t, outerAck.Tag.Eq(tagAckSuccess))
	batchAck, err := z.DecodeBatchAck(outerAck.InnerAck)
	uassert.NoError(t, err)
	uassert.Equal(t, 2, len(batchAck.Acknowledgements))
	assertSuccessAck(t, batchAck.Acknowledgements[0])
	assertSuccessAck(t, batchAck.Acknowledgements[1])
	uassert.Equal(t, "second", mock.LastCalldata(cross(cur)))
}

func TestExecuteBatchPanicChildPropagatesOnlyMaker(cur realm, t *testing.T) {
	mock.Reset(cross(cur))
	mock.SetPanic(cross(cur), "boom")
	packet := core.NewPacket(cross(cur), core.ChannelId(7), core.ChannelId(8), nil, 0, 0)
	batch := z.Batch{Instructions: []z.Instruction{
		batchMustCallInstruction(batchCall("sender", "first")),
		batchMustCallInstruction(batchCall("sender", "second")),
	}}

	ackBytes, err := (&ZkgmV1{}).executeBatch(cur, packet, address("g1relayer"), nil, u256.Zero(), [32]byte{0xBB}, batch, false)

	uassert.NoError(t, err)
	uassert.True(t, isOnlyMakerAck(ackBytes))
	uassert.Equal(t, 1, mock.Calls(cross(cur)))
}

func TestAcknowledgeBatchRejectsAckCountMismatch(cur realm, t *testing.T) {
	packet := core.NewPacket(cross(cur), core.ChannelId(7), core.ChannelId(8), nil, 0, 0)
	batch := z.Batch{Instructions: []z.Instruction{
		batchMustCallInstruction(batchCall("sender", "first")),
		batchMustCallInstruction(batchCall("sender", "second")),
	}}

	err := (&ZkgmV1{}).acknowledgeBatch(cur, packet, u256.Zero(), [32]byte{}, batch, mustBatchOuterAck([][]byte{mustSuccessAck()}))

	uassert.ErrorContains(t, err, "batch ack count mismatch")
}

func TestTimeoutBatchTokenOrderChildrenRefund(cur realm, t *testing.T) {
	resetTokenOrderTest(cur)
	path := u256.NewUint(23)
	packet := core.NewPacket(cross(cur), core.ChannelId(7), core.ChannelId(8), nil, 0, 0)
	orderA := batchRefundOrder("timeout-a", "ibc/batch-timeout-a", "quote-a", 11)
	orderB := batchRefundOrder("timeout-b", "ibc/batch-timeout-b", "quote-b", 17)
	increaseChannelBalanceV2(cross(cur), core.ChannelId(7), path, orderA.BaseToken, orderA.QuoteToken, orderA.BaseAmount)
	increaseChannelBalanceV2(cross(cur), core.ChannelId(7), path, orderB.BaseToken, orderB.QuoteToken, orderB.BaseAmount)
	batch := z.Batch{Instructions: []z.Instruction{
		batchMustOrderInstruction(orderA),
		batchMustOrderInstruction(orderB),
	}}

	err := (&ZkgmV1{}).timeoutBatch(cur, packet, path, [32]byte{}, batch)

	uassert.NoError(t, err)
	assertNoChannelBalance(t, core.ChannelId(7), path, orderA)
	assertNoChannelBalance(t, core.ChannelId(7), path, orderB)
	uassert.Equal(t, int64(11), VoucherBalanceOf("ibc/batch-timeout-a", address(orderA.Sender)))
	uassert.Equal(t, int64(17), VoucherBalanceOf("ibc/batch-timeout-b", address(orderB.Sender)))
}

func batchCall(sender string, calldata string) z.Call {
	return z.Call{
		Sender:           []byte(sender),
		ContractAddress:  []byte(mockReceiverPath),
		ContractCalldata: []byte(calldata),
	}
}

func batchMustCallInstruction(call z.Call) z.Instruction {
	bz, err := z.EncodeCall(call)
	if err != nil {
		panic(err)
	}
	return z.Instruction{Version: z.INSTR_VERSION_0, Opcode: z.OP_CALL, Operand: bz}
}

func batchMustOrderInstruction(order z.TokenOrderV2) z.Instruction {
	bz, err := z.EncodeTokenOrderV2(order)
	if err != nil {
		panic(err)
	}
	return z.Instruction{Version: z.INSTR_VERSION_2, Opcode: z.OP_TOKEN_ORDER, Operand: bz}
}

func batchMustBatchInstruction(batch z.Batch) z.Instruction {
	bz, err := z.EncodeBatch(batch)
	if err != nil {
		panic(err)
	}
	return z.Instruction{Version: z.INSTR_VERSION_0, Opcode: z.OP_BATCH, Operand: bz}
}

func batchRefundOrder(sender string, baseToken string, quoteToken string, amount uint64) z.TokenOrderV2 {
	return z.TokenOrderV2{
		Sender:      []byte(testAddress(sender)),
		BaseToken:   []byte(baseToken),
		BaseAmount:  u256.NewUint(amount),
		QuoteToken:  []byte(quoteToken),
		QuoteAmount: u256.NewUint(amount),
		Kind:        z.TOKEN_ORDER_KIND_ESCROW,
	}
}

func assertNoChannelBalance(t *testing.T, channelId core.ChannelId, path *u256.Uint, order z.TokenOrderV2) {
	balance := zkgm.GetChannelBalanceV2(ChannelBalanceKeyV2(channelId, path, order.BaseToken, order.QuoteToken))
	// nil is the canonical post-drain state (decreaseChannelBalanceV2 removes
	// the entry on zero); IsZero() defends against out-of-band zero writes.
	uassert.True(t, balance == nil || balance.IsZero())
}

func mustBatchOuterAck(childAcks [][]byte) z.Ack {
	batchAck, err := z.EncodeBatchAck(z.BatchAck{Acknowledgements: childAcks})
	if err != nil {
		panic(err)
	}
	return z.Ack{Tag: tagAckSuccess, InnerAck: batchAck}
}

func mustSuccessAck() []byte {
	ack, err := z.EncodeAck(z.Ack{Tag: tagAckSuccess, InnerAck: []byte{}})
	if err != nil {
		panic(err)
	}
	return ack
}

func assertSuccessAck(t *testing.T, ackBytes []byte) {
	ack, err := z.DecodeAck(ackBytes)
	uassert.NoError(t, err)
	uassert.True(t, ack.Tag.Eq(tagAckSuccess))
}
