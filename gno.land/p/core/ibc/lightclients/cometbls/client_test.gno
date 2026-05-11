package cometbls

import (
	"testing"

	"gno.land/p/aib/ics23"
	"gno.land/p/aib/ibc/types"
)

// nowNanos = 2024-01-01 00:00:00 UTC in nanoseconds.
const testNow = uint64(1_704_067_200) * 1_000_000_000

func newTestClient(cs ClientState, states map[Height]ConsensusState) *CometBLSClient {
	c := New(
		func(h Height) (ConsensusState, bool) {
			s, ok := states[h]
			return s, ok
		},
		func(h Height, s ConsensusState) {
			states[h] = s
		},
	)
	c.cs = cs
	return c
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
	states := map[Height]ConsensusState{
		cs.LatestHeight: {Timestamp: testNow - 1_000*1_000_000_000}, // 1000s ago
	}
	if got := newTestClient(cs, states).Status(testNow); got != StatusActive {
		t.Fatalf("got %q want %q", got, StatusActive)
	}
}

func TestStatusFrozen(t *testing.T) {
	cs := baseCS()
	cs.FrozenHeight = FrozenHeight
	states := map[Height]ConsensusState{
		cs.LatestHeight: {Timestamp: testNow - 1_000*1_000_000_000},
	}
	if got := newTestClient(cs, states).Status(testNow); got != StatusFrozen {
		t.Fatalf("got %q want %q", got, StatusFrozen)
	}
}

func TestStatusExpiredNoConsensusState(t *testing.T) {
	cs := baseCS()
	if got := newTestClient(cs, map[Height]ConsensusState{}).Status(testNow); got != StatusExpired {
		t.Fatalf("got %q want %q", got, StatusExpired)
	}
}

func TestStatusExpiredTrustingPeriod(t *testing.T) {
	cs := baseCS()
	states := map[Height]ConsensusState{
		cs.LatestHeight: {Timestamp: testNow - cs.TrustingPeriod - 1},
	}
	if got := newTestClient(cs, states).Status(testNow); got != StatusExpired {
		t.Fatalf("got %q want %q", got, StatusExpired)
	}
}

func TestStatusFrozenTakesPrecedence(t *testing.T) {
	cs := baseCS()
	cs.FrozenHeight = FrozenHeight
	states := map[Height]ConsensusState{
		cs.LatestHeight: {Timestamp: testNow - cs.TrustingPeriod - 1},
	}
	if got := newTestClient(cs, states).Status(testNow); got != StatusFrozen {
		t.Fatalf("got %q want %q", got, StatusFrozen)
	}
}

// --- VerifyClientMessage dispatch tests ---

func TestVerifyClientMessageEmptyMessage(t *testing.T) {
	cs := baseCS()
	client := newTestClient(cs, map[Height]ConsensusState{})
	err := client.VerifyClientMessage(ClientMessage{}, testNow)
	if err == nil {
		t.Fatal("expected error for empty client message")
	}
}

func TestVerifyClientMessageTrustedNotFound(t *testing.T) {
	cs := baseCS()
	client := newTestClient(cs, map[Height]ConsensusState{})
	msg := NewHeaderMessage(devnetHeader())
	if err := client.VerifyClientMessage(msg, devnetNow()); err == nil {
		t.Fatal("expected error when trusted consensus state not found")
	}
}

func TestVerifyClientMessageHeaderOK(t *testing.T) {
	cs := ClientState{
		ChainID:        devnetChainID,
		TrustingPeriod: 14 * 24 * 3600 * 1_000_000_000,
		MaxClockDrift:  10 * 1_000_000_000,
		LatestHeight:   Height(devnetHeight - 1),
	}
	states := map[Height]ConsensusState{
		cs.LatestHeight: devnetTrusted(),
	}
	client := newTestClient(cs, states)
	msg := NewHeaderMessage(devnetHeader())
	if err := client.VerifyClientMessage(msg, devnetNow()); err != nil {
		t.Fatalf("VerifyClientMessage: %v", err)
	}
}

