package impl

// forward_test.gno covers forward.gno's pure validation and dispatch logic:
// instruction allow-listing, path/timeout validation in buildForwardChild, the
// market-maker intent short-circuit, and ack refund routing. The async dispatch
// (BatchSend + in-flight tracking) and the core-frame receive flow are
// integration paths exercised in the e2e suite.

import (
	"bytes"
	"testing"

	types "gno.land/p/onbloc/ibc/union/types"

	u256 "gno.land/p/gnoswap/uint256"
	"gno.land/p/nt/uassert/v0"
	z "gno.land/p/onbloc/ibc/union/zkgm"
	core "gno.land/r/onbloc/ibc/union/core"
)

func TestVerifyForwardRejectsNestedForward(cur realm, t *testing.T) {
	err := newTestImpl().verifyForward(0, cur, types.ChannelId(1), "sender", newFunds(nil), u256.Zero(), z.Forward{
		Path: forwardPath(1, 2),
		Instruction: z.Instruction{
			Version: z.INSTR_VERSION_0,
			Opcode:  z.OP_FORWARD,
			Operand: mustForwardBytes(z.Forward{Path: forwardPath(1, 2)}),
		},
	})

	uassert.ErrorContains(t, err, "invalid forward instruction")
}

func TestVerifyForwardPassesAllowedChildren(cur realm, t *testing.T) {
	v := newTestImpl()

	sender := testAddress("forward-sender")
	baseToken := "ibc/v1-forward"
	uassert.NoError(t, v.mintVoucher(0, cur, baseToken, [32]byte{}, "", "", 0, sender, u256.NewUint(30)))
	order := z.TokenOrderV2{
		Sender:      []byte(sender),
		BaseToken:   []byte(baseToken),
		BaseAmount:  u256.NewUint(10),
		QuoteToken:  []byte("quote"),
		QuoteAmount: u256.NewUint(10),
		Kind:        z.TOKEN_ORDER_KIND_ESCROW,
	}
	batchBytes, err := z.EncodeBatch(z.Batch{Instructions: []z.Instruction{
		batchMustCallInstruction(batchCall(sender, "")),
	}})
	uassert.NoError(t, err)

	cases := []z.Instruction{
		batchMustCallInstruction(batchCall(sender, "")),
		batchMustOrderInstruction(order),
		{Version: z.INSTR_VERSION_0, Opcode: z.OP_BATCH, Operand: batchBytes},
	}
	for _, instr := range cases {
		err := v.verifyForward(0, cur, types.ChannelId(1), sender, newFunds(nil), u256.Zero(), z.Forward{
			Path:             forwardPath(1, 2),
			TimeoutTimestamp: 999,
			Instruction:      instr,
		})
		uassert.NoError(t, err)
	}
}

func TestVerifyForwardRejectsZeroTimeout(cur realm, t *testing.T) {
	err := newTestImpl().verifyForward(0, cur, types.ChannelId(1), "sender", newFunds(nil), u256.Zero(), z.Forward{
		Path:             forwardPath(1, 2),
		TimeoutTimestamp: 0,
		Instruction:      batchMustCallInstruction(batchCall("sender", "")),
	})

	uassert.True(t, err == errForwardZeroTimeout)
}

func TestVerifyForwardAllowsMaxHopPath(cur realm, t *testing.T) {
	err := newTestImpl().verifyForward(0, cur, types.ChannelId(1), "sender", newFunds(nil), u256.Zero(), z.Forward{
		Path:             forwardPath(1, 2, 3, 4, 5, 6, 7, 8),
		TimeoutTimestamp: 999,
		Instruction:      batchMustCallInstruction(batchCall("sender", "")),
	})

	uassert.NoError(t, err)
}

func TestBuildForwardChildRejectsInvalidPath(cur realm, t *testing.T) {
	cases := []struct {
		name    string
		destCh  types.ChannelId
		path    *u256.Uint
		wantErr error
	}{
		{"missing prev dest", types.ChannelId(1), u256.Zero(), errForwardMissingPrevDest},
		{"missing next source", types.ChannelId(5), forwardPath(5), errForwardMissingNextSource},
		{"prev dest mismatch", types.ChannelId(7), forwardPath(5, 99), errForwardPrevDestMismatch},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			parent := core.NewPacket(types.ChannelId(0), tc.destCh, nil, 0)
			_, err := buildForwardChild(parent, u256.Zero(), [32]byte{}, z.Forward{
				Path:             tc.path,
				TimeoutTimestamp: 999,
				Instruction:      batchMustCallInstruction(batchCall("sender", "")),
			})
			uassert.True(t, err == tc.wantErr)
		})
	}
}

