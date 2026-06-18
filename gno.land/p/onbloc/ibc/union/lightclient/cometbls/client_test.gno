package cometbls

import (
	"testing"

	"gno.land/p/onbloc/ibc/union/lightclient"
	"gno.land/p/onbloc/ibc/union/types"
)

// newTestClient builds a CometblsLightClient with a single consensus state at
// height 100 and a zero owner address.
func newTestClient(t *testing.T) *CometblsLightClient {
	t.Helper()
	cs := validClientState()
	consensus := &ConsensusState{
		Timestamp:          testNow,
		Root:               MerkleRoot{Hash: repeat32(0xAB)},
		NextValidatorsHash: repeat32(0xCD),
	}
	c, err := NewCometblsLightClient(&cs, consensus)
	if err != nil {
		t.Fatalf("NewCometblsLightClient: %v", err)
	}
	return c
}

func TestClientAccessors(t *testing.T) {
	c := newTestClient(t)

	if c.GetLatestHeight() != 100 {
		t.Errorf("GetLatestHeight: got %d want 100", c.GetLatestHeight())
	}
	if c.GetCounterpartyChainID() != "test-chain" {
		t.Errorf("GetCounterpartyChainID: got %q want test-chain", c.GetCounterpartyChainID())
	}
	if c.GetTimestamp() != types.Timestamp(testNow) {
		t.Errorf("GetTimestamp: got %d want %d", c.GetTimestamp(), testNow)
	}
}

func TestClientGetTimestampNoConsensus(t *testing.T) {
	c := newTestClient(t)
	// Move latest height to one with no consensus state.
	c.clientState.LatestHeight = types.NewHeight(999)
	if c.GetTimestamp() != 0 {
		t.Errorf("GetTimestamp: got %d want 0", c.GetTimestamp())
	}
}

func TestClientStatusFrozen(t *testing.T) {
	c := newTestClient(t)
	c.clientState.FrozenHeight = FrozenHeight
	if got := c.Status(); got != lightclient.Frozen {
		t.Errorf("Status: got %q want %q", got, lightclient.Frozen)
	}
}

func TestClientStatusExpiredNoConsensus(t *testing.T) {
	c := newTestClient(t)
	// No consensus state at the latest height => expired.
	c.clientState.LatestHeight = types.NewHeight(999)
	if got := c.Status(); got != lightclient.Expired {
		t.Errorf("Status: got %q want %q", got, lightclient.Expired)
	}
}

func TestClientStatusExpiredTrustingPeriod(t *testing.T) {
	// Union reference: cometbls status returns Expired when the latest
	// consensus state exists but is older than the trusting period.
	c := newTestClient(t)
	c.clientState.TrustingPeriod = 1
	c.setConsensusState(c.clientState.LatestHeight, &ConsensusState{
		Timestamp:          1,
		Root:               MerkleRoot{Hash: repeat32(0xAB)},
		NextValidatorsHash: repeat32(0xCD),
	})

	if got := c.Status(); got != lightclient.Expired {
		t.Errorf("Status: got %q want %q", got, lightclient.Expired)
	}
}

func TestClientStatusActive(t *testing.T) {
	// Union reference: cometbls status returns Active when the client is not
	// frozen, has latest consensus state, and the trusting period has not
	// expired.
	c := newTestClient(t)
	c.clientState.TrustingPeriod = 1_000_000_000_000_000_000

	if got := c.Status(); got != lightclient.Active {
		t.Errorf("Status: got %q want %q", got, lightclient.Active)
	}
}

func TestVerifyCreationEmpty(t *testing.T) {
	// Union reference: cometbls verify_creation returns ClientCreationResult::new().
	c := newTestClient(t)
	var caller, relayer address
	res, err := c.VerifyCreation(caller, relayer)
	if err != nil {
		t.Fatalf("VerifyCreation: %v", err)
	}
	if len(res.ClientStateBytes) != 0 {
		t.Fatal("VerifyCreation must not return client state bytes")
	}
}

// twoExistProof returns a MerkleProof wire buffer containing two existence
// commitment proofs (matching GetSDKProofSpecs length of 2).
func twoExistProof() []byte {
	ep1 := encodeExistenceProof([]byte("k1"), []byte("v1"), nil, nil)
	ep2 := encodeExistenceProof([]byte("k2"), []byte("v2"), nil, nil)
	return encodeMerkleProof(encodeCommitmentExist(ep1), encodeCommitmentExist(ep2))
}

// --- VerifyMembership error paths (no valid crypto required) ---

func TestVerifyMembershipEmptyValue(t *testing.T) {
	c := newTestClient(t)
	if err := c.VerifyMembership(100, []byte("key"), twoExistProof(), nil); err == nil {
		t.Fatal("expected error for empty value")
	}
}

func TestVerifyMembershipHeightTooHigh(t *testing.T) {
	c := newTestClient(t)
	if err := c.VerifyMembership(200, []byte("key"), twoExistProof(), []byte("v")); err == nil {
		t.Fatal("expected error for height above latest")
	}
}

func TestVerifyMembershipBadProof(t *testing.T) {
	c := newTestClient(t)
	if err := c.VerifyMembership(100, []byte("key"), []byte{0x0a, 0xff}, []byte("v")); err == nil {
		t.Fatal("expected error for undecodable proof")
	}
}

func TestVerifyMembershipProofCountMismatch(t *testing.T) {
	c := newTestClient(t)
	ep := encodeExistenceProof([]byte("k"), []byte("v"), nil, nil)
	oneProof := encodeMerkleProof(encodeCommitmentExist(ep))
	if err := c.VerifyMembership(100, []byte("key"), oneProof, []byte("v")); err == nil {
		t.Fatal("expected error for proof count != specs")
	}
}

func TestVerifyMembershipConsensusNotFound(t *testing.T) {
	c := newTestClient(t)
	// Height 50 <= latest 100, but no consensus state was stored there.
	if err := c.VerifyMembership(50, []byte("key"), twoExistProof(), []byte("v")); err == nil {
		t.Fatal("expected error when consensus state not found")
	}
}

// --- VerifyNonMembership error paths ---

func TestVerifyNonMembershipConsensusNotFound(t *testing.T) {
	c := newTestClient(t)
	nep := encodeNonExistenceProof([]byte("k"), nil, nil)
	ep := encodeExistenceProof([]byte("k"), []byte("v"), nil, nil)
	buf := encodeMerkleProof(encodeCommitmentNonexist(nep), encodeCommitmentExist(ep))
	if err := c.VerifyNonMembership(50, []byte("key"), buf); err == nil {
		t.Fatal("expected error when consensus state not found")
	}
}

func TestVerifyNonMembershipFirstProofNotNonexist(t *testing.T) {
	c := newTestClient(t)
	// Consensus exists at 100, two proofs, but the first is an existence proof.
	if err := c.VerifyNonMembership(100, []byte("key"), twoExistProof()); err == nil {
		t.Fatal("expected error when first proof is not a non-existence proof")
	}
}

func TestVerifyNonMembershipProofCountMismatch(t *testing.T) {
	c := newTestClient(t)
	nep := encodeNonExistenceProof([]byte("k"), nil, nil)
	oneProof := encodeMerkleProof(encodeCommitmentNonexist(nep))
	if err := c.VerifyNonMembership(100, []byte("key"), oneProof); err == nil {
		t.Fatal("expected error for proof count != specs")
	}
}