// --- CheckForMisbehaviour tests ---

func TestCheckForMisbehaviourMisbehaviourMsg(t *testing.T) {
	// A Misbehaviour message always indicates misbehaviour (VerifyClientMessage already passed).
	client := newTestClient(devnetClientState(), devnetStates())
	msg := NewMisbehaviourMessage(Misbehaviour{HeaderA: devnetHeader(), HeaderB: devnetHeader()})
	if !client.CheckForMisbehaviour(msg) {
		t.Fatal("expected misbehaviour for Misbehaviour message")
	}
}

func TestCheckForMisbehaviourNoExistingState(t *testing.T) {
	// Header with no existing consensus state at that height — not misbehaviour.
	client := newTestClient(devnetClientState(), devnetStates())
	if client.CheckForMisbehaviour(NewHeaderMessage(devnetHeader())) {
		t.Fatal("expected no misbehaviour when no existing consensus state at header height")
	}
}

func TestCheckForMisbehaviourMatchingState(t *testing.T) {
	h := devnetHeader()
	lh := h.SignedHeader
	hHeight := Height(lh.Height)
	states := map[Height]ConsensusState{
		h.TrustedHeight: devnetTrusted(),
		hHeight: {
			Timestamp:          lh.Nanos(),
			NextValidatorsHash: lh.NextValidatorsHash,
			Root:               MerkleRoot{Hash: lh.AppHash},
		},
	}
	client := newTestClient(devnetClientState(), states)
	if client.CheckForMisbehaviour(NewHeaderMessage(h)) {
		t.Fatal("expected no misbehaviour when existing consensus state matches header")
	}
}

func TestCheckForMisbehaviourConflictingTimestamp(t *testing.T) {
	h := devnetHeader()
	lh := h.SignedHeader
	hHeight := Height(lh.Height)
	states := map[Height]ConsensusState{
		h.TrustedHeight: devnetTrusted(),
		hHeight: {
			Timestamp:          lh.Nanos() + 1, // differs
			NextValidatorsHash: lh.NextValidatorsHash,
			Root:               MerkleRoot{Hash: lh.AppHash},
		},
	}
	client := newTestClient(devnetClientState(), states)
	if !client.CheckForMisbehaviour(NewHeaderMessage(h)) {
		t.Fatal("expected misbehaviour for conflicting timestamp")
	}
}

func TestCheckForMisbehaviourConflictingAppHash(t *testing.T) {
	h := devnetHeader()
	lh := h.SignedHeader
	hHeight := Height(lh.Height)
	states := map[Height]ConsensusState{
		h.TrustedHeight: devnetTrusted(),
		hHeight: {
			Timestamp:          lh.Nanos(),
			NextValidatorsHash: lh.NextValidatorsHash,
			Root:               MerkleRoot{Hash: []byte{0xFF}}, // differs
		},
	}
	client := newTestClient(devnetClientState(), states)
	if !client.CheckForMisbehaviour(NewHeaderMessage(h)) {
		t.Fatal("expected misbehaviour for conflicting AppHash")
	}
}

func TestCheckForMisbehaviourEmptyMessage(t *testing.T) {
	client := newTestClient(devnetClientState(), devnetStates())
	if client.CheckForMisbehaviour(ClientMessage{}) {
		t.Fatal("expected no misbehaviour for empty message")
	}
}

// --- UpdateStateOnMisbehaviour tests ---

func TestUpdateStateOnMisbehaviour(t *testing.T) {
	cs := devnetClientState()
	client := newTestClient(cs, devnetStates())
	client.UpdateStateOnMisbehaviour()
	if client.Status(devnetNow()) != StatusFrozen {
		t.Fatal("expected client to be frozen after UpdateStateOnMisbehaviour")
	}
}

