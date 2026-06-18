package impl

// batch_test.gno covers batch.gno's verify/acknowledge/timeout logic and the
// funds-accounting it drives. The send-path native funds checks are exercised
// here directly against verifyBatch + funds.assertEmpty (the Send entry point
// itself is integration-tested in the e2e suite). executeBatch's call-dispatch
// (mock receiver) likewise lives in e2e since it needs a registered receiver.

import (
	"testing"

	types "gno.land/p/onbloc/ibc/union/types"

	u256 "gno.land/p/gnoswap/uint256"
	"gno.land/p/nt/uassert/v0"
	z "gno.land/p/onbloc/ibc/union/zkgm"
	core "gno.land/r/onbloc/ibc/union/core"
)

func TestVerifyBatchRejectsNestedBatch(cur realm, t *testing.T) {
	batch := z.Batch{Instructions: []z.Instruction{{
		Version: z.INSTR_VERSION_0,
		Opcode:  z.OP_BATCH,
	}}}

	err := newTestImpl().verifyBatch(0, cur, types.ChannelId(1), "sender", newFunds(nil), u256.Zero(), batch)

	uassert.ErrorContains(t, err, "invalid batch instruction")
}

func TestVerifyBatchPassesAllowedCallChildren(cur realm, t *testing.T) {
	batch := z.Batch{Instructions: []z.Instruction{
		batchMustCallInstruction(batchCall("sender", "a")),
		batchMustCallInstruction(batchCall("sender", "b")),
	}}

	err := newTestImpl().verifyBatch(0, cur, types.ChannelId(1), "sender", newFunds(nil), u256.Zero(), batch)

	uassert.NoError(t, err)
}

func TestVerifyBatchExactTotalNativeConsumptionPasses(cur realm, t *testing.T) {
	v := newTestImpl()
	sender := testAddress("batch-exact-sender")
	const channelId = types.ChannelId(92)
	orderA := batchRefundOrder("batch-exact-a", "ugnot", "quote-exact-a", 60)
	orderB := batchRefundOrder("batch-exact-b", "ugnot", "quote-exact-b", 40)
	batch := z.Batch{Instructions: []z.Instruction{
		batchMustOrderInstruction(orderA),
		batchMustOrderInstruction(orderB),
	}}
	f := newFunds(parseCoins("100ugnot"))

	err := v.verifyBatch(0, cur, channelId, sender, f, u256.Zero(), batch)
	uassert.NoError(t, err)
	uassert.NoError(t, f.assertEmpty())

	balanceA, _ := testStore.GetChannelBalanceV2(ChannelBalanceKeyV2(channelId, u256.Zero(), orderA.BaseToken, orderA.QuoteToken))
	uassert.Equal(t, "60", balanceA.ToString())
	balanceB, _ := testStore.GetChannelBalanceV2(ChannelBalanceKeyV2(channelId, u256.Zero(), orderB.BaseToken, orderB.QuoteToken))
	uassert.Equal(t, "40", balanceB.ToString())
}

func TestVerifyBatchDuplicateNativeConsumptionRejected(cur realm, t *testing.T) {
	v := newTestImpl()
	sender := testAddress("batch-dup-sender")
	batch := z.Batch{Instructions: []z.Instruction{
		batchMustOrderInstruction(batchRefundOrder("batch-dup-a", "ugnot", "quote-dup-a", 100)),
		batchMustOrderInstruction(batchRefundOrder("batch-dup-b", "ugnot", "quote-dup-b", 100)),
	}}

	err := v.verifyBatch(0, cur, types.ChannelId(91), sender, newFunds(parseCoins("100ugnot")), u256.Zero(), batch)

	uassert.ErrorContains(t, err, "sent coin mismatch")
}

func TestVerifyBatchLeftoverNativeRejected(cur realm, t *testing.T) {
	v := newTestImpl()
	sender := testAddress("batch-left-sender")
	batch := z.Batch{Instructions: []z.Instruction{
		batchMustOrderInstruction(batchRefundOrder("batch-left", "ugnot", "quote-leftover", 60)),
	}}
	f := newFunds(parseCoins("100ugnot"))

	err := v.verifyBatch(0, cur, types.ChannelId(93), sender, f, u256.Zero(), batch)
	uassert.NoError(t, err)
	// 40ugnot left unconsumed → the send-path drain check must reject it.
	uassert.ErrorContains(t, f.assertEmpty(), "sent coin mismatch")
}

