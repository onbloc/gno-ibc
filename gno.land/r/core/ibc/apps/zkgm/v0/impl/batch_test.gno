package impl

import (
	"testing"

	"gno.land/p/aib/ibc/types"
	z "gno.land/p/gnoswap/ibc/zkgm"
	u256 "gno.land/p/gnoswap/uint256"
	"gno.land/p/nt/uassert/v0"
	zkgm "gno.land/r/gnoswap/ibc/apps/zkgm"
	"gno.land/r/gnoswap/ibc/apps/zkgm/testing/mock"
)

func TestVerifyBatchRejectsNestedBatch(cur realm, t *testing.T) {
	batch := z.Batch{Instructions: []z.Instruction{{
		Version: z.INSTR_VERSION_0,
		Opcode:  z.OP_BATCH,
	}}}

	err := (&ZkgmV0{}).verifyBatch("client-a", "sender", nil, u256.Zero(), batch)

	uassert.ErrorContains(t, err, "invalid batch instruction")
}

func TestVerifyBatchRejectsForward(cur realm, t *testing.T) {
	batch := z.Batch{Instructions: []z.Instruction{{
		Version: z.INSTR_VERSION_0,
		Opcode:  z.OP_FORWARD,
	}}}

	err := (&ZkgmV0{}).verifyBatch("client-a", "sender", nil, u256.Zero(), batch)

	uassert.ErrorContains(t, err, "invalid batch instruction")
}

func TestVerifyBatchPassesAllowedCallChildren(cur realm, t *testing.T) {
	callA := batchCall("sender", "a")
	callB := batchCall("sender", "b")
	batch := z.Batch{Instructions: []z.Instruction{
		mustCallInstruction(callA),
		mustCallInstruction(callB),
	}}

	err := (&ZkgmV0{}).verifyBatch("client-a", "sender", nil, u256.Zero(), batch)

	uassert.NoError(t, err)
}

func TestExecuteBatchAggregatesChildAcks(cur realm, t *testing.T) {
	mock.Reset(cross)
	batch := z.Batch{Instructions: []z.Instruction{
		mustCallInstruction(batchCall("sender", "first")),
		mustCallInstruction(batchCall("sender", "second")),
	}}

	ackBytes, err := (&ZkgmV0{}).executeBatch(zkgm.RecvRequest{
		SourceClient:      "client-a",
		DestinationClient: "client-b",
		Caller:            "relayer",
		Relayer:           []byte("relayer"),
	}, u256.NewUint(9), [32]byte{0xAA}, batch, false)

	uassert.NoError(t, err)
	uassert.Equal(t, 2, mock.Calls())
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
	batch := z.Batch{Instructions: []z.Instruction{
		mustCallInstruction(batchCall("sender", "first")),
		mustCallInstruction(batchCall("sender", "second")),
	}}

	ackBytes, err := (&ZkgmV0{}).executeBatch(zkgm.RecvRequest{
		SourceClient:      "client-a",
		DestinationClient: "client-b",
		Caller:            "relayer",
	}, u256.Zero(), [32]byte{0xBB}, batch, false)

	uassert.NoError(t, err)
	uassert.True(t, isOnlyMakerAck(ackBytes))
	uassert.Equal(t, 1, mock.Calls())
}

func TestAcknowledgeBatchDistributesCallAcks(cur realm, t *testing.T) {
	batch := z.Batch{Instructions: []z.Instruction{
		mustCallInstruction(batchCall("sender", "first")),
		mustCallInstruction(batchCall("sender", "second")),
	}}
	outerAck := mustBatchOuterAck([][]byte{mustSuccessAck(), mustSuccessAck()})

	err := (&ZkgmV0{}).acknowledgeBatch(zkgm.AckRequest{
		SourceClient: "client-a",
	}, u256.Zero(), [32]byte{0xCC}, batch, outerAck)

	uassert.NoError(t, err)
}

