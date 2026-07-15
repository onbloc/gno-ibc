package ucs03_zkgm

// forward_test.gno tests the validation and dispatch logic in forward.gno,
// including instruction allow-listing, buildForwardChild validation,
// market-maker intent short-circuiting, and ack refund routing.
//
// Asynchronous dispatch and core-frame receive handling are covered by the e2e
// suite.

import (
	"bytes"
	"testing"

	types "gno.land/p/onbloc/ibc/union/types"

	u256 "gno.land/p/gnoswap/uint256"
	"gno.land/p/nt/uassert/v0"
	z "gno.land/p/onbloc/ibc/union/zkgm"
	core "gno.land/r/onbloc/ibc/union/core"
)

func TestForwardInFlightKey(t *testing.T) {
	cases := []struct {
		name        string
		packet      types.Packet
		compareWith types.Packet
		wantEqual   bool
	}{
		{
			name:        "same packet produces same key",
			packet:      core.NewPacket(types.ChannelId(1), types.ChannelId(2), []byte("data"), 99),
			compareWith: core.NewPacket(types.ChannelId(1), types.ChannelId(2), []byte("data"), 99),
			wantEqual:   true,
		},
		{
			name:        "different dest channel produces different key",
			packet:      core.NewPacket(types.ChannelId(1), types.ChannelId(2), []byte("data"), 99),
			compareWith: core.NewPacket(types.ChannelId(1), types.ChannelId(3), []byte("data"), 99),
			wantEqual:   false,
		},
		{
			name:        "empty data produces deterministic key",
			packet:      core.NewPacket(types.ChannelId(1), types.ChannelId(2), []byte{}, 0),
			compareWith: core.NewPacket(types.ChannelId(1), types.ChannelId(2), []byte{}, 0),
			wantEqual:   true,
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			key1 := forwardInFlightKey(tc.packet)
			key2 := forwardInFlightKey(tc.compareWith)
			if tc.wantEqual {
				uassert.Equal(t, key1, key2)
			} else {
				uassert.NotEqual(t, key1, key2)
			}
		})
	}
}

func TestIsAllowedForwardInstruction(t *testing.T) {
	cases := []struct {
		name string
		op   uint8
		want bool
	}{
		{"call", z.OP_CALL, true},
		{"token order", z.OP_TOKEN_ORDER, true},
		{"batch", z.OP_BATCH, true},
		{"forward", z.OP_FORWARD, false},
		{"unknown", 0xFF, false},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			uassert.Equal(t, tc.want, isAllowedForwardInstruction(tc.op))
		})
	}
}

func TestVerifyForward(cur realm, t *testing.T) {
	v := newTestImpl()
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
		name             string
		forward          z.Forward
		channelId        types.ChannelId
		funds            *funds
		setSender        bool
		wantErr          string
	}{
		{
			name: "passes call child",
			forward: z.Forward{
				Path:             forwardPath(1, 2),
				TimeoutTimestamp: 999,
				Instruction:      batchMustCallInstruction(batchCall(sender, "")),
			},
			channelId: types.ChannelId(1),
			funds:     newFunds(nil),
			setSender: true,
			wantErr:   "",
		},
		{
			name: "passes token order child",
			forward: z.Forward{
				Path:             forwardPath(1, 2),
				TimeoutTimestamp: 999,
				Instruction:      batchMustOrderInstruction(order),
			},
			channelId: types.ChannelId(1),
			funds:     newFunds(parseCoins("10ugnot")),
			setSender: true,
			wantErr:   "",
		},
		{
			name: "passes batch child",
			forward: z.Forward{
				Path:             forwardPath(1, 2),
				TimeoutTimestamp: 999,
				Instruction:      z.Instruction{Version: z.INSTR_VERSION_0, Opcode: z.OP_BATCH, Operand: batchBytes},
			},
			channelId: types.ChannelId(1),
			funds:     newFunds(nil),
			setSender: true,
			wantErr:   "",
		},
		{
			name: "passes max hop path",
			forward: z.Forward{
				Path:             forwardPath(1, 2, 3, 4, 5, 6, 7, 8),
				TimeoutTimestamp: 999,
				Instruction:      batchMustCallInstruction(batchCall(sender, "")),
			},
			channelId: types.ChannelId(1),
			funds:     newFunds(nil),
			setSender: true,
			wantErr:   "",
		},
		{
			name: "rejects nested forward",
			forward: z.Forward{
				Path: forwardPath(1, 2),
				Instruction: z.Instruction{
					Version: z.INSTR_VERSION_0,
					Opcode:  z.OP_FORWARD,
					Operand: mustForwardBytes(z.Forward{Path: forwardPath(1, 2)}),
				},
			},
			channelId: types.ChannelId(1),
			funds:     newFunds(nil),
			wantErr:   "invalid forward instruction",
		},
		{
			name: "rejects zero timeout",
			forward: z.Forward{
				Path:             forwardPath(1, 2),
				TimeoutTimestamp: 0,
				Instruction:      batchMustCallInstruction(batchCall("sender", "")),
			},
			channelId: types.ChannelId(1),
			funds:     newFunds(nil),
			wantErr:   errForwardZeroTimeout,
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(cur realm, t *testing.T) {
			if tc.setSender {
				testing.SetRealm(testing.NewUserRealm(address(sender)))
			}
			var err error
			if tc.setSender {
				err = v.verifyForwardX(cross(cur), tc.funds, tc.channelId, tc.forward)
			} else {
				err = v.verifyForward(0, cur, tc.funds, tc.channelId, tc.forward)
			}
			if tc.wantErr != "" {
				uassert.ErrorContains(t, err, tc.wantErr)
				return
			}
			uassert.NoError(t, err)
		})
	}
}

