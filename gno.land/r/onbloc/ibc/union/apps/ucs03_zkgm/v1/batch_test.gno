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

func TestIsAllowedBatchInstruction(t *testing.T) {
	cases := []struct {
		name string
		op   uint8
		want bool
	}{
		{"call", z.OP_CALL, true},
		{"token order", z.OP_TOKEN_ORDER, true},
		{"batch", z.OP_BATCH, false},
		{"forward", z.OP_FORWARD, false},
		{"unknown", 0xFF, false},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			uassert.Equal(t, tc.want, isAllowedBatchInstruction(tc.op))
		})
	}
}

func TestVerifyBatch(cur realm, t *testing.T) {
	callSender := testAddress("batch-call-caller")
	exactOrderA := batchRefundOrder("batch-exact-a", "ugnot", "quote-exact-a", 60)
	exactOrderB := batchRefundOrder("batch-exact-b", "ugnot", "quote-exact-b", 40)

	type channelBalance struct {
		channelId types.ChannelId
		order     z.TokenOrderV2
		want      string
	}

	cases := []struct {
		name          string
		previous      string
		channelId     types.ChannelId
		sent          string
		batch         z.Batch
		wantVerifyErr string
		wantDrainErr  string
		wantBalances  []channelBalance
	}{
		{
			name:      "rejects nested batch",
			channelId: types.ChannelId(1),
			batch: z.Batch{Instructions: []z.Instruction{{
				Version: z.INSTR_VERSION_0,
				Opcode:  z.OP_BATCH,
			}}},
			wantVerifyErr: "invalid batch instruction",
		},
		{
			name:      "passes allowed call children",
			previous:  callSender,
			channelId: types.ChannelId(1),
			batch: z.Batch{Instructions: []z.Instruction{
				batchMustCallInstruction(batchCall(callSender, "a")),
				batchMustCallInstruction(batchCall(callSender, "b")),
			}},
		},
		{
			name:      "exact total native consumption passes",
			channelId: types.ChannelId(92),
			sent:      "100ugnot",
			batch: z.Batch{Instructions: []z.Instruction{
				batchMustOrderInstruction(exactOrderA),
				batchMustOrderInstruction(exactOrderB),
			}},
			wantBalances: []channelBalance{
				{types.ChannelId(92), exactOrderA, "60"},
				{types.ChannelId(92), exactOrderB, "40"},
			},
		},
		{
			name:      "duplicate native consumption rejected",
			channelId: types.ChannelId(91),
			sent:      "100ugnot",
			batch: z.Batch{Instructions: []z.Instruction{
				batchMustOrderInstruction(batchRefundOrder("batch-dup-a", "ugnot", "quote-dup-a", 100)),
				batchMustOrderInstruction(batchRefundOrder("batch-dup-b", "ugnot", "quote-dup-b", 100)),
			}},
			wantVerifyErr: "sent coin mismatch",
		},
		{
			name:      "leftover native rejected by drain check",
			channelId: types.ChannelId(93),
			sent:      "100ugnot",
			batch: z.Batch{Instructions: []z.Instruction{
				batchMustOrderInstruction(batchRefundOrder("batch-left", "ugnot", "quote-leftover", 60)),
			}},
			wantDrainErr: "sent coin mismatch",
		},
		{
			name:      "multi denom exact passes",
			channelId: types.ChannelId(95),
			sent:      "100ugnot,50foo",
			batch: z.Batch{Instructions: []z.Instruction{
				batchMustOrderInstruction(batchRefundOrder("batch-denom-a", "ugnot", "quote-denom-a", 100)),
				batchMustOrderInstruction(batchRefundOrder("batch-denom-b", "foo", "quote-denom-b", 50)),
			}},
		},
		{
			name:      "multi denom shortfall rejected",
			channelId: types.ChannelId(96),
			sent:      "100ugnot,40foo",
			batch: z.Batch{Instructions: []z.Instruction{
				batchMustOrderInstruction(batchRefundOrder("batch-denom-sa", "ugnot", "quote-denom-sa", 100)),
				batchMustOrderInstruction(batchRefundOrder("batch-denom-sb", "foo", "quote-denom-sb", 50)),
			}},
			wantVerifyErr: "sent coin mismatch",
		},
	}

	for _, tc := range cases {
		testStore = newMockStore()
		if tc.previous != "" {
			testing.SetRealm(testing.NewUserRealm(address(tc.previous)))
		}
		v := newTestImpl()
		f := newFunds(parseCoins(tc.sent))

		err := v.verifyBatchX(cross(cur), f, tc.channelId, u256.Zero(), tc.batch)
		if tc.wantVerifyErr != "" {
			uassert.ErrorContains(t, err, tc.wantVerifyErr)
			continue
		}
		uassert.NoError(t, err)

		if tc.wantDrainErr != "" {
			uassert.ErrorContains(t, f.assertEmpty(), tc.wantDrainErr)
		} else {
			uassert.NoError(t, f.assertEmpty())
		}

		for _, want := range tc.wantBalances {
			balance, ok := testStore.GetChannelBalanceV2(ChannelBalanceKeyV2(want.channelId, u256.Zero(), want.order.BaseToken, want.order.QuoteToken))
			uassert.True(t, ok)
			uassert.Equal(t, want.want, balance.ToString())
		}
	}
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

func TestAcknowledgeBatch(cur realm, t *testing.T) {
	type refundExpectation struct {
		order   z.TokenOrderV2
		balance int64
	}

	cases := []struct {
		name    string
		refund  bool
		wantErr string
	}{
		{"rejects ack count mismatch", false, "batch ack count mismatch"},
		{"failure refunds token order children", true, ""},
	}

	for _, tc := range cases {
		testStore = newMockStore()
		v := newTestImpl()
		packet := core.NewPacket(types.ChannelId(7), types.ChannelId(8), nil, 0)
		path := u256.Zero()
		relayer := address("")
		successful := true
		ack := mustBatchOuterAck([][]byte{mustSuccessAck()}).InnerAck
		batch := z.Batch{Instructions: []z.Instruction{
			batchMustCallInstruction(batchCall("sender", "first")),
			batchMustCallInstruction(batchCall("sender", "second")),
		}}
		refunds := []refundExpectation{}

		if tc.refund {
			path = u256.NewUint(29)
			relayer = address(testAddress("relayer"))
			successful = false
			ack = nil

			orderA := batchRefundOrder("ack-fail-a", "ibc/batch-ack-fail-a", "quote-a", 11)
			orderB := batchRefundOrder("ack-fail-b", "ibc/batch-ack-fail-b", "quote-b", 17)
			v.increaseChannelBalanceV2(0, cur, types.ChannelId(7), path, orderA.BaseToken, orderA.QuoteToken, orderA.BaseAmount)
			v.increaseChannelBalanceV2(0, cur, types.ChannelId(7), path, orderB.BaseToken, orderB.QuoteToken, orderB.BaseAmount)
			uassert.NoError(t, v.mintVoucher(0, cur, string(orderA.BaseToken), [32]byte{}, "", "", 0, cur.Address().String(), orderA.BaseAmount))
			uassert.NoError(t, v.mintVoucher(0, cur, string(orderB.BaseToken), [32]byte{}, "", "", 0, cur.Address().String(), orderB.BaseAmount))

			batch = z.Batch{Instructions: []z.Instruction{
				batchMustOrderInstruction(orderA),
				batchMustOrderInstruction(orderB),
			}}
			refunds = []refundExpectation{
				{orderA, 11},
				{orderB, 17},
			}
		}

		err := v.acknowledgeBatch(0, cur, packet, relayer, [32]byte{}, path, batch, successful, ack)
		if tc.wantErr != "" {
			uassert.ErrorContains(t, err, tc.wantErr)
			continue
		}
		uassert.NoError(t, err)

		for _, want := range refunds {
			assertNoChannelBalance(t, types.ChannelId(7), path, want.order)
			uassert.Equal(t, want.balance, voucherBalanceOf(string(want.order.BaseToken), address(want.order.Sender)))
		}
	}
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
