package impl

import (
	"testing"

	types "gno.land/p/onbloc/ibc/union/types"

	"gno.land/p/nt/uassert/v0"
	z "gno.land/p/onbloc/ibc/union/zkgm"
)

// TestUnionVerifyForward ports the union ucs03-zkgm verify_forward unit tests:
// an allowed inner instruction verifies, an unsupported inner version is
// rejected, and a nested FORWARD inner instruction is rejected.
//
// Note: union's fixtures set timeout_timestamp=0 (relying on timeout_height);
// the gno impl additionally requires a non-zero timeout_timestamp, so the
// fixtures here use 1. The zero-timeout rejection itself is covered in
// forward_test.gno (TestVerifyForwardRejectsZeroTimeout).
// reference: https://github.com/unionlabs/union/blob/d91c5e94354e15801bd5f82dc658eae3b79f2dad/cosmwasm/app/ucs03-zkgm/src/tests.rs#L334-L454
func TestUnionVerifyForward(cur realm, t *testing.T) {
	v := newTestImpl()
	const sender = "sender"
	// update_channel_path(update_channel_path(0, 10), 1)
	path := forwardPath(10, 1)
	callOperand := mustCallBytes(z.Call{Sender: []byte(sender), ContractAddress: []byte(sender)})

	cases := []struct {
		name    string
		forward z.Forward
		wantErr string
	}{
		{
			name: "allowed inner call ok",
			forward: z.Forward{
				Path:             path,
				TimeoutTimestamp: 1,
				Instruction:      z.Instruction{Version: z.INSTR_VERSION_0, Opcode: z.OP_CALL, Operand: callOperand},
			},
		},
		{
			name: "unsupported inner version rejected",
			forward: z.Forward{
				Path:             path,
				TimeoutTimestamp: 1,
				Instruction:      z.Instruction{Version: z.INSTR_VERSION_1, Opcode: z.OP_CALL, Operand: callOperand},
			},
			wantErr: "unsupported call version",
		},
		{
			name: "nested forward instruction rejected",
			forward: z.Forward{
				Path:             path,
				TimeoutTimestamp: 1,
				Instruction:      z.Instruction{Version: z.INSTR_VERSION_0, Opcode: z.OP_FORWARD},
			},
			wantErr: "invalid forward instruction",
		},
	}

	for _, tc := range cases {
		err := v.verifyForward(0, cur, MessageInfo{Sender: sender}, newFunds(nil), types.ChannelId(1), tc.forward)
		if tc.wantErr == "" {
			uassert.NoError(t, err)
		} else {
			uassert.ErrorContains(t, err, tc.wantErr)
		}
	}
}
