package impl

// batch_test.gno covers batch.gno's verify/acknowledge/timeout logic and the
// funds-accounting it drives. The send-path native funds checks are exercised
// here directly against verifyBatch + funds.assertEmpty (the Send entry point
// itself is integration-tested in the e2e suite). executeBatch is covered here
// for unit-level ack/short-circuit behavior with an injected mock receiver.

import (
	"bytes"
	"testing"

	types "gno.land/p/onbloc/ibc/union/types"

	u256 "gno.land/p/gnoswap/uint256"
	"gno.land/p/nt/uassert/v0"
	z "gno.land/p/onbloc/ibc/union/zkgm"
	"gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/testing/mock"
	core "gno.land/r/onbloc/ibc/union/core"
)

func TestVerifyBatchRejectsNestedBatch(cur realm, t *testing.T) {
	batch := z.Batch{Instructions: []z.Instruction{{
		Version: z.INSTR_VERSION_0,
		Opcode:  z.OP_BATCH,
	}}}

	err := newTestImpl().verifyBatch(0, cur, newFunds(nil), types.ChannelId(1), u256.Zero(), batch)

	uassert.ErrorContains(t, err, "invalid batch instruction")
}

func TestVerifyBatchPassesAllowedCallChildren(cur realm, t *testing.T) {
	sender := testAddress("batch-call-caller")
	batch := z.Batch{Instructions: []z.Instruction{
		batchMustCallInstruction(batchCall(sender, "a")),
		batchMustCallInstruction(batchCall(sender, "b")),
	}}

	testing.SetRealm(testing.NewUserRealm(address(sender)))
	err := newTestImpl().verifyBatchX(cross(cur), newFunds(nil), types.ChannelId(1), u256.Zero(), batch)

	uassert.NoError(t, err)
}

func TestVerifyBatchExactTotalNativeConsumptionPasses(cur realm, t *testing.T) {
	v := newTestImpl()
	const channelId = types.ChannelId(92)
	orderA := batchRefundOrder("batch-exact-a", "ugnot", "quote-exact-a", 60)
	orderB := batchRefundOrder("batch-exact-b", "ugnot", "quote-exact-b", 40)
	batch := z.Batch{Instructions: []z.Instruction{
		batchMustOrderInstruction(orderA),
		batchMustOrderInstruction(orderB),
	}}
	f := newFunds(parseCoins("100ugnot"))

	err := v.verifyBatch(0, cur, f, channelId, u256.Zero(), batch)
	uassert.NoError(t, err)
	uassert.NoError(t, f.assertEmpty())

	balanceA, _ := testStore.GetChannelBalanceV2(ChannelBalanceKeyV2(channelId, u256.Zero(), orderA.BaseToken, orderA.QuoteToken))
	uassert.Equal(t, "60", balanceA.ToString())
	balanceB, _ := testStore.GetChannelBalanceV2(ChannelBalanceKeyV2(channelId, u256.Zero(), orderB.BaseToken, orderB.QuoteToken))
	uassert.Equal(t, "40", balanceB.ToString())
}

func TestVerifyBatchDuplicateNativeConsumptionRejected(cur realm, t *testing.T) {
	v := newTestImpl()
	batch := z.Batch{Instructions: []z.Instruction{
		batchMustOrderInstruction(batchRefundOrder("batch-dup-a", "ugnot", "quote-dup-a", 100)),
		batchMustOrderInstruction(batchRefundOrder("batch-dup-b", "ugnot", "quote-dup-b", 100)),
	}}

	err := v.verifyBatch(0, cur, newFunds(parseCoins("100ugnot")), types.ChannelId(91), u256.Zero(), batch)

	uassert.ErrorContains(t, err, "sent coin mismatch")
}

func TestVerifyBatchLeftoverNativeRejected(cur realm, t *testing.T) {
	v := newTestImpl()
	batch := z.Batch{Instructions: []z.Instruction{
		batchMustOrderInstruction(batchRefundOrder("batch-left", "ugnot", "quote-leftover", 60)),
	}}
	f := newFunds(parseCoins("100ugnot"))

	err := v.verifyBatch(0, cur, f, types.ChannelId(93), u256.Zero(), batch)
	uassert.NoError(t, err)
	// 40ugnot left unconsumed → the send-path drain check must reject it.
	uassert.ErrorContains(t, f.assertEmpty(), "sent coin mismatch")
}

