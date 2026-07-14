package v1

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

	// The verify path reads the sender from rlm.Previous() (MessageInfo removed),
	// so the caller is driven through testing.SetRealm + the verifyCallX crossing
	// shim. A matching call sender passes; any mismatch is rejected.
	caller := testAddress("union-vc-caller")

	cases := []struct {
		name    string
		call    z.Call
		wantErr string // empty = expect Ok
	}{
		{
			name: "matching sender ok",
			call: z.Call{Sender: []byte(caller), ContractAddress: []byte("contract")},
		},
		{
			name:    "wrong sender rejected",
			call:    z.Call{Sender: []byte("wrong_sender"), ContractAddress: []byte("contract")},
			wantErr: "invalid call sender",
		},
	}

	for _, tc := range cases {
		testing.SetRealm(testing.NewUserRealm(address(caller)))
		err := v.verifyCallX(cross(cur), tc.call)
		if tc.wantErr == "" {
			uassert.NoError(t, err)
		} else {
			uassert.ErrorContains(t, err, tc.wantErr)
		}
	}
}