func TestTimeoutBatchDistributesCallChildren(cur realm, t *testing.T) {
	batch := z.Batch{Instructions: []z.Instruction{
		mustCallInstruction(batchCall("sender", "first")),
		mustCallInstruction(batchCall("sender", "second")),
	}}

	err := (&ZkgmV0{}).timeoutBatch(zkgm.TimeoutRequest{
		SourceClient: "client-a",
	}, u256.Zero(), [32]byte{0xDD}, batch)

	uassert.NoError(t, err)
}

func TestRecvDispatchesBatchOpcode(cur realm, t *testing.T) {
	mock.Reset(cross)
	batch := z.Batch{Instructions: []z.Instruction{
		mustCallInstruction(batchCall("sender", "dispatch-a")),
		mustCallInstruction(batchCall("sender", "dispatch-b")),
	}}
	payload := mustBatchPayload(batch)

	res, err := (&ZkgmV0{}).Recv(zkgm.RecvRequest{
		SourceClient:      "client-a",
		DestinationClient: "client-b",
		Payload:           payload,
		Caller:            "relayer",
		Relayer:           []byte("relayer"),
	})

	uassert.NoError(t, err)
	uassert.True(t, res.Status == types.PacketStatus_Success)
	outerAck, err := z.DecodeAck(res.Acknowledgement)
	uassert.NoError(t, err)
	batchAck, err := z.DecodeBatchAck(outerAck.InnerAck)
	uassert.NoError(t, err)
	uassert.Equal(t, 2, len(batchAck.Acknowledgements))
	uassert.Equal(t, 2, mock.Calls())
	uassert.Equal(t, "dispatch-b", mock.LastCalldata(cross))
}

func TestExecuteBatchMixedOpcodes(cur realm, t *testing.T) {
	resetImplForTest()
	mock.Reset(cross)
	receiver := testAddress("mixed-receiver")
	metaBytes := mustEncodeTokenMetadata(z.TokenMetadata{
		Implementation: []byte("grc20"),
		Initializer:    []byte("init"),
	})
	image := MetadataImage(mustDecodeTokenMetadata(metaBytes))
	ibcDenom := PredictWrappedTokenV2(u256.NewUint(7), 1, []byte("ugnot"), image)
	order := z.TokenOrderV2{
		Receiver:    []byte(receiver),
		BaseToken:   []byte("ugnot"),
		BaseAmount:  u256.NewUint(100),
		QuoteToken:  []byte(ibcDenom),
		QuoteAmount: u256.NewUint(95),
		Kind:        z.TOKEN_ORDER_KIND_INITIALIZE,
		Metadata:    metaBytes,
	}
	batch := z.Batch{Instructions: []z.Instruction{
		mustCallInstruction(batchCall("sender", "call-payload")),
		mustOrderInstruction(order),
	}}

	ackBytes, err := (&ZkgmV0{}).executeBatch(zkgm.RecvRequest{
		SourceClient:      "client-a",
		DestinationClient: "client-1",
		Caller:            testAddress("relayer"),
	}, u256.NewUint(7), [32]byte{}, batch, false)

	uassert.NoError(t, err)
	uassert.Equal(t, 1, mock.Calls())
	outerAck, err := z.DecodeAck(ackBytes)
	uassert.NoError(t, err)
	uassert.True(t, outerAck.Tag.Eq(tagAckSuccess))
	batchAck, err := z.DecodeBatchAck(outerAck.InnerAck)
	uassert.NoError(t, err)
	uassert.Equal(t, 2, len(batchAck.Acknowledgements))
	assertSuccessAck(t, batchAck.Acknowledgements[0])
	assertSuccessAck(t, batchAck.Acknowledgements[1])

	uassert.Equal(t, int64(95), VoucherBalanceOf(ibcDenom, address(receiver)))
}

