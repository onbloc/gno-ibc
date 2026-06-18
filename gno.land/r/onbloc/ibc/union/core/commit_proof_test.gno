package core

import (
	"testing"

	"gno.land/p/nt/testutils/v0"
	"gno.land/p/nt/uassert/v0"
	"gno.land/p/onbloc/ibc/union/types"
)

func setCommitProofAdmin(cur realm) {
	admin = cur.Address()
}

func TestCommitMembershipProofStoresCommittedValue(cur realm, t *testing.T) {
	resetStore()
	oldAdmin := admin
	defer func() { admin = oldAdmin }()
	setCommitProofAdmin(cur)

	client := &mockClient{chainId: "union-1", status: types.StatusActive}
	clientId := registerMockClient(client)
	path := types.Bytes("clients/7/consensusStates/11")
	value := types.Bytes("consensus-state")
	proof := types.Bytes("membership-proof")

	CommitMembershipProof(cross(cur), types.MsgCommitMembershipProof{
		ClientId:    clientId,
		ProofHeight: 10,
		Proof:       proof,
		Path:        path,
		Value:       value,
	})

	if len(client.membershipKeys) != 1 {
		t.Fatalf("membership calls: got %d want 1", len(client.membershipKeys))
	}
	if client.membershipHeights[0] != types.NewHeight(10) ||
		string(client.membershipProofs[0]) != string(proof) ||
		string(client.membershipKeys[0]) != string(path) ||
		string(client.membershipValues[0]) != string(value) {
		t.Fatal("CommitMembershipProof must pass proof height, path, proof, and value through")
	}
	if got := GetCommittedMembershipProof(clientId, 10, path); got != types.Keccak(value).String() {
		t.Fatalf("committed membership proof: got %q want %s", got, types.Keccak(value))
	}
}

func TestCommitMembershipProofRejectsNonAdminBeforeVerification(cur realm, t *testing.T) {
	resetStore()
	oldAdmin := admin
	defer func() { admin = oldAdmin }()
	admin = testutils.TestAddress("different-admin")
	client := &mockClient{chainId: "union-1", status: types.StatusActive}
	clientId := registerMockClient(client)

	uassert.AbortsContains(t, cur, "unauthorized", func(cur realm) {
		CommitMembershipProof(cur, types.MsgCommitMembershipProof{
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

func TestCommitMembershipProofRejectsInactiveClientBeforeVerification(cur realm, t *testing.T) {
	resetStore()
	oldAdmin := admin
	defer func() { admin = oldAdmin }()
	setCommitProofAdmin(cur)
	client := &mockClient{chainId: "union-1", status: types.StatusFrozen}
	clientId := registerMockClient(client)

	uassert.AbortsContains(t, cur, "client is not active", func(cur realm) {
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
	if got := GetCommittedMembershipProof(clientId, 10, types.Bytes("path")); got != "" {
		t.Fatalf("inactive client must not commit membership proof; got %q", got)
	}
}

func TestCommitNonMembershipProofStoresSentinel(cur realm, t *testing.T) {
	resetStore()
	oldAdmin := admin
	defer func() { admin = oldAdmin }()
	setCommitProofAdmin(cur)

	client := &mockClient{chainId: "union-1", status: types.StatusActive}
	clientId := registerMockClient(client)
	path := types.Bytes("clients/7/consensusStates/11")
	proof := types.Bytes("non-membership-proof")

	CommitNonMembershipProof(cross(cur), types.MsgCommitNonMembershipProof{
		ClientId:    clientId,
		ProofHeight: 10,
		Proof:       proof,
		Path:        path,
	})

	if len(client.nonMembershipKeys) != 1 {
		t.Fatalf("non-membership calls: got %d want 1", len(client.nonMembershipKeys))
	}
	if client.nonMembershipHeights[0] != types.NewHeight(10) ||
		string(client.nonMembershipProofs[0]) != string(proof) ||
		string(client.nonMembershipKeys[0]) != string(path) {
		t.Fatal("CommitNonMembershipProof must pass proof height, path, and proof through")
	}
	if !GetCommittedNonMembershipProof(clientId, 10, path) {
		t.Fatal("CommitNonMembershipProof must store the non-membership sentinel")
	}
}

func TestCommitNonMembershipProofRejectsInactiveClientBeforeVerification(cur realm, t *testing.T) {
	resetStore()
	oldAdmin := admin
	defer func() { admin = oldAdmin }()
	setCommitProofAdmin(cur)
	client := &mockClient{chainId: "union-1", status: types.StatusExpired}
	clientId := registerMockClient(client)

	uassert.AbortsContains(t, cur, "client is not active", func(cur realm) {
		CommitNonMembershipProof(cross(cur), types.MsgCommitNonMembershipProof{
			ClientId:    clientId,
			ProofHeight: 10,
			Proof:       types.Bytes("proof"),
			Path:        types.Bytes("path"),
		})
	})

	if len(client.nonMembershipKeys) != 0 {
		t.Fatalf("non-membership calls: got %d want 0", len(client.nonMembershipKeys))
	}
	if GetCommittedNonMembershipProof(clientId, 10, types.Bytes("path")) {
		t.Fatal("inactive client must not commit non-membership proof")
	}
}
