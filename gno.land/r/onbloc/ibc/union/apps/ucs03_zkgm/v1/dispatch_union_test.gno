package impl

import (
	"testing"

	types "gno.land/p/onbloc/ibc/union/types"

	u256 "gno.land/p/gnoswap/uint256"
	"gno.land/p/nt/uassert/v0"
	z "gno.land/p/onbloc/ibc/union/zkgm"
)

// TestUnionVerifyInternal ports the union ucs03-zkgm verify_internal unit tests:
// an instruction with an unsupported version and one with an unknown opcode are
// both rejected during verification.
//
// Note: union returns generic UnsupportedVersion/UnknownOpcode errors. The gno
// dispatcher decodes per opcode first, so an unsupported version on a CALL
// surfaces as the call-specific version error; the reject outcome is the same.
// reference: https://github.com/unionlabs/union/blob/d91c5e94354e15801bd5f82dc658eae3b79f2dad/cosmwasm/app/ucs03-zkgm/src/tests.rs#L545-L599
func TestUnionVerifyInternal(cur realm, t *testing.T) {
	v := newTestImpl()

	cases := []struct {
		name    string
		instr   z.Instruction
		wantErr string
	}{
		{
			name:    "unsupported version",
			instr:   z.Instruction{Version: 99, Opcode: z.OP_CALL},
			wantErr: "unsupported call version",
		},
		{
			name:    "unknown opcode",
			instr:   z.Instruction{Version: z.INSTR_VERSION_0, Opcode: 99},
			wantErr: "unsupported opcode",
		},
	}

	for _, tc := range cases {
		err := v.verifyInternal(0, cur, newFunds(nil), types.ChannelId(1), u256.Zero(), tc.instr)
		uassert.ErrorContains(t, err, tc.wantErr)
	}
}
