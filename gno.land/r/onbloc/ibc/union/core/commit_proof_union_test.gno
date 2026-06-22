package core

import (
	"testing"

	"gno.land/p/onbloc/ibc/union/types"
)

// Union implementation reference:
// https://github.com/unionlabs/union/blob/d91c5e94354e15801bd5f82dc658eae3b79f2dad/cosmwasm/core/src/contract.rs#L2176-L2191
func TestGetCommittedMembershipProofUnknownReturnsEmpty(cur realm, t *testing.T) {
	resetStore(cur)

	if got := GetCommittedMembershipProof(types.ClientId(1), 10, types.Bytes("path")); got != "" {
		t.Fatalf("GetCommittedMembershipProof unknown: got %q want empty", got)
	}
}

// Union implementation reference:
// https://github.com/unionlabs/union/blob/d91c5e94354e15801bd5f82dc658eae3b79f2dad/cosmwasm/core/src/contract.rs#L2181-L2189
func TestGetCommittedMembershipProofUsesClientHeightAndPath(cur realm, t *testing.T) {
	resetStore(cur)
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
// https://github.com/unionlabs/union/blob/d91c5e94354e15801bd5f82dc658eae3b79f2dad/cosmwasm/core/src/contract.rs#L2192-L2213
func TestGetCommittedNonMembershipProofUnknownReturnsFalse(cur realm, t *testing.T) {
	resetStore(cur)

	if GetCommittedNonMembershipProof(types.ClientId(1), 10, types.Bytes("path")) {
		t.Fatal("GetCommittedNonMembershipProof unknown: got true want false")
	}
}

// Union implementation reference:
// https://github.com/unionlabs/union/blob/d91c5e94354e15801bd5f82dc658eae3b79f2dad/cosmwasm/core/src/contract.rs#L2197-L2210
func TestGetCommittedNonMembershipProofUsesClientHeightAndPath(cur realm, t *testing.T) {
	resetStore(cur)
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
