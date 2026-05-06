package cometbls

import "testing"

// nowNanos = 2024-01-01 00:00:00 UTC in nanoseconds.
const testNow = uint64(1_704_067_200) * 1_000_000_000

func newTestClient(cs ClientState, states map[Height]ConsensusState) *CometBLSClient {
	return New(cs, func(h Height) (ConsensusState, bool) {
		s, ok := states[h]
		return s, ok
	})
}

func baseCS() ClientState {
	return ClientState{
		TrustingPeriod: 14 * 24 * 3600 * 1_000_000_000, // 14 days in ns; mirrors common Cosmos convention (2/3 of 21-day unbonding period)
		LatestHeight:   Height{RevisionNumber: 0, RevisionHeight: 100},
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
	cs.FrozenHeight = Height{RevisionNumber: 0, RevisionHeight: 1}
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
	cs.FrozenHeight = Height{RevisionNumber: 0, RevisionHeight: 1}
	// also expired — frozen should win
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
		LatestHeight:   Height{RevisionNumber: 0, RevisionHeight: uint64(devnetHeight - 1)},
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