func TestVerifyBatchMultiDenomExactPasses(cur realm, t *testing.T) {
	v := newTestImpl()
	sender := testAddress("batch-denom-sender")
	batch := z.Batch{Instructions: []z.Instruction{
		batchMustOrderInstruction(batchRefundOrder("batch-denom-a", "ugnot", "quote-denom-a", 100)),
		batchMustOrderInstruction(batchRefundOrder("batch-denom-b", "foo", "quote-denom-b", 50)),
	}}
	f := newFunds(parseCoins("100ugnot,50foo"))

	err := v.verifyBatch(0, cur, types.ChannelId(95), sender, f, u256.Zero(), batch)
	uassert.NoError(t, err)
	uassert.NoError(t, f.assertEmpty())
}

func TestVerifyBatchMultiDenomShortfallRejected(cur realm, t *testing.T) {
	v := newTestImpl()
	sender := testAddress("batch-short-sender")
	batch := z.Batch{Instructions: []z.Instruction{
		batchMustOrderInstruction(batchRefundOrder("batch-denom-sa", "ugnot", "quote-denom-sa", 100)),
		batchMustOrderInstruction(batchRefundOrder("batch-denom-sb", "foo", "quote-denom-sb", 50)),
	}}

	err := v.verifyBatch(0, cur, types.ChannelId(96), sender, newFunds(parseCoins("100ugnot,40foo")), u256.Zero(), batch)

	uassert.ErrorContains(t, err, "sent coin mismatch")
}

func TestVerifyBatchMixedNativeAndVoucher(cur realm, t *testing.T) {
	v := newTestImpl()
	sender := testAddress("batch-mixed-sender")
	voucherDenom := "ibc/batch-mixed"
	uassert.NoError(t, v.mintVoucher(0, cur, voucherDenom, [32]byte{}, "", "", 0, sender, u256.NewUint(20)))
	batch := z.Batch{Instructions: []z.Instruction{
		batchMustOrderInstruction(z.TokenOrderV2{
			Sender:      []byte(sender),
			BaseToken:   []byte(voucherDenom),
			BaseAmount:  u256.NewUint(7),
			QuoteToken:  []byte("quote-mixed-voucher"),
			QuoteAmount: u256.NewUint(7),
			Kind:        z.TOKEN_ORDER_KIND_ESCROW,
		}),
		batchMustOrderInstruction(batchRefundOrder("batch-mixed-native", "ugnot", "quote-mixed-native", 100)),
	}}
	f := newFunds(parseCoins("100ugnot"))

	err := v.verifyBatch(0, cur, types.ChannelId(94), sender, f, u256.Zero(), batch)
	uassert.NoError(t, err)
	uassert.NoError(t, f.assertEmpty())
	uassert.Equal(t, int64(13), voucherBalanceOf(voucherDenom, address(sender)))
}

func TestAcknowledgeBatchRejectsAckCountMismatch(cur realm, t *testing.T) {
	packet := core.NewPacket(types.ChannelId(7), types.ChannelId(8), nil, 0)
	batch := z.Batch{Instructions: []z.Instruction{
		batchMustCallInstruction(batchCall("sender", "first")),
		batchMustCallInstruction(batchCall("sender", "second")),
	}}

	err := newTestImpl().acknowledgeBatch(0, cur, packet, u256.Zero(), [32]byte{}, batch, mustBatchOuterAck([][]byte{mustSuccessAck()}))

	uassert.ErrorContains(t, err, "batch ack count mismatch")
}

func TestTimeoutBatchTokenOrderChildrenRefund(cur realm, t *testing.T) {
	v := newTestImpl()
	path := u256.NewUint(23)
	packet := core.NewPacket(types.ChannelId(7), types.ChannelId(8), nil, 0)
	orderA := batchRefundOrder("timeout-a", "ibc/batch-timeout-a", "quote-a", 11)
	orderB := batchRefundOrder("timeout-b", "ibc/batch-timeout-b", "quote-b", 17)
	v.increaseChannelBalanceV2(0, cur, types.ChannelId(7), path, orderA.BaseToken, orderA.QuoteToken, orderA.BaseAmount)
	v.increaseChannelBalanceV2(0, cur, types.ChannelId(7), path, orderB.BaseToken, orderB.QuoteToken, orderB.BaseAmount)
	batch := z.Batch{Instructions: []z.Instruction{
		batchMustOrderInstruction(orderA),
		batchMustOrderInstruction(orderB),
	}}

	err := v.timeoutBatch(0, cur, packet, path, [32]byte{}, batch)

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
	// absence is the canonical post-drain state (decreaseChannelBalanceV2 removes
	// the entry on zero); IsZero() defends against out-of-band zero writes.
	uassert.True(t, !ok || balance.IsZero())
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
