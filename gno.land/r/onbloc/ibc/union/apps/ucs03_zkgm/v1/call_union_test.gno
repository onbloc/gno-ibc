package impl

import (
	"testing"

	"gno.land/p/nt/uassert/v0"
	z "gno.land/p/onbloc/ibc/union/zkgm"
)

// TestUnionVerifyCall ports the union ucs03-zkgm verify_call unit tests: a call
// whose Sender equals the dispatch sender passes; any mismatch is rejected.
// reference: https://github.com/unionlabs/union/blob/d91c5e94354e15801bd5f82dc658eae3b79f2dad/cosmwasm/app/ucs03-zkgm/src/tests.rs#L456-L484
func TestUnionVerifyCall(cur realm, t *testing.T) {
	v := newTestImpl()

	cases := []struct {
		name    string
		sender  string
		call    z.Call
		wantErr string // empty = expect Ok
	}{
		{
			name:   "matching sender ok",
			sender: "sender",
			call:   z.Call{Sender: []byte("sender"), ContractAddress: []byte("contract")},
		},
		{
			name:    "wrong sender rejected",
			sender:  "wrong_sender",
			call:    z.Call{Sender: []byte("sender"), ContractAddress: []byte("contract")},
			wantErr: "invalid call sender",
		},
	}

	for _, tc := range cases {
		err := v.verifyCall(0, cur, tc.call, tc.sender)
		if tc.wantErr == "" {
			uassert.NoError(t, err)
		} else {
			uassert.ErrorContains(t, err, tc.wantErr)
		}
	}
}