func TestAcknowledgeBatchUniversalErrorRefundsTokenOrderChildren(cur realm, t *testing.T) {
	resetImplForTest()
	path := u256.NewUint(17)
	orderA := batchRefundOrder("sender-a", "ibc/batch-refund-a", "quote-a", 13)
	orderB := batchRefundOrder("sender-b", "ibc/batch-refund-b", "quote-b", 29)
	increaseChannelBalanceV2(cross, "client-a", path, orderA.BaseToken, orderA.QuoteToken, orderA.BaseAmount)
	increaseChannelBalanceV2(cross, "client-a", path, orderB.BaseToken, orderB.QuoteToken, orderB.BaseAmount)
	batch := z.Batch{Instructions: []z.Instruction{
		mustOrderInstruction(orderA),
		mustOrderInstruction(orderB),
	}}

	err := (&ZkgmV0{}).acknowledgeBatch(zkgm.AckRequest{
		SourceClient: "client-a",
	}, path, [32]byte{}, batch, z.Ack{Tag: tagAckFailure})

	uassert.NoError(t, err)
	assertNoChannelBalance(t, "client-a", path, orderA)
	assertNoChannelBalance(t, "client-a", path, orderB)
	uassert.Equal(t, int64(13), VoucherBalanceOf("ibc/batch-refund-a", address(orderA.Sender)))
	uassert.Equal(t, int64(29), VoucherBalanceOf("ibc/batch-refund-b", address(orderB.Sender)))
}

func TestAcknowledgeBatchRejectsAckCountMismatch(cur realm, t *testing.T) {
	batch := z.Batch{Instructions: []z.Instruction{
		mustCallInstruction(batchCall("sender", "first")),
		mustCallInstruction(batchCall("sender", "second")),
	}}
	outerAck := mustBatchOuterAck([][]byte{mustSuccessAck()})

	err := (&ZkgmV0{}).acknowledgeBatch(zkgm.AckRequest{
		SourceClient: "client-a",
	}, u256.Zero(), [32]byte{}, batch, outerAck)

	uassert.ErrorContains(t, err, "batch ack count mismatch")
}

func TestTimeoutBatchTokenOrderChildrenRefund(cur realm, t *testing.T) {
	resetImplForTest()
	path := u256.NewUint(23)
	orderA := batchRefundOrder("timeout-a", "ibc/batch-timeout-a", "quote-a", 11)
	orderB := batchRefundOrder("timeout-b", "ibc/batch-timeout-b", "quote-b", 17)
	increaseChannelBalanceV2(cross, "client-a", path, orderA.BaseToken, orderA.QuoteToken, orderA.BaseAmount)
	increaseChannelBalanceV2(cross, "client-a", path, orderB.BaseToken, orderB.QuoteToken, orderB.BaseAmount)
	batch := z.Batch{Instructions: []z.Instruction{
		mustOrderInstruction(orderA),
		mustOrderInstruction(orderB),
	}}

	err := (&ZkgmV0{}).timeoutBatch(zkgm.TimeoutRequest{
		SourceClient: "client-a",
	}, path, [32]byte{}, batch)

	uassert.NoError(t, err)
	assertNoChannelBalance(t, "client-a", path, orderA)
	assertNoChannelBalance(t, "client-a", path, orderB)
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

func mustCallInstruction(call z.Call) z.Instruction {
	bz, err := z.EncodeCall(call)
	if err != nil {
		panic(err)
	}
	return z.Instruction{Version: z.INSTR_VERSION_0, Opcode: z.OP_CALL, Operand: bz}
}

func mustOrderInstruction(order z.TokenOrderV2) z.Instruction {
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

func assertNoChannelBalance(t *testing.T, channelID string, path *u256.Uint, order z.TokenOrderV2) {
	balance := zkgm.GetChannelBalanceV2(ChannelBalanceKeyV2(channelID, path, order.BaseToken, order.QuoteToken))
	uassert.True(t, balance == nil || balance.IsZero())
}

func mustBatchPayload(batch z.Batch) types.Payload {
	batchBytes, err := z.EncodeBatch(batch)
	if err != nil {
		panic(err)
	}
	packetBytes, err := z.EncodeZkgmPacket(z.ZkgmPacket{
		Salt: [32]byte{},
		Path: u256.Zero(),
		Instruction: z.Instruction{
			Version: z.INSTR_VERSION_0,
			Opcode:  z.OP_BATCH,
			Operand: batchBytes,
		},
	})
	if err != nil {
		panic(err)
	}
	return types.Payload{
		SourcePort:      PortID,
		DestinationPort: PortID,
		Version:         z.PROTOCOL_VERSION,
		Encoding:        packetEncoding,
		Value:           packetBytes,
	}
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