// --- UpdateState tests ---

func TestUpdateStateStoresConsensusState(t *testing.T) {
	states := devnetStates()
	client := newTestClient(devnetClientState(), states)
	h := devnetHeader()
	heights := client.UpdateState(NewHeaderMessage(h))
	if len(heights) != 1 {
		t.Fatalf("expected 1 height, got %d", len(heights))
	}
	newHeight := Height(h.SignedHeader.Height)
	if heights[0] != newHeight {
		t.Fatalf("got height %d want %d", heights[0], newHeight)
	}
	stored, found := states[newHeight]
	if !found {
		t.Fatal("expected consensus state to be stored at new height")
	}
	wantNanos := uint64(h.SignedHeader.TimeSeconds)*1_000_000_000 + uint64(h.SignedHeader.TimeNanos)
	if stored.Timestamp != wantNanos {
		t.Fatalf("stored timestamp %d want %d", stored.Timestamp, wantNanos)
	}
}

func TestUpdateStateAdvancesLatestHeight(t *testing.T) {
	cs := devnetClientState()
	cs.LatestHeight = Height(devnetHeight - 1)
	states := devnetStates()
	client := newTestClient(cs, states)
	client.UpdateState(NewHeaderMessage(devnetHeader()))
	want := Height(devnetHeight)
	if client.cs.LatestHeight != want {
		t.Fatalf("LatestHeight got %d want %d", client.cs.LatestHeight, want)
	}
}

func TestUpdateStateDuplicateNoOp(t *testing.T) {
	h := devnetHeader()
	newHeight := Height(h.SignedHeader.Height)
	existing := ConsensusState{Timestamp: 999}
	states := map[Height]ConsensusState{
		h.TrustedHeight: devnetTrusted(),
		newHeight:       existing,
	}
	client := newTestClient(devnetClientState(), states)
	client.UpdateState(NewHeaderMessage(h))
	// existing state must not be overwritten
	if states[newHeight].Timestamp != 999 {
		t.Fatal("expected no-op: existing consensus state should not be overwritten")
	}
}

func TestUpdateStateMisbehaviourMsgReturnsNil(t *testing.T) {
	client := newTestClient(devnetClientState(), devnetStates())
	heights := client.UpdateState(NewMisbehaviourMessage(Misbehaviour{HeaderA: devnetHeader(), HeaderB: devnetHeader()}))
	if heights != nil {
		t.Fatal("expected nil for Misbehaviour message")
	}
}

// --- Initialize tests ---

func TestInitializeOK(t *testing.T) {
	states := map[Height]ConsensusState{}
	client := newTestClient(ClientState{}, states)
	cs := devnetClientState()
	cs.LatestHeight = Height(100)
	initial := ConsensusState{
		Timestamp:          testNow,
		NextValidatorsHash: devnetVH,
	}
	if err := client.Initialize(cs, initial); err != nil {
		t.Fatalf("Initialize: %v", err)
	}
	if client.LatestHeight() != cs.LatestHeight {
		t.Fatal("LatestHeight not set after Initialize")
	}
	stored, ok := states[cs.LatestHeight]
	if !ok {
		t.Fatal("expected initial consensus state to be stored")
	}
	if stored.Timestamp != testNow {
		t.Fatalf("stored timestamp %d want %d", stored.Timestamp, testNow)
	}
}

func TestInitializeEmptyChainID(t *testing.T) {
	cs := devnetClientState()
	cs.ChainID = ""
	if err := newTestClient(ClientState{}, map[Height]ConsensusState{}).Initialize(cs, ConsensusState{Timestamp: testNow, NextValidatorsHash: devnetVH}); err == nil {
		t.Fatal("expected error for empty chain ID")
	}
}

