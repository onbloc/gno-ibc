package ucs03_zkgm

import (
	"testing"

	u256 "gno.land/p/gnoswap/uint256"
	"gno.land/p/nt/uassert/v0"

	"gno.land/p/onbloc/ibc/union/types"
	z "gno.land/p/onbloc/ibc/union/zkgm"
)

// TestUnionVerifyBatch ports the union ucs03-zkgm verify_batch unit tests: a
// batch of allowed children (a CALL whose sender matches) verifies; a batch
// containing a nested BATCH child is rejected as an invalid batch instruction.
// reference: https://github.com/unionlabs/union/blob/d91c5e94354e15801bd5f82dc658eae3b79f2dad/cosmwasm/app/ucs03-zkgm/src/tests.rs#L486-L543
func TestUnionVerifyBatch(cur realm, t *testing.T) {
	v := newTestImpl()
	// verify reads the sender from rlm.Previous(); drive it via SetRealm + the
	// verifyBatchX crossing shim.
	sender := testAddress("union-vb-caller")

	cases := []struct {
		name    string
		batch   z.Batch
		wantErr string // empty = expect Ok
	}{
		{
			name: "single allowed call child ok",
			batch: z.Batch{Instructions: []z.Instruction{
				batchMustCallInstruction(z.Call{Sender: []byte(sender), ContractAddress: []byte("contract")}),
			}},
		},
		{
			name: "nested batch child rejected",
			batch: z.Batch{Instructions: []z.Instruction{
				{Version: z.INSTR_VERSION_0, Opcode: z.OP_BATCH},
			}},
			wantErr: "invalid batch instruction",
		},
	}

	for _, tc := range cases {
		testing.SetRealm(testing.NewUserRealm(address(sender)))
		err := v.verifyBatchX(cross(cur), newFunds(nil), types.ChannelId(1), u256.Zero(), tc.batch)
		if tc.wantErr == "" {
			uassert.NoError(t, err)
		} else {
			uassert.ErrorContains(t, err, tc.wantErr)
		}
	}
}
