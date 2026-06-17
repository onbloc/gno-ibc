package cometbls

import (
	"bytes"
	"testing"

	"gno.land/p/aib/ibc/types"
	"gno.land/p/aib/ics23"
	"gno.land/p/onbloc/ibc/union/lightclient"
)

// nowNanos = 2024-01-01 00:00:00 UTC in nanoseconds.
const testNow = uint64(1_704_067_200) * 1_000_000_000

func TestWasmContractStoreKey(t *testing.T) {
	var contractAddress H256
	for i := 0; i < len(contractAddress); i++ {
		contractAddress[i] = byte(i)
	}
	key := []byte{0xAA, 0xBB}

	got := wasmContractStoreKey(contractAddress, key)
	want := append([]byte{0x03}, contractAddress[:]...)
	want = append(want, 0x00)
	want = append(want, key...)
	if !bytes.Equal(got, want) {
		t.Fatalf("wasmContractStoreKey: got %x want %x", got, want)
	}
}

func TestMembershipPath(t *testing.T) {
	var contractAddress H256
	for i := 0; i < len(contractAddress); i++ {
		contractAddress[i] = byte(i)
	}
	key := []byte{0xAA, 0xBB}
	cs := ClientState{ContractAddress: contractAddress}

	path := MembershipPath(cs, key)
	if len(path.KeyPath) != 2 {
		t.Fatalf("MembershipPath: got %d key segments want 2", len(path.KeyPath))
	}
	if !bytes.Equal(path.KeyPath[0], wasmdModuleStoreKey) {
		t.Fatalf("MembershipPath[0]: got %x want %x", path.KeyPath[0], wasmdModuleStoreKey)
	}
	if !bytes.Equal(path.KeyPath[1], wasmContractStoreKey(contractAddress, key)) {
		t.Fatalf("MembershipPath[1] mismatch")
	}
}

func baseCS() ClientState {
	return ClientState{
		TrustingPeriod: 14 * 24 * 3600 * 1_000_000_000, // 14 days in ns
		LatestHeight:   Height(100),
	}
}

// --- Status tests ---

func TestStatusActive(t *testing.T) {
	cs := baseCS()
	latest := ConsensusState{Timestamp: testNow - 1_000*1_000_000_000}
	if got := Status(cs, latest, testNow); got != lightclient.Active {
		t.Fatalf("got %q want %q", got, lightclient.Active)
	}
}

func TestStatusFrozen(t *testing.T) {
	cs := baseCS()
	cs.FrozenHeight = FrozenHeight
	latest := ConsensusState{Timestamp: testNow - 1_000*1_000_000_000}
	if got := Status(cs, latest, testNow); got != lightclient.Frozen {
		t.Fatalf("got %q want %q", got, lightclient.Frozen)
	}
}

func TestStatusExpiredNoConsensusState(t *testing.T) {
	cs := baseCS()
	if got := Status(cs, ConsensusState{}, testNow); got != lightclient.Expired {
		t.Fatalf("got %q want %q", got, lightclient.Expired)
	}
}

func TestStatusExpiredTrustingPeriod(t *testing.T) {
	cs := baseCS()
	latest := ConsensusState{Timestamp: testNow - cs.TrustingPeriod - 1}
	if got := Status(cs, latest, testNow); got != lightclient.Expired {
		t.Fatalf("got %q want %q", got, lightclient.Expired)
	}
}

func TestStatusFrozenTakesPrecedence(t *testing.T) {
	cs := baseCS()
	cs.FrozenHeight = FrozenHeight
	latest := ConsensusState{Timestamp: testNow - cs.TrustingPeriod - 1}
	if got := Status(cs, latest, testNow); got != lightclient.Frozen {
		t.Fatalf("got %q want %q", got, lightclient.Frozen)
	}
}

// --- ValidateInitialize tests ---

func TestValidateInitializeOK(t *testing.T) {
	cs := devnetClientState()
	cs.LatestHeight = Height(100)
	initial := ConsensusState{
		Timestamp:          testNow,
		NextValidatorsHash: devnetVH,
	}
	if err := ValidateInitialize(cs, initial); err != nil {
		t.Fatalf("ValidateInitialize: %v", err)
	}
}

func TestValidateInitializeEmptyChainID(t *testing.T) {
	cs := devnetClientState()
	cs.ChainID = ""
	if err := ValidateInitialize(cs, ConsensusState{Timestamp: testNow, NextValidatorsHash: devnetVH}); err == nil {
		t.Fatal("expected error for empty chain ID")
	}
}

func TestValidateInitializeZeroTrustingPeriod(t *testing.T) {
	cs := devnetClientState()
	cs.TrustingPeriod = 0
	if err := ValidateInitialize(cs, ConsensusState{Timestamp: testNow, NextValidatorsHash: devnetVH}); err == nil {
		t.Fatal("expected error for zero trusting period")
	}
}