func TestVerifyBatchMultiDenomExactPasses(cur realm, t *testing.T) {
	v := newTestImpl()
	batch := z.Batch{Instructions: []z.Instruction{
		batchMustOrderInstruction(batchRefundOrder("batch-denom-a", "ugnot", "quote-denom-a", 100)),
		batchMustOrderInstruction(batchRefundOrder("batch-denom-b", "foo", "quote-denom-b", 50)),
	}}
	f := newFunds(parseCoins("100ugnot,50foo"))

	err := v.verifyBatch(0, cur, f, types.ChannelId(95), u256.Zero(), batch)
	uassert.NoError(t, err)
	uassert.NoError(t, f.assertEmpty())
}

func TestVerifyBatchMultiDenomShortfallRejected(cur realm, t *testing.T) {
	v := newTestImpl()
	batch := z.Batch{Instructions: []z.Instruction{
		batchMustOrderInstruction(batchRefundOrder("batch-denom-sa", "ugnot", "quote-denom-sa", 100)),
		batchMustOrderInstruction(batchRefundOrder("batch-denom-sb", "foo", "quote-denom-sb", 50)),
	}}

	err := v.verifyBatch(0, cur, newFunds(parseCoins("100ugnot,40foo")), types.ChannelId(96), u256.Zero(), batch)

	uassert.ErrorContains(t, err, "sent coin mismatch")
}

func TestAcknowledgeBatchRejectsAckCountMismatch(cur realm, t *testing.T) {
	packet := core.NewPacket(types.ChannelId(7), types.ChannelId(8), nil, 0)
	batch := z.Batch{Instructions: []z.Instruction{
		batchMustCallInstruction(batchCall("sender", "first")),
		batchMustCallInstruction(batchCall("sender", "second")),
	}}

	outerAck := mustBatchOuterAck([][]byte{mustSuccessAck()})
	err := newTestImpl().acknowledgeBatch(0, cur, packet, address(""), [32]byte{}, u256.Zero(), batch, true, outerAck.InnerAck)

	uassert.ErrorContains(t, err, "batch ack count mismatch")
}

func TestExecuteBatchPropagatesOnlyMakerAndSkipsRemainingChildren(cur realm, t *testing.T) {
	mock.Reset(cross(cur))
	testStore = newMockStore()
	testStore.SetReceiver(0, cur, mockReceiverPath, mock.Zkgmable(cross(cur)))

	onlyMakerOrder := z.TokenOrderV2{
		Kind:        z.TOKEN_ORDER_KIND_SOLVE,
		Sender:      []byte(testAddress("batch-om-sender")),
		Receiver:    []byte(testAddress("batch-om-receiver")),
		BaseToken:   []byte("uatom"),
		BaseAmount:  u256.NewUint(10),
		QuoteToken:  []byte("ibc/batch-only-maker-quote"),
		QuoteAmount: u256.NewUint(10),
	}
	batch := z.Batch{Instructions: []z.Instruction{
		batchMustOrderInstruction(onlyMakerOrder),
		batchMustCallInstruction(batchCall("sender", "must-not-run")),
	}}
	packet := core.NewPacket(types.ChannelId(7), types.ChannelId(8), nil, 0)

	ack, err := newTestImpl().executeBatch(0, cur, packet, address(testAddress("relayer")), nil, [32]byte{}, u256.Zero(), batch, false)

	uassert.NoError(t, err)
	uassert.True(t, bytes.Equal(z.ACK_ERR_ONLY_MAKER, ack))
	uassert.Equal(t, 0, mock.Calls(cross(cur)))
}