func TestInitializeZeroTrustingPeriod(t *testing.T) {
	cs := devnetClientState()
	cs.TrustingPeriod = 0
	if err := newTestClient(ClientState{}, map[Height]ConsensusState{}).Initialize(cs, ConsensusState{Timestamp: testNow, NextValidatorsHash: devnetVH}); err == nil {
		t.Fatal("expected error for zero trusting period")
	}
}

func TestInitializeZeroLatestHeight(t *testing.T) {
	cs := devnetClientState()
	cs.LatestHeight = 0
	if err := newTestClient(ClientState{}, map[Height]ConsensusState{}).Initialize(cs, ConsensusState{Timestamp: testNow, NextValidatorsHash: devnetVH}); err == nil {
		t.Fatal("expected error for zero latest height")
	}
}

func TestInitializeZeroTimestamp(t *testing.T) {
	cs := devnetClientState()
	cs.LatestHeight = Height(100)
	if err := newTestClient(ClientState{}, map[Height]ConsensusState{}).Initialize(cs, ConsensusState{NextValidatorsHash: devnetVH}); err == nil {
		t.Fatal("expected error for zero initial timestamp")
	}
}

func TestInitializeEmptyNextValidatorsHash(t *testing.T) {
	cs := devnetClientState()
	cs.LatestHeight = Height(100)
	if err := newTestClient(ClientState{}, map[Height]ConsensusState{}).Initialize(cs, ConsensusState{Timestamp: testNow}); err == nil {
		t.Fatal("expected error for empty next validators hash")
	}
}

// --- LatestHeight tests ---

func TestLatestHeight(t *testing.T) {
	cs := baseCS()
	if got := newTestClient(cs, map[Height]ConsensusState{}).LatestHeight(); got != cs.LatestHeight {
		t.Fatalf("got %d want %d", got, cs.LatestHeight)
	}
}

func TestLatestHeightUpdatedAfterUpdateState(t *testing.T) {
	cs := devnetClientState()
	cs.LatestHeight = Height(devnetHeight - 1)
	client := newTestClient(cs, devnetStates())
	client.UpdateState(NewHeaderMessage(devnetHeader()))
	if got := client.LatestHeight(); got != Height(devnetHeight) {
		t.Fatalf("got %d want %d", got, Height(devnetHeight))
	}
}

// --- TimestampAtHeight tests ---

func TestTimestampAtHeightFound(t *testing.T) {
	cs := baseCS()
	wantNanos := testNow - 1_000*1_000_000_000
	states := map[Height]ConsensusState{
		cs.LatestHeight: {Timestamp: wantNanos},
	}
	ts, ok := newTestClient(cs, states).TimestampAtHeight(cs.LatestHeight)
	if !ok {
		t.Fatal("expected consensus state to be found")
	}
	if ts != wantNanos {
		t.Fatalf("got %d want %d", ts, wantNanos)
	}
}

func TestTimestampAtHeightNotFound(t *testing.T) {
	cs := baseCS()
	_, ok := newTestClient(cs, map[Height]ConsensusState{}).TimestampAtHeight(cs.LatestHeight)
	if ok {
		t.Fatal("expected not found for missing consensus state")
	}
}

// --- RecoverClient tests ---

func TestRecoverClientOK(t *testing.T) {
	subjectStates := map[Height]ConsensusState{}
	subject := newTestClient(devnetClientState(), subjectStates)
	subject.cs.FrozenHeight = FrozenHeight

	substituteHeight := Height(devnetHeight)
	substituteConsState := ConsensusState{Timestamp: devnetNow(), NextValidatorsHash: devnetVH}
	substituteStates := map[Height]ConsensusState{substituteHeight: substituteConsState}
	substitute := newTestClient(devnetClientState(), substituteStates)
	substitute.cs.LatestHeight = substituteHeight

	if err := subject.RecoverClient(substitute); err != nil {
		t.Fatalf("RecoverClient: %v", err)
	}
	if subject.cs.IsFrozen() {
		t.Fatal("expected subject to be unfrozen after recovery")
	}
	if subject.cs.LatestHeight != substituteHeight {
		t.Fatalf("LatestHeight got %d want %d", subject.cs.LatestHeight, substituteHeight)
	}
	stored, ok := subjectStates[substituteHeight]
	if !ok {
		t.Fatal("expected substitute consensus state to be copied into subject")
	}
	if stored.Timestamp != substituteConsState.Timestamp {
		t.Fatalf("stored timestamp %d want %d", stored.Timestamp, substituteConsState.Timestamp)
	}
}

