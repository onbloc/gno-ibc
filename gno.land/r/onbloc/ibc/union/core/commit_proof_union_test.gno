package core

import (
	"testing"

	"gno.land/p/nt/uassert/v0"
	"gno.land/p/onbloc/ibc/union/types"
)

// Union implementation reference:
// https://github.com/unionlabs/union/blob/d91c5e94354e15801bd5f82dc658eae3b79f2dad/cosmwasm/core/src/contract.rs#L2259-L2297
// Query reference:
// https://github.com/unionlabs/union/blob/d91c5e94354e15801bd5f82dc658eae3b79f2dad/cosmwasm/core/src/contract.rs#L2176-L2191
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

// Union implementation reference:
// https://github.com/unionlabs/union/blob/d91c5e94354e15801bd5f82dc658eae3b79f2dad/cosmwasm/core/src/contract.rs#L2267-L2289
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

// Union implementation reference:
// https://github.com/unionlabs/union/blob/d91c5e94354e15801bd5f82dc658eae3b79f2dad/cosmwasm/core/src/contract.rs#L2176-L2191
func TestGetCommittedMembershipProofUnknownReturnsEmpty(cur realm, t *testing.T) {
	resetStore()

	if got := GetCommittedMembershipProof(types.ClientId(1), 10, types.Bytes("path")); got != "" {
		t.Fatalf("GetCommittedMembershipProof unknown: got %q want empty", got)
	}
}

// Union implementation reference:
// https://github.com/unionlabs/union/blob/d91c5e94354e15801bd5f82dc658eae3b79f2dad/cosmwasm/core/src/contract.rs#L2181-L2189
func TestGetCommittedMembershipProofUsesClientHeightAndPath(cur realm, t *testing.T) {
	resetStore()
	clientId := types.ClientId(7)
	path := types.Bytes("clients/7/consensusStates/11")
	value := types.Keccak(types.Bytes("consensus-state"))
	store.saveMembershipProof(clientId, 10, path, value)

	if got := GetCommittedMembershipProof(clientId, 10, path); got != value.String() {
		t.Fatalf("GetCommittedMembershipProof exact key: got %q want %s", got, value)
	}
	if got := GetCommittedMembershipProof(types.ClientId(8), 10, path); got != "" {
		t.Fatalf("GetCommittedMembershipProof wrong client: got %q want empty", got)
	}
	if got := GetCommittedMembershipProof(clientId, 11, path); got != "" {
		t.Fatalf("GetCommittedMembershipProof wrong height: got %q want empty", got)
	}
	if got := GetCommittedMembershipProof(clientId, 10, types.Bytes("other-path")); got != "" {
		t.Fatalf("GetCommittedMembershipProof wrong path: got %q want empty", got)
	}
}

// Union implementation reference:
// https://github.com/unionlabs/union/blob/d91c5e94354e15801bd5f82dc658eae3b79f2dad/cosmwasm/core/src/contract.rs#L2300-L2336
// Query reference:
// https://github.com/unionlabs/union/blob/d91c5e94354e15801bd5f82dc658eae3b79f2dad/cosmwasm/core/src/contract.rs#L2192-L2213
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

// Union implementation reference:
// https://github.com/unionlabs/union/blob/d91c5e94354e15801bd5f82dc658eae3b79f2dad/cosmwasm/core/src/contract.rs#L2307-L2328
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

// Union implementation reference:
// https://github.com/unionlabs/union/blob/d91c5e94354e15801bd5f82dc658eae3b79f2dad/cosmwasm/core/src/contract.rs#L2192-L2213
func TestGetCommittedNonMembershipProofUnknownReturnsFalse(cur realm, t *testing.T) {
	resetStore()

	if GetCommittedNonMembershipProof(types.ClientId(1), 10, types.Bytes("path")) {
		t.Fatal("GetCommittedNonMembershipProof unknown: got true want false")
	}
}

// Union implementation reference:
// https://github.com/unionlabs/union/blob/d91c5e94354e15801bd5f82dc658eae3b79f2dad/cosmwasm/core/src/contract.rs#L2197-L2210
func TestGetCommittedNonMembershipProofUsesClientHeightAndPath(cur realm, t *testing.T) {
	resetStore()
	clientId := types.ClientId(7)
	path := types.Bytes("clients/7/consensusStates/11")
	store.saveNonMembershipProof(clientId, 10, path, types.NON_MEMBERSHIP_COMMITMENT_VALUE)

	if !GetCommittedNonMembershipProof(clientId, 10, path) {
		t.Fatal("GetCommittedNonMembershipProof exact key: got false want true")
	}
	if GetCommittedNonMembershipProof(types.ClientId(8), 10, path) {
		t.Fatal("GetCommittedNonMembershipProof wrong client: got true want false")
	}
	if GetCommittedNonMembershipProof(clientId, 11, path) {
		t.Fatal("GetCommittedNonMembershipProof wrong height: got true want false")
	}
	if GetCommittedNonMembershipProof(clientId, 10, types.Bytes("other-path")) {
		t.Fatal("GetCommittedNonMembershipProof wrong path: got true want false")
	}
}