func TestAcknowledgeBatchFailureRefundsTokenOrderChildren(cur realm, t *testing.T) {
	v := newTestImpl()
	path := u256.NewUint(29)
	packet := core.NewPacket(types.ChannelId(7), types.ChannelId(8), nil, 0)
	orderA := batchRefundOrder("ack-fail-a", "ibc/batch-ack-fail-a", "quote-a", 11)
	orderB := batchRefundOrder("ack-fail-b", "ibc/batch-ack-fail-b", "quote-b", 17)
	v.increaseChannelBalanceV2(0, cur, types.ChannelId(7), path, orderA.BaseToken, orderA.QuoteToken, orderA.BaseAmount)
	v.increaseChannelBalanceV2(0, cur, types.ChannelId(7), path, orderB.BaseToken, orderB.QuoteToken, orderB.BaseAmount)
	uassert.NoError(t, v.mintVoucher(0, cur, string(orderA.BaseToken), [32]byte{}, "", "", 0, cur.Address().String(), orderA.BaseAmount))
	uassert.NoError(t, v.mintVoucher(0, cur, string(orderB.BaseToken), [32]byte{}, "", "", 0, cur.Address().String(), orderB.BaseAmount))
	batch := z.Batch{Instructions: []z.Instruction{
		batchMustOrderInstruction(orderA),
		batchMustOrderInstruction(orderB),
	}}

	err := v.acknowledgeBatch(0, cur, packet, address(testAddress("relayer")), [32]byte{}, path, batch, false, nil)

	uassert.NoError(t, err)
	assertNoChannelBalance(t, types.ChannelId(7), path, orderA)
	assertNoChannelBalance(t, types.ChannelId(7), path, orderB)
	uassert.Equal(t, int64(11), voucherBalanceOf("ibc/batch-ack-fail-a", address(orderA.Sender)))
	uassert.Equal(t, int64(17), voucherBalanceOf("ibc/batch-ack-fail-b", address(orderB.Sender)))
}

func TestTimeoutBatchTokenOrderChildrenRefund(cur realm, t *testing.T) {
	v := newTestImpl()
	path := u256.NewUint(23)
	packet := core.NewPacket(types.ChannelId(7), types.ChannelId(8), nil, 0)
	orderA := batchRefundOrder("timeout-a", "ibc/batch-timeout-a", "quote-a", 11)
	orderB := batchRefundOrder("timeout-b", "ibc/batch-timeout-b", "quote-b", 17)
	v.increaseChannelBalanceV2(0, cur, types.ChannelId(7), path, orderA.BaseToken, orderA.QuoteToken, orderA.BaseAmount)
	v.increaseChannelBalanceV2(0, cur, types.ChannelId(7), path, orderB.BaseToken, orderB.QuoteToken, orderB.BaseAmount)
	// Escrow the wrapped vouchers in the proxy so the timeout refund can transfer
	// them back to each sender (settleEscrowedV2 moves ibc/ vouchers out of escrow).
	uassert.NoError(t, v.mintVoucher(0, cur, string(orderA.BaseToken), [32]byte{}, "", "", 0, cur.Address().String(), orderA.BaseAmount))
	uassert.NoError(t, v.mintVoucher(0, cur, string(orderB.BaseToken), [32]byte{}, "", "", 0, cur.Address().String(), orderB.BaseAmount))
	batch := z.Batch{Instructions: []z.Instruction{
		batchMustOrderInstruction(orderA),
		batchMustOrderInstruction(orderB),
	}}

	err := v.timeoutBatch(0, cur, packet, [32]byte{}, path, batch)

	uassert.NoError(t, err)
	assertNoChannelBalance(t, types.ChannelId(7), path, orderA)
	assertNoChannelBalance(t, types.ChannelId(7), path, orderB)
	uassert.Equal(t, int64(11), voucherBalanceOf("ibc/batch-timeout-a", address(orderA.Sender)))
	uassert.Equal(t, int64(17), voucherBalanceOf("ibc/batch-timeout-b", address(orderB.Sender)))
}

func batchCall(sender string, calldata string) z.Call {
	return z.Call{
		Sender:           []byte(sender),
		ContractAddress:  []byte(mockReceiverPath),
		ContractCalldata: []byte(calldata),
	}
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

func assertNoChannelBalance(t *testing.T, channelId types.ChannelId, path *u256.Uint, order z.TokenOrderV2) {
	balance, ok := testStore.GetChannelBalanceV2(ChannelBalanceKeyV2(channelId, path, order.BaseToken, order.QuoteToken))
	uassert.True(t, ok && balance.IsZero())
}

func mustBatchOuterAck(childAcks [][]byte) z.Ack {
	batchAck, err := z.EncodeBatchAck(z.BatchAck{Acknowledgements: childAcks})
	if err != nil {
		panic(err)
	}
	return z.Ack{Tag: tagAckSuccess(), InnerAck: batchAck}
}

func mustSuccessAck() []byte {
	ack, err := z.EncodeAck(z.Ack{Tag: tagAckSuccess(), InnerAck: []byte{}})
	if err != nil {
		panic(err)
	}
	return ack
}
