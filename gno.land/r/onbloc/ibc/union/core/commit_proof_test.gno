package core

import (
	"testing"

	"gno.land/p/nt/uassert/v0"
	"gno.land/p/onbloc/ibc/union/types"
)

func setCommitProofAdmin(cur realm) {
	admin = cur.Address()
	resetAccess(cur, admin)
}

// Gno equivalent of Union RestrictedExecuteMsg access management.
func TestCommitMembershipProofRejectsNonAdminBeforeVerification(cur realm, t *testing.T) {
	resetStore(cur)
	previousRole := denySelectorForTest(cur, SelectorCommitMembershipProof)
	client := &mockClient{chainId: "union-1", status: types.StatusActive}
	clientId := registerMockClient(client)

	uassert.AbortsContains(t, cur, "unauthorized", func(cur realm) {
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
	restoreSelectorForTest(cur, SelectorCommitMembershipProof, previousRole)
}