func TestRecoverClientNilSubstitute(t *testing.T) {
	subject := newTestClient(devnetClientState(), devnetStates())
	if err := subject.RecoverClient(nil); err == nil {
		t.Fatal("expected error for nil substitute")
	}
}

func TestRecoverClientMaxClockDriftMismatch(t *testing.T) {
	subject := newTestClient(devnetClientState(), devnetStates())
	subCS := devnetClientState()
	subCS.MaxClockDrift = subject.cs.MaxClockDrift + 1
	substitute := newTestClient(subCS, devnetStates())
	if err := subject.RecoverClient(substitute); err == nil {
		t.Fatal("expected error for MaxClockDrift mismatch")
	}
}

func TestRecoverClientSubstituteConsensusStateNotFound(t *testing.T) {
	subject := newTestClient(devnetClientState(), devnetStates())
	substituteHeight := Height(devnetHeight)
	substitute := newTestClient(devnetClientState(), map[Height]ConsensusState{})
	substitute.cs.LatestHeight = substituteHeight
	if err := subject.RecoverClient(substitute); err == nil {
		t.Fatal("expected error when substitute consensus state not found")
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
	cs := baseCS()
	client := newTestClient(cs, map[Height]ConsensusState{cs.LatestHeight: {Timestamp: testNow, Root: MerkleRoot{Hash: []byte("root")}}})
	if err := client.VerifyMembership(cs.LatestHeight, twoExistProofs(), twoLevelPath([]byte("ibc"), []byte("key")), nil); err == nil {
		t.Fatal("expected error for empty value")
	}
}

func TestVerifyMembershipProofCountMismatch(t *testing.T) {
	cs := baseCS()
	client := newTestClient(cs, map[Height]ConsensusState{cs.LatestHeight: {Timestamp: testNow, Root: MerkleRoot{Hash: []byte("root")}}})
	oneProof := []ics23.CommitmentProof{ics23.CommitmentProof_Exist{Exist: &ics23.ExistenceProof{}}}
	if err := client.VerifyMembership(cs.LatestHeight, oneProof, twoLevelPath([]byte("ibc"), []byte("key")), []byte("v")); err == nil {
		t.Fatal("expected error for proof count mismatch")
	}
}

func TestVerifyMembershipPathCountMismatch(t *testing.T) {
	cs := baseCS()
	client := newTestClient(cs, map[Height]ConsensusState{cs.LatestHeight: {Timestamp: testNow, Root: MerkleRoot{Hash: []byte("root")}}})
	onePath := types.MerklePath{KeyPath: [][]byte{[]byte("ibc")}}
	if err := client.VerifyMembership(cs.LatestHeight, twoExistProofs(), onePath, []byte("v")); err == nil {
		t.Fatal("expected error for path length mismatch")
	}
}

func TestVerifyMembershipConsensusStateNotFound(t *testing.T) {
	cs := baseCS()
	client := newTestClient(cs, map[Height]ConsensusState{})
	if err := client.VerifyMembership(cs.LatestHeight, twoExistProofs(), twoLevelPath([]byte("ibc"), []byte("key")), []byte("v")); err == nil {
		t.Fatal("expected error when consensus state not found")
	}
}

func TestVerifyMembershipEmptyRoot(t *testing.T) {
	cs := baseCS()
	client := newTestClient(cs, map[Height]ConsensusState{cs.LatestHeight: {Timestamp: testNow, Root: MerkleRoot{Hash: nil}}})
	if err := client.VerifyMembership(cs.LatestHeight, twoExistProofs(), twoLevelPath([]byte("ibc"), []byte("key")), []byte("v")); err == nil {
		t.Fatal("expected error for empty root hash")
	}
}

func TestVerifyMembershipProofFails(t *testing.T) {
	cs := baseCS()
	client := newTestClient(cs, map[Height]ConsensusState{cs.LatestHeight: {Timestamp: testNow, Root: MerkleRoot{Hash: []byte("root")}}})
	if err := client.VerifyMembership(cs.LatestHeight, twoExistProofs(), twoLevelPath([]byte("ibc"), []byte("key")), []byte("v")); err == nil {
		t.Fatal("expected error for invalid proof")
	}
}

// --- VerifyNonMembership tests ---

func TestVerifyNonMembershipProofCountMismatch(t *testing.T) {
	cs := baseCS()
	client := newTestClient(cs, map[Height]ConsensusState{cs.LatestHeight: {Timestamp: testNow, Root: MerkleRoot{Hash: []byte("root")}}})
	oneProof := []ics23.CommitmentProof{ics23.CommitmentProof_Exist{Exist: &ics23.ExistenceProof{}}}
	if err := client.VerifyNonMembership(cs.LatestHeight, oneProof, twoLevelPath([]byte("ibc"), []byte("key"))); err == nil {
		t.Fatal("expected error for proof count mismatch")
	}
}

func TestVerifyNonMembershipConsensusStateNotFound(t *testing.T) {
	cs := baseCS()
	client := newTestClient(cs, map[Height]ConsensusState{})
	proofs := []ics23.CommitmentProof{
		ics23.CommitmentProof_Nonexist{Nonexist: &ics23.NonExistenceProof{}},
		ics23.CommitmentProof_Exist{Exist: &ics23.ExistenceProof{}},
	}
	if err := client.VerifyNonMembership(cs.LatestHeight, proofs, twoLevelPath([]byte("ibc"), []byte("key"))); err == nil {
		t.Fatal("expected error when consensus state not found")
	}
}

func TestVerifyNonMembershipEmptyRoot(t *testing.T) {
	cs := baseCS()
	client := newTestClient(cs, map[Height]ConsensusState{cs.LatestHeight: {Timestamp: testNow, Root: MerkleRoot{Hash: nil}}})
	proofs := []ics23.CommitmentProof{
		ics23.CommitmentProof_Nonexist{Nonexist: &ics23.NonExistenceProof{}},
		ics23.CommitmentProof_Exist{Exist: &ics23.ExistenceProof{}},
	}
	if err := client.VerifyNonMembership(cs.LatestHeight, proofs, twoLevelPath([]byte("ibc"), []byte("key"))); err == nil {
		t.Fatal("expected error for empty root hash")
	}
}

func TestVerifyNonMembershipFirstProofNotNonexist(t *testing.T) {
	cs := baseCS()
	client := newTestClient(cs, map[Height]ConsensusState{cs.LatestHeight: {Timestamp: testNow, Root: MerkleRoot{Hash: []byte("root")}}})
	if err := client.VerifyNonMembership(cs.LatestHeight, twoExistProofs(), twoLevelPath([]byte("ibc"), []byte("key"))); err == nil {
		t.Fatal("expected error when first proof is not a non-existence proof")
	}
}

func TestVerifyNonMembershipProofFails(t *testing.T) {
	cs := baseCS()
	client := newTestClient(cs, map[Height]ConsensusState{cs.LatestHeight: {Timestamp: testNow, Root: MerkleRoot{Hash: []byte("root")}}})
	proofs := []ics23.CommitmentProof{
		ics23.CommitmentProof_Nonexist{Nonexist: &ics23.NonExistenceProof{}},
		ics23.CommitmentProof_Exist{Exist: &ics23.ExistenceProof{}},
	}
	if err := client.VerifyNonMembership(cs.LatestHeight, proofs, twoLevelPath([]byte("ibc"), []byte("key"))); err == nil {
		t.Fatal("expected error for invalid non-existence proof")
	}
}

// --- VerifyUpgradeAndUpdateState tests ---

func TestVerifyUpgradeAndUpdateStateOK(t *testing.T) {
	cs := baseCS()
	client := newTestClient(cs, map[Height]ConsensusState{cs.LatestHeight: {Timestamp: testNow}})

	newCS := ClientState{
		ChainID:        "union-devnet-2",
		TrustingPeriod: cs.TrustingPeriod,
		MaxClockDrift:  cs.MaxClockDrift,
		LatestHeight:   cs.LatestHeight + 1,
	}
	newConsState := ConsensusState{Timestamp: testNow + 1_000_000_000}

	if err := client.VerifyUpgradeAndUpdateState(
		EncodeClientState(newCS),
		mustConsState(newConsState),
		[]byte("proof-placeholder"),
		[]byte("proof-placeholder"),
	); err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if client.LatestHeight() != newCS.LatestHeight {
		t.Fatalf("LatestHeight: got %d want %d", client.LatestHeight(), newCS.LatestHeight)
	}
}

func TestVerifyUpgradeAndUpdateStateFrozen(t *testing.T) {
	cs := baseCS()
	client := newTestClient(cs, map[Height]ConsensusState{cs.LatestHeight: {Timestamp: testNow}})

	frozen := ClientState{
		ChainID:        "x",
		TrustingPeriod: cs.TrustingPeriod,
		FrozenHeight:   1,
		LatestHeight:   cs.LatestHeight + 1,
	}
	if err := client.VerifyUpgradeAndUpdateState(
		EncodeClientState(frozen),
		mustConsState(ConsensusState{Timestamp: testNow + 1}),
		nil, nil,
	); err == nil {
		t.Fatal("expected error for frozen upgraded client state")
	}
}

func TestVerifyUpgradeAndUpdateStateHeightNotAdvancing(t *testing.T) {
	cs := baseCS()
	client := newTestClient(cs, map[Height]ConsensusState{cs.LatestHeight: {Timestamp: testNow}})

	same := ClientState{
		TrustingPeriod: cs.TrustingPeriod,
		LatestHeight:   cs.LatestHeight,
	}
	if err := client.VerifyUpgradeAndUpdateState(
		EncodeClientState(same),
		mustConsState(ConsensusState{Timestamp: testNow + 1}),
		nil, nil,
	); err == nil {
		t.Fatal("expected error for non-advancing upgrade height")
	}
}

func TestVerifyUpgradeAndUpdateStateZeroTimestamp(t *testing.T) {
	cs := baseCS()
	client := newTestClient(cs, map[Height]ConsensusState{cs.LatestHeight: {Timestamp: testNow}})

	newCS := ClientState{
		TrustingPeriod: cs.TrustingPeriod,
		LatestHeight:   cs.LatestHeight + 1,
	}
	if err := client.VerifyUpgradeAndUpdateState(
		EncodeClientState(newCS),
		mustConsState(ConsensusState{Timestamp: 0}),
		nil, nil,
	); err == nil {
		t.Fatal("expected error for zero timestamp in upgraded consensus state")
	}
}

// mustConsState ABI-encodes a ConsensusState for use in tests.
// Root.Hash and NextValidatorsHash default to 32 zero bytes if unset.
func mustConsState(cs ConsensusState) []byte {
	if len(cs.Root.Hash) == 0 {
		cs.Root.Hash = make([]byte, 32)
	}
	if len(cs.NextValidatorsHash) == 0 {
		cs.NextValidatorsHash = make([]byte, 32)
	}
	b, err := EncodeConsensusState(cs)
	if err != nil {
		panic("mustConsState: " + err.Error())
	}
	return b
}
