package cometbls

import "testing"

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