func TestValidateInitializeZeroMaxClockDrift(t *testing.T) {
	cs := devnetClientState()
	cs.MaxClockDrift = 0
	if err := ValidateInitialize(cs, ConsensusState{Timestamp: testNow, NextValidatorsHash: devnetVH}); err == nil {
		t.Fatal("expected error for zero max clock drift")
	}
}

func TestValidateInitializeZeroLatestHeight(t *testing.T) {
	cs := devnetClientState()
	cs.LatestHeight = 0
	if err := ValidateInitialize(cs, ConsensusState{Timestamp: testNow, NextValidatorsHash: devnetVH}); err == nil {
		t.Fatal("expected error for zero latest height")
	}
}

func TestValidateInitializeZeroTimestamp(t *testing.T) {
	cs := devnetClientState()
	cs.LatestHeight = Height(100)
	if err := ValidateInitialize(cs, ConsensusState{NextValidatorsHash: devnetVH}); err == nil {
		t.Fatal("expected error for zero initial timestamp")
	}
}

// --- Header/consensus helpers ---

func TestConsensusStateFromHeader(t *testing.T) {
	h := devnetHeader()
	got := ConsensusStateFromHeader(h.SignedHeader)
	if got.Timestamp != h.SignedHeader.Nanos() {
		t.Fatalf("timestamp got %d want %d", got.Timestamp, h.SignedHeader.Nanos())
	}
	if !bytes.Equal(got.Root.Hash, h.SignedHeader.AppHash) {
		t.Fatalf("root got %x want %x", got.Root.Hash, h.SignedHeader.AppHash)
	}
	if got.NextValidatorsHash != h.SignedHeader.NextValidatorsHash {
		t.Fatalf("next validators hash got %x want %x", got.NextValidatorsHash, h.SignedHeader.NextValidatorsHash)
	}
}

func TestHeaderHeight(t *testing.T) {
	if got := HeaderHeight(devnetHeader()); got != Height(devnetHeight) {
		t.Fatalf("got %d want %d", got, Height(devnetHeight))
	}
}

func TestConsensusEqualsHeaderMatchingState(t *testing.T) {
	h := devnetHeader()
	if !ConsensusEqualsHeader(ConsensusStateFromHeader(h.SignedHeader), h.SignedHeader) {
		t.Fatal("expected consensus state to match header")
	}
}

func TestConsensusEqualsHeaderNoExistingState(t *testing.T) {
	if ConsensusEqualsHeader(ConsensusState{}, devnetHeader().SignedHeader) {
		t.Fatal("expected zero consensus state not to match header")
	}
}

func TestConsensusEqualsHeaderConflictingTimestamp(t *testing.T) {
	h := devnetHeader()
	cs := ConsensusStateFromHeader(h.SignedHeader)
	cs.Timestamp++
	if ConsensusEqualsHeader(cs, h.SignedHeader) {
		t.Fatal("expected timestamp mismatch")
	}
}

func TestConsensusEqualsHeaderConflictingAppHash(t *testing.T) {
	h := devnetHeader()
	cs := ConsensusStateFromHeader(h.SignedHeader)
	cs.Root.Hash = []byte{0xFF}
	if ConsensusEqualsHeader(cs, h.SignedHeader) {
		t.Fatal("expected app hash mismatch")
	}
}

// twoLevelPath returns a MerklePath with two segments (matching GetSDKProofSpecs length).
func twoLevelPath(store, key []byte) types.MerklePath {
	return types.MerklePath{KeyPath: [][]byte{store, key}}
}

// twoExistProofs returns a pair of existence proof stubs (invalid, for error-path tests).
func twoExistProofs() []ics23.CommitmentProof {
	return []ics23.CommitmentProof{
		ics23.CommitmentProof_Exist{Exist: &ics23.ExistenceProof{Key: []byte("k"), Value: []byte("v")}},
		ics23.CommitmentProof_Exist{Exist: &ics23.ExistenceProof{Key: []byte("k"), Value: []byte("v")}},
	}
}

// --- VerifyMembership tests ---

func TestVerifyMembershipEmptyValue(t *testing.T) {
	cs := ConsensusState{Timestamp: testNow, Root: MerkleRoot{Hash: []byte("root")}}
	if err := VerifyMembership(cs, twoExistProofs(), twoLevelPath([]byte("ibc"), []byte("key")), nil); err == nil {
		t.Fatal("expected error for empty value")
	}
}

