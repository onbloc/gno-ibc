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

	err := (&ZkgmV1{}).verifyBatch(core.ChannelId(1), "sender", nil, u256.Zero(), [32]byte{}, batch)

	uassert.ErrorContains(t, err, "invalid batch instruction")
}

func TestVerifyBatchPassesAllowedCallChildren(cur realm, t *testing.T) {
	batch := z.Batch{Instructions: []z.Instruction{
		batchMustCallInstruction(batchCall("sender", "a")),
		batchMustCallInstruction(batchCall("sender", "b")),
	}}

	err := (&ZkgmV1{}).verifyBatch(core.ChannelId(1), "sender", nil, u256.Zero(), [32]byte{}, batch)

	uassert.NoError(t, err)
}

func TestExecuteBatchAggregatesChildAcks(cur realm, t *testing.T) {
	mock.Reset(cross)
	packet := core.Packet{SourceChannelId: core.ChannelId(7), DestinationChannelId: core.ChannelId(8)}
	batch := z.Batch{Instructions: []z.Instruction{
		batchMustCallInstruction(batchCall("sender", "first")),
		batchMustCallInstruction(batchCall("sender", "second")),
	}}

	ackBytes, err := (&ZkgmV1{}).executeBatch(packet, address("g1relayer"), nil, u256.NewUint(9), [32]byte{0xAA}, batch, false)

	uassert.NoError(t, err)
	uassert.Equal(t, 2, mock.Calls(cross))
	outerAck, err := z.DecodeAck(ackBytes)
	uassert.NoError(t, err)
	uassert.True(t, outerAck.Tag.Eq(tagAckSuccess))
	batchAck, err := z.DecodeBatchAck(outerAck.InnerAck)
	uassert.NoError(t, err)
	uassert.Equal(t, 2, len(batchAck.Acknowledgements))
	assertSuccessAck(t, batchAck.Acknowledgements[0])
	assertSuccessAck(t, batchAck.Acknowledgements[1])
	uassert.Equal(t, "second", mock.LastCalldata(cross))
}

func TestExecuteBatchPanicChildPropagatesOnlyMaker(cur realm, t *testing.T) {
	mock.Reset(cross)
	mock.SetPanic(cross, "boom")
	packet := core.Packet{SourceChannelId: core.ChannelId(7), DestinationChannelId: core.ChannelId(8)}
	batch := z.Batch{Instructions: []z.Instruction{
		batchMustCallInstruction(batchCall("sender", "first")),
		batchMustCallInstruction(batchCall("sender", "second")),
	}}

	ackBytes, err := (&ZkgmV1{}).executeBatch(packet, address("g1relayer"), nil, u256.Zero(), [32]byte{0xBB}, batch, false)

	uassert.NoError(t, err)
	uassert.True(t, isOnlyMakerAck(ackBytes))
	uassert.Equal(t, 1, mock.Calls(cross))
}

func TestAcknowledgeBatchRejectsAckCountMismatch(cur realm, t *testing.T) {
	packet := core.Packet{SourceChannelId: core.ChannelId(7), DestinationChannelId: core.ChannelId(8)}
	batch := z.Batch{Instructions: []z.Instruction{
		batchMustCallInstruction(batchCall("sender", "first")),
		batchMustCallInstruction(batchCall("sender", "second")),
	}}

	err := (&ZkgmV1{}).acknowledgeBatch(packet, u256.Zero(), [32]byte{}, batch, mustBatchOuterAck([][]byte{mustSuccessAck()}))

	uassert.ErrorContains(t, err, "batch ack count mismatch")
}

func TestTimeoutBatchTokenOrderChildrenRefund(cur realm, t *testing.T) {
	resetTokenOrderTest()
	path := u256.NewUint(23)
	packet := core.Packet{SourceChannelId: core.ChannelId(7), DestinationChannelId: core.ChannelId(8)}
	orderA := batchRefundOrder("timeout-a", "ibc/batch-timeout-a", "quote-a", 11)
	orderB := batchRefundOrder("timeout-b", "ibc/batch-timeout-b", "quote-b", 17)
	increaseChannelBalanceV2(cross, core.ChannelId(7), path, orderA.BaseToken, orderA.QuoteToken, orderA.BaseAmount)
	increaseChannelBalanceV2(cross, core.ChannelId(7), path, orderB.BaseToken, orderB.QuoteToken, orderB.BaseAmount)
	batch := z.Batch{Instructions: []z.Instruction{
		batchMustOrderInstruction(orderA),
		batchMustOrderInstruction(orderB),
	}}

	err := (&ZkgmV1{}).timeoutBatch(packet, path, [32]byte{}, batch)

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
