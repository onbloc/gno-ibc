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
	err := newTestImpl().verifyForward(0, cur, newFunds(nil), types.ChannelId(1), z.Forward{
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

	// verify reads the send-side sender from rlm.Previous(); it is driven via
	// SetRealm + the verifyForwardX crossing shim. A native ESCROW order keeps the
	// escrow a funds.sub (no realm-dependent voucher transfer), so the order child
	// can be verified at the unit level (voucher escrow is integration-tested).
	sender := testAddress("forward-sender")
	order := z.TokenOrderV2{
		Sender:      []byte(sender),
		BaseToken:   []byte("ugnot"),
		BaseAmount:  u256.NewUint(10),
		QuoteToken:  []byte("quote"),
		QuoteAmount: u256.NewUint(10),
		Kind:        z.TOKEN_ORDER_KIND_ESCROW,
	}
	batchBytes, err := z.EncodeBatch(z.Batch{Instructions: []z.Instruction{
		batchMustCallInstruction(batchCall(sender, "")),
	}})
	uassert.NoError(t, err)

	cases := []struct {
		instr z.Instruction
		funds *funds
	}{
		{batchMustCallInstruction(batchCall(sender, "")), newFunds(nil)},
		{batchMustOrderInstruction(order), newFunds(parseCoins("10ugnot"))},
		{z.Instruction{Version: z.INSTR_VERSION_0, Opcode: z.OP_BATCH, Operand: batchBytes}, newFunds(nil)},
	}
	for _, tc := range cases {
		testing.SetRealm(testing.NewUserRealm(address(sender)))
		err := v.verifyForwardX(cross(cur), tc.funds, types.ChannelId(1), z.Forward{
			Path:             forwardPath(1, 2),
			TimeoutTimestamp: 999,
			Instruction:      tc.instr,
		})
		uassert.NoError(t, err)
	}
}

func TestVerifyForwardRejectsZeroTimeout(cur realm, t *testing.T) {
	err := newTestImpl().verifyForward(0, cur, newFunds(nil), types.ChannelId(1), z.Forward{
		Path:             forwardPath(1, 2),
		TimeoutTimestamp: 0,
		Instruction:      batchMustCallInstruction(batchCall("sender", "")),
	})

	uassert.ErrorIs(t, err, makeError(errForwardZeroTimeout))
}

func TestVerifyForwardAllowsMaxHopPath(cur realm, t *testing.T) {
	sender := testAddress("fwd-maxhop-caller")
	testing.SetRealm(testing.NewUserRealm(address(sender)))
	err := newTestImpl().verifyForwardX(cross(cur), newFunds(nil), types.ChannelId(1), z.Forward{
		Path:             forwardPath(1, 2, 3, 4, 5, 6, 7, 8),
		TimeoutTimestamp: 999,
		Instruction:      batchMustCallInstruction(batchCall(sender, "")),
	})

	uassert.NoError(t, err)
}

func TestBuildForwardChildRejectsInvalidPath(cur realm, t *testing.T) {
	cases := []struct {
		name    string
		destCh  types.ChannelId
		path    *u256.Uint
		wantErr string
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
			uassert.ErrorIs(t, err, makeError(tc.wantErr))
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

	uassert.ErrorIs(t, err, makeError(errForwardZeroTimeout))
	uassert.Equal(t, uint32(0), uint32(child.SourceChannelId))
	uassert.True(t, len(child.Data) == 0)
}

func TestExecuteForwardIntentReturnsOnlyMaker(cur realm, t *testing.T) {
	res, err := newTestImpl().executeForward(0, cur, core.NewPacket(0, 0, nil, 0), [32]byte{}, u256.Zero(), z.Forward{
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

	uassert.AbortsContains(t, cur, "only maker", func(cur realm) {
		newTestImpl().OnIntentRecvPacket(0, cur, packet, address("g1relayer"), nil)
	})
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
