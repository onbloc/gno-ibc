package core

import (
	"testing"

	"gno.land/p/nt/uassert/v0"
	"gno.land/p/onbloc/ibc/union/types"
)

// Gno equivalent of Union RestrictedExecuteMsg access management.
func TestCommitMembershipProofRejectsNonAdminBeforeVerification(cur realm, t *testing.T) {
	resetStore(cur)
	previousRole := denySelectorForTest(cur, SelectorCommitMembershipProof)
	defer restoreSelectorForTest(cur, SelectorCommitMembershipProof, previousRole)

	client := &mockClient{chainId: "union-1", status: types.StatusActive}
	clientId := registerMockClient(client)

	uassert.AbortsContains(t, cur, accessManagerUnauthorizedCallError, func(cur realm) {
		CommitMembershipProof(cross(cur), types.MsgCommitMembershipProof{
			ClientId:    clientId,
			ProofHeight: 10,
			Proof:       types.Bytes("proof"),
			Path:        types.Bytes("path"),
			Value:       types.Bytes("value"),
		})
	})

	if len(client.membershipKeys) != 0 {
		t.Fatalf("membership calls: got %d want 0", len(client.membershipKeys))
	}
}