func TestBuildForwardChild(cur realm, t *testing.T) {
	cases := []struct {
		name             string
		parent           types.Packet
		path             *u256.Uint
		timeoutTimestamp uint64
		wantErr          string
	}{
		{
			name:             "missing prev dest",
			parent:           core.NewPacket(types.ChannelId(0), types.ChannelId(1), nil, 0),
			path:             u256.Zero(),
			timeoutTimestamp: 999,
			wantErr:          errForwardMissingPrevDest,
		},
		{
			name:             "missing next source",
			parent:           core.NewPacket(types.ChannelId(0), types.ChannelId(5), nil, 0),
			path:             forwardPath(5),
			timeoutTimestamp: 999,
			wantErr:          errForwardMissingNextSource,
		},
		{
			name:             "prev dest mismatch",
			parent:           core.NewPacket(types.ChannelId(0), types.ChannelId(7), nil, 0),
			path:             forwardPath(5, 99),
			timeoutTimestamp: 999,
			wantErr:          errForwardPrevDestMismatch,
		},
		{
			name:             "zero timeout",
			parent:           core.NewPacket(types.ChannelId(0), types.ChannelId(1), nil, 0),
			path:             forwardPath(1, 2),
			timeoutTimestamp: 0,
			wantErr:          errForwardZeroTimeout,
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			child, err := buildForwardChild(tc.parent, u256.Zero(), [32]byte{}, z.Forward{
				Path:             tc.path,
				TimeoutTimestamp: tc.timeoutTimestamp,
				Instruction:      batchMustCallInstruction(batchCall("sender", "")),
			})
			uassert.ErrorIs(t, err, makeError(tc.wantErr))
			uassert.Equal(t, uint32(0), uint32(child.SourceChannelId))
			uassert.True(t, len(child.Data) == 0)
		})
	}
}

func TestExecuteForward(cur realm, t *testing.T) {
	v := newTestImpl()
	packet := core.NewPacket(types.ChannelId(7), types.ChannelId(8), nil, 0)

	cases := []struct {
		name             string
		forward          z.Forward
		intent           bool
		wantStatus       types.PacketStatus
		wantOnlyMaker    bool
		wantErr          string
		assertions       func()
	}{
		{
			name: "intent returns only-maker ack",
			forward: z.Forward{
				Path:        forwardPath(1, 2),
				Instruction: batchMustCallInstruction(batchCall("sender", "")),
			},
			intent:        true,
			wantStatus:    types.PacketStatusSuccess,
			wantOnlyMaker: true,
		},
		{
			name: "invalid instruction returns error",
			forward: z.Forward{
				Path:        forwardPath(1, 2),
				Instruction: z.Instruction{Version: z.INSTR_VERSION_0, Opcode: z.OP_FORWARD},
			},
			wantStatus: types.PacketStatusUnknown,
			wantErr:    "invalid forward instruction",
		},
		{
			name: "buildForwardChild zero timeout propagates error",
			forward: z.Forward{
				Path:             forwardPath(1, 2),
				TimeoutTimestamp: 0,
				Instruction:      batchMustCallInstruction(batchCall("sender", "")),
			},
			wantStatus: types.PacketStatusUnknown,
			wantErr:    errForwardZeroTimeout,
		},
		{
			name: "buildForwardChild invalid path propagates error",
			forward: z.Forward{
				Path:             u256.Zero(),
				TimeoutTimestamp: 999,
				Instruction:      batchMustCallInstruction(batchCall("sender", "")),
			},
			wantStatus: types.PacketStatusUnknown,
			wantErr:    errForwardMissingPrevDest,
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			res, err := v.executeForward(0, cur, packet, [32]byte{}, u256.Zero(), tc.forward, tc.intent)

			if tc.wantErr != "" {
				uassert.ErrorContains(t, err, tc.wantErr)
				uassert.True(t, res.Status == tc.wantStatus)
				return
			}

			uassert.NoError(t, err)
			uassert.True(t, res.Status == tc.wantStatus)

			if tc.wantOnlyMaker {
				uassert.True(t, bytes.Equal(z.ACK_ERR_ONLY_MAKER, res.Acknowledgement))
			}

			if tc.assertions != nil {
				tc.assertions()
			}
		})
	}
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

func TestHandleForwardChild_NoopsWhenPacketIsNotResolvable(cur realm, t *testing.T) {
	testStore = newMockStore()
	v := newTestImpl()
	parent := core.NewPacket(types.ChannelId(1), types.ChannelId(2), []byte("parent"), 0)
	child := core.NewPacket(types.ChannelId(3), types.ChannelId(4), []byte("child"), 0)
	childKey := forwardInFlightKey(child)

	cases := []struct {
		name string
		zp   z.ZkgmPacket
		seed bool
	}{
		{
			name: "plain salt ignores stored key",
			zp:   z.ZkgmPacket{Salt: [32]byte{0x01}},
			seed: true,
		},
		{
			name: "forward salt without stored parent",
			zp:   z.ZkgmPacket{Salt: z.DeriveForwardSalt([32]byte{0x02})},
			seed: false,
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			testStore.RemoveInFlightPacket(0, cur, childKey)
			if tc.seed {
				testStore.SetInFlightPacket(0, cur, childKey, parent)
			}

			ok := v.handleForwardChild(0, cur, child, tc.zp, []byte("ack"))

			uassert.False(t, ok)
			_, found := testStore.GetInFlightPacket(childKey)
			uassert.Equal(t, tc.seed, found)
		})
	}
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