func TestBuildForwardChildRejectsZeroTimeout(cur realm, t *testing.T) {
	parent := core.NewPacket(types.ChannelId(0), types.ChannelId(1), nil, 0)

	child, err := buildForwardChild(parent, u256.NewUint(9), [32]byte{0xA}, z.Forward{
		Path:             forwardPath(1, 2),
		TimeoutTimestamp: 0,
		Instruction:      batchMustCallInstruction(batchCall("sender", "call")),
	})

	uassert.True(t, err == errForwardZeroTimeout)
	uassert.Equal(t, uint32(0), uint32(child.SourceChannelId))
	uassert.True(t, len(child.Data) == 0)
}

func TestExecuteForwardIntentReturnsOnlyMaker(cur realm, t *testing.T) {
	res, err := newTestImpl().executeForward(0, cur, core.NewPacket(0, 0, nil, 0), u256.Zero(), [32]byte{}, z.Forward{
		Path:        forwardPath(1, 2),
		Instruction: batchMustCallInstruction(batchCall("sender", "")),
	}, true)

	uassert.NoError(t, err)
	uassert.True(t, res.Status == types.PacketStatusSuccess)
	uassert.True(t, bytes.Equal(z.ACK_ERR_ONLY_MAKER, res.Acknowledgement))
}

func TestIntentRecvOnlyMakerForwardAborts(cur realm, t *testing.T) {
	data := mustZkgmPacketBytes(z.Instruction{
		Version: z.INSTR_VERSION_0,
		Opcode:  z.OP_FORWARD,
		Operand: mustForwardBytes(z.Forward{
			Path:        forwardPath(1, 2),
			Instruction: batchMustCallInstruction(batchCall("sender", "")),
		}),
	})
	packet := core.NewPacket(types.ChannelId(7), types.ChannelId(8), data, 0)

	uassert.AbortsContains(t, cur, "zkgm: only maker", func(cur realm) {
		newTestImpl().OnIntentRecvPacket(0, cur, packet, address("g1relayer"), nil)
	})
}

func TestAcknowledgeForwardDispatchesToInnerInstruction(cur realm, t *testing.T) {
	err := newTestImpl().acknowledgeForward(0, cur, core.NewPacket(0, 0, nil, 0), u256.Zero(), [32]byte{}, z.Forward{
		Path:        forwardPath(1, 2),
		Instruction: batchMustCallInstruction(batchCall("sender", "calldata")),
	}, z.Ack{Tag: tagAckSuccess(), InnerAck: []byte{}})

	uassert.NoError(t, err)
}

func TestAcknowledgeForwardWithTokenOrderChildRefundsOnFailure(cur realm, t *testing.T) {
	v := newTestImpl()

	sender := testAddress("forward-refund")
	order := z.TokenOrderV2{
		Sender:      []byte(sender),
		BaseToken:   []byte("ibc/v1-forward-refund"),
		BaseAmount:  u256.NewUint(20),
		QuoteToken:  []byte("quote"),
		QuoteAmount: u256.NewUint(20),
		Kind:        z.TOKEN_ORDER_KIND_ESCROW,
	}
	path := forwardPath(1, 2)
	v.increaseChannelBalanceV2(0, cur, types.ChannelId(3), path, order.BaseToken, order.QuoteToken, order.BaseAmount)
	childFailAck, err := z.EncodeAck(z.Ack{Tag: tagAckFailure(), InnerAck: []byte("failed")})
	uassert.NoError(t, err)

	err = v.acknowledgeForward(0, cur, core.NewPacket(types.ChannelId(3), types.ChannelId(4), nil, 0), u256.Zero(), [32]byte{}, z.Forward{
		Path:        path,
		Instruction: batchMustOrderInstruction(order),
	}, z.Ack{Tag: tagAckSuccess(), InnerAck: childFailAck})

	uassert.NoError(t, err)

	balance, ok := testStore.GetChannelBalanceV2(ChannelBalanceKeyV2(types.ChannelId(3), path, order.BaseToken, order.QuoteToken))
	uassert.True(t, ok && balance.IsZero())
	uassert.Equal(t, int64(20), voucherBalanceOf(string(order.BaseToken), address(sender)))
}

func forwardPath(channels ...uint32) *u256.Uint {
	path := u256.Zero()
	for _, channel := range channels {
		var err error
		path, err = z.UpdateChannelPath(path, channel)
		if err != nil {
			panic(err)
		}
	}
	return path
}
