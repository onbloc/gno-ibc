package core

import (
	"testing"

	"gno.land/p/onbloc/ibc/union/types"
)

type committedProofGetterImpl struct {
	ICore
}

func (i *committedProofGetterImpl) GetCommittedMembershipProofCommitment(clientId types.ClientId, proofHeight uint64, path []byte) (types.H256, error) {
	commitment, ok := store.MembershipProofAt(clientId, proofHeight, path)
	if !ok {
		return types.H256{}, makeError(ErrMembershipProofNotFound)
	}

	return commitment, nil
}

func (i *committedProofGetterImpl) GetCommittedNonMembershipProof(clientId types.ClientId, proofHeight uint64, path []byte) bool {
	return store.HasNonMembershipProof(clientId, proofHeight, path)
}

func resetCommittedProofGetterTest(cur realm) {
	resetStore(cur)
	currentImpl = &committedProofGetterImpl{}
}

// Union implementation reference:
// https://github.com/unionlabs/union/blob/d91c5e94354e15801bd5f82dc658eae3b79f2dad/cosmwasm/core/src/contract.rs#L2176-L2191
func TestGetCommittedMembershipProofUnknownReturnsError(cur realm, t *testing.T) {
	resetCommittedProofGetterTest(cur)

	_, err := GetCommittedMembershipProof(types.ClientId(1), 10, types.Bytes("path"))
	if err == nil || err.Error() != ErrMembershipProofNotFound {
		t.Fatalf("GetCommittedMembershipProof unknown error: got %v want %q", err, ErrMembershipProofNotFound)
	}
}

// Union implementation reference:
// https://github.com/unionlabs/union/blob/d91c5e94354e15801bd5f82dc658eae3b79f2dad/cosmwasm/core/src/contract.rs#L2181-L2189
func TestGetCommittedMembershipProofUsesClientHeightAndPath(cur realm, t *testing.T) {
	resetCommittedProofGetterTest(cur)
	clientId := types.ClientId(7)
	path := types.Bytes("clients/7/consensusStates/11")
	value := types.Keccak(types.Bytes("consensus-state"))
	store.SaveMembershipProof(0, cur, clientId, 10, path, value)

	got, err := GetCommittedMembershipProof(clientId, 10, path)
	if err != nil {
		t.Fatalf("GetCommittedMembershipProof exact key error: %v", err)
	}
	if got != value {
		t.Fatalf("GetCommittedMembershipProof exact key: got %s want %s", got, value)
	}
	if _, err := GetCommittedMembershipProof(types.ClientId(8), 10, path); err == nil || err.Error() != ErrMembershipProofNotFound {
		t.Fatalf("GetCommittedMembershipProof wrong client error: got %v want %q", err, ErrMembershipProofNotFound)
	}
	if _, err := GetCommittedMembershipProof(clientId, 11, path); err == nil || err.Error() != ErrMembershipProofNotFound {
		t.Fatalf("GetCommittedMembershipProof wrong height error: got %v want %q", err, ErrMembershipProofNotFound)
	}
	if _, err := GetCommittedMembershipProof(clientId, 10, types.Bytes("other-path")); err == nil || err.Error() != ErrMembershipProofNotFound {
		t.Fatalf("GetCommittedMembershipProof wrong path error: got %v want %q", err, ErrMembershipProofNotFound)
	}
}

// Union implementation reference:
// https://github.com/unionlabs/union/blob/d91c5e94354e15801bd5f82dc658eae3b79f2dad/cosmwasm/core/src/contract.rs#L2192-L2213
func TestGetCommittedNonMembershipProofUnknownReturnsFalse(cur realm, t *testing.T) {
	resetCommittedProofGetterTest(cur)

	if GetCommittedNonMembershipProof(types.ClientId(1), 10, types.Bytes("path")) {
		t.Fatal("GetCommittedNonMembershipProof unknown: got true want false")
	}
}

// Union implementation reference:
// https://github.com/unionlabs/union/blob/d91c5e94354e15801bd5f82dc658eae3b79f2dad/cosmwasm/core/src/contract.rs#L2197-L2210
func TestGetCommittedNonMembershipProofUsesClientHeightAndPath(cur realm, t *testing.T) {
	resetCommittedProofGetterTest(cur)
	clientId := types.ClientId(7)
	path := types.Bytes("clients/7/consensusStates/11")
	store.SaveNonMembershipProof(0, cur, clientId, 10, path, types.NON_MEMBERSHIP_COMMITMENT_VALUE)

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