func TestVerifyMembershipProofCountMismatch(t *testing.T) {
	cs := ConsensusState{Timestamp: testNow, Root: MerkleRoot{Hash: []byte("root")}}
	oneProof := []ics23.CommitmentProof{ics23.CommitmentProof_Exist{Exist: &ics23.ExistenceProof{}}}
	if err := VerifyMembership(cs, oneProof, twoLevelPath([]byte("ibc"), []byte("key")), []byte("v")); err == nil {
		t.Fatal("expected error for proof count mismatch")
	}
}

func TestVerifyMembershipPathCountMismatch(t *testing.T) {
	cs := ConsensusState{Timestamp: testNow, Root: MerkleRoot{Hash: []byte("root")}}
	onePath := types.MerklePath{KeyPath: [][]byte{[]byte("ibc")}}
	if err := VerifyMembership(cs, twoExistProofs(), onePath, []byte("v")); err == nil {
		t.Fatal("expected error for path length mismatch")
	}
}

func TestVerifyMembershipConsensusStateNotFound(t *testing.T) {
	if err := VerifyMembership(ConsensusState{}, twoExistProofs(), twoLevelPath([]byte("ibc"), []byte("key")), []byte("v")); err == nil {
		t.Fatal("expected error when consensus state not found")
	}
}

func TestVerifyMembershipEmptyRoot(t *testing.T) {
	cs := ConsensusState{Timestamp: testNow, Root: MerkleRoot{Hash: nil}}
	if err := VerifyMembership(cs, twoExistProofs(), twoLevelPath([]byte("ibc"), []byte("key")), []byte("v")); err == nil {
		t.Fatal("expected error for empty root hash")
	}
}

func TestVerifyMembershipProofFails(t *testing.T) {
	cs := ConsensusState{Timestamp: testNow, Root: MerkleRoot{Hash: []byte("root")}}
	if err := VerifyMembership(cs, twoExistProofs(), twoLevelPath([]byte("ibc"), []byte("key")), []byte("v")); err == nil {
		t.Fatal("expected error for invalid proof")
	}
}

// --- VerifyNonMembership tests ---

func TestVerifyNonMembershipProofCountMismatch(t *testing.T) {
	cs := ConsensusState{Timestamp: testNow, Root: MerkleRoot{Hash: []byte("root")}}
	oneProof := []ics23.CommitmentProof{ics23.CommitmentProof_Exist{Exist: &ics23.ExistenceProof{}}}
	if err := VerifyNonMembership(cs, oneProof, twoLevelPath([]byte("ibc"), []byte("key"))); err == nil {
		t.Fatal("expected error for proof count mismatch")
	}
}

func TestVerifyNonMembershipConsensusStateNotFound(t *testing.T) {
	proofs := []ics23.CommitmentProof{
		ics23.CommitmentProof_Nonexist{Nonexist: &ics23.NonExistenceProof{}},
		ics23.CommitmentProof_Exist{Exist: &ics23.ExistenceProof{}},
	}
	if err := VerifyNonMembership(ConsensusState{}, proofs, twoLevelPath([]byte("ibc"), []byte("key"))); err == nil {
		t.Fatal("expected error when consensus state not found")
	}
}

func TestVerifyNonMembershipEmptyRoot(t *testing.T) {
	cs := ConsensusState{Timestamp: testNow, Root: MerkleRoot{Hash: nil}}
	proofs := []ics23.CommitmentProof{
		ics23.CommitmentProof_Nonexist{Nonexist: &ics23.NonExistenceProof{}},
		ics23.CommitmentProof_Exist{Exist: &ics23.ExistenceProof{}},
	}
	if err := VerifyNonMembership(cs, proofs, twoLevelPath([]byte("ibc"), []byte("key"))); err == nil {
		t.Fatal("expected error for empty root hash")
	}
}

func TestVerifyNonMembershipFirstProofNotNonexist(t *testing.T) {
	cs := ConsensusState{Timestamp: testNow, Root: MerkleRoot{Hash: []byte("root")}}
	if err := VerifyNonMembership(cs, twoExistProofs(), twoLevelPath([]byte("ibc"), []byte("key"))); err == nil {
		t.Fatal("expected error when first proof is not a non-existence proof")
	}
}

func TestVerifyNonMembershipProofFails(t *testing.T) {
	cs := ConsensusState{Timestamp: testNow, Root: MerkleRoot{Hash: []byte("root")}}
	proofs := []ics23.CommitmentProof{
		ics23.CommitmentProof_Nonexist{Nonexist: &ics23.NonExistenceProof{}},
		ics23.CommitmentProof_Exist{Exist: &ics23.ExistenceProof{}},
	}
	if err := VerifyNonMembership(cs, proofs, twoLevelPath([]byte("ibc"), []byte("key"))); err == nil {
		t.Fatal("expected error for invalid non-existence proof")
	}
}
