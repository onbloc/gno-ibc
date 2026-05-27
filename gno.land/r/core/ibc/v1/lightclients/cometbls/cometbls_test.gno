package cometbls

import (
	"bytes"
	"testing"

	cometblsp "gno.land/p/core/ibc/lightclients/cometbls"
	"gno.land/p/nt/uassert/v0"
	"gno.land/r/core/ibc/v1/core"
)

func resetAdapterEntries() {
	entries = make(map[core.ClientId]*clientEntry)
}

func newAdapterClientEntry(cs cometblsp.ClientState, cons cometblsp.ConsensusState) *clientEntry {
	return &clientEntry{
		consensusStates: map[cometblsp.Height]cometblsp.ConsensusState{cs.LatestHeight: cons},
		cs:              cs,
	}
}

func activeAdapterClientState() cometblsp.ClientState {
	return cometblsp.ClientState{
		ChainID:        "union-test",
		TrustingPeriod: 14 * 24 * 3600 * 1_000_000_000,
		MaxClockDrift:  10 * 1_000_000_000,
		LatestHeight:   cometblsp.Height(10),
	}
}

func activeAdapterConsensusState() cometblsp.ConsensusState {
	return cometblsp.ConsensusState{
		Timestamp:          nowNanos(),
		Root:               cometblsp.MerkleRoot{Hash: []byte{0x01}},
		NextValidatorsHash: cometblsp.H256{0x02},
	}
}

func installAdapterClient(clientId core.ClientId, cs cometblsp.ClientState, cons cometblsp.ConsensusState) {
	entries[clientId] = newAdapterClientEntry(cs, cons)
}

func TestWasmContractStoreKey(cur realm, t *testing.T) {
	var contractAddress cometblsp.H256
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

func TestMutatingEntrypointsRequireCoreCaller(cur realm, t *testing.T) {
	resetAdapterEntries()
	adapter := Adapter{}

	uassert.AbortsContains(t, cur, "cometbls: core only", func(cur realm) {
		adapter.CreateClient(cross(cur), core.ClientId(1), nil, nil)
	})
	uassert.AbortsContains(t, cur, "cometbls: core only", func(cur realm) {
		adapter.UpdateClient(cross(cur), core.ClientId(1), nil)
	})
	uassert.AbortsContains(t, cur, "cometbls: core only", func(cur realm) {
		adapter.Misbehaviour(cross(cur), core.ClientId(1), nil)
	})
	uassert.AbortsContains(t, cur, "cometbls: core only", func(cur realm) {
		adapter.ForceUpdateClient(cross(cur), core.ClientId(1), nil, nil)
	})
}

func TestVerifyMembershipAndNonMembershipRejectInactiveBeforeProofDecode(cur realm, t *testing.T) {
	testCases := []struct {
		name        string
		mutate      func(*cometblsp.ClientState, *cometblsp.ConsensusState)
		statusLabel string
	}{
		{"frozen", func(cs *cometblsp.ClientState, _ *cometblsp.ConsensusState) {
			cs.FrozenHeight = cometblsp.FrozenHeight
		}, "Frozen"},
		{"expired", func(cs *cometblsp.ClientState, cons *cometblsp.ConsensusState) {
			cs.TrustingPeriod = 1
			cons.Timestamp = 1
		}, "Expired"},
	}
	for _, tc := range testCases {
		t.Run(tc.name+"/membership", func(t *testing.T) {
			resetAdapterEntries()
			clientId := core.ClientId(1)
			cs := activeAdapterClientState()
			cons := activeAdapterConsensusState()
			tc.mutate(&cs, &cons)
			installAdapterClient(clientId, cs, cons)
			uassert.AbortsContains(t, cur, "cometbls: client is "+tc.statusLabel, func(cur realm) {
				Adapter{}.VerifyMembership(clientId, core.Height(cs.LatestHeight), []byte{0xff}, []byte("key"), []byte("value"))
			})
		})
		t.Run(tc.name+"/non-membership", func(t *testing.T) {
			resetAdapterEntries()
			clientId := core.ClientId(1)
			cs := activeAdapterClientState()
			cons := activeAdapterConsensusState()
			tc.mutate(&cs, &cons)
			installAdapterClient(clientId, cs, cons)
			uassert.AbortsContains(t, cur, "cometbls: client is "+tc.statusLabel, func(cur realm) {
				Adapter{}.VerifyNonMembership(clientId, core.Height(cs.LatestHeight), []byte{0xff}, []byte("key"))
			})
		})
	}
}

func TestGetLatestHeightReturnsStoredClientStateHeight(cur realm, t *testing.T) {
	resetAdapterEntries()
	clientId := core.ClientId(1)
	cs := activeAdapterClientState()
	cs.LatestHeight = cometblsp.Height(42)
	installAdapterClient(clientId, cs, activeAdapterConsensusState())

	if got := (Adapter{}).GetLatestHeight(clientId); got != core.Height(42) {
		t.Fatalf("got %d want %d", got, core.Height(42))
	}
}

func TestGetTimestampReturnsStoredConsensusTimestamp(cur realm, t *testing.T) {
	resetAdapterEntries()
	clientId := core.ClientId(1)
	cs := activeAdapterClientState()
	cons := activeAdapterConsensusState()
	cons.Timestamp = 12345
	installAdapterClient(clientId, cs, cons)

	if got := (Adapter{}).GetTimestamp(clientId, core.Height(cs.LatestHeight)); got != core.Timestamp(12345) {
		t.Fatalf("got %d want %d", got, core.Timestamp(12345))
	}
}

func TestGetTimestampPanicsWhenConsensusStateMissing(cur realm, t *testing.T) {
	resetAdapterEntries()
	clientId := core.ClientId(1)
	installAdapterClient(clientId, activeAdapterClientState(), activeAdapterConsensusState())

	uassert.AbortsContains(t, cur, "cometbls: consensus state not found at height 99", func(cur realm) {
		Adapter{}.GetTimestamp(clientId, core.Height(99))
	})
}

func TestGetStatusActive(cur realm, t *testing.T) {
	resetAdapterEntries()
	clientId := core.ClientId(1)
	installAdapterClient(clientId, activeAdapterClientState(), activeAdapterConsensusState())

	if got := (Adapter{}).GetStatus(clientId); got != core.StatusActive {
		t.Fatalf("got %s want %s", got, core.StatusActive)
	}
}

func TestGetStatusFrozen(cur realm, t *testing.T) {
	resetAdapterEntries()
	clientId := core.ClientId(1)
	cs := activeAdapterClientState()
	cs.FrozenHeight = cometblsp.FrozenHeight
	installAdapterClient(clientId, cs, activeAdapterConsensusState())

	if got := (Adapter{}).GetStatus(clientId); got != core.StatusFrozen {
		t.Fatalf("got %s want %s", got, core.StatusFrozen)
	}
}

func TestGetStatusExpiredWhenLatestConsensusStateMissing(cur realm, t *testing.T) {
	resetAdapterEntries()
	clientId := core.ClientId(1)
	cs := activeAdapterClientState()
	e := newAdapterClientEntry(cs, activeAdapterConsensusState())
	delete(e.consensusStates, cs.LatestHeight)
	entries[clientId] = e

	if got := (Adapter{}).GetStatus(clientId); got != core.StatusExpired {
		t.Fatalf("got %s want %s", got, core.StatusExpired)
	}
}

// --- ForceUpdateClient (applyForceUpdate) ---

// encodableConsensusState returns a ConsensusState with a 32-byte root hash,
// required by EncodeConsensusState.
func encodableConsensusState(ts uint64) cometblsp.ConsensusState {
	var hash [32]byte
	hash[0] = 0x01
	return cometblsp.ConsensusState{
		Timestamp:          ts,
		Root:               cometblsp.MerkleRoot{Hash: hash[:]},
		NextValidatorsHash: cometblsp.H256{0x02},
	}
}

func encodeState(t *testing.T, cs cometblsp.ClientState, cons cometblsp.ConsensusState) ([]byte, []byte) {
	t.Helper()
	csBytes := cometblsp.EncodeClientState(cs)
	consBytes, err := cometblsp.EncodeConsensusState(cons)
	if err != nil {
		t.Fatalf("EncodeConsensusState: %v", err)
	}
	return csBytes, consBytes
}

func TestForceUpdateClientRecoveredExpiredClient(t *testing.T) {
	resetAdapterEntries()
	clientId := core.ClientId(1)
	cs := activeAdapterClientState()
	expiredCons := encodableConsensusState(1) // nanosecond 1 — far in the past
	installAdapterClient(clientId, cs, expiredCons)

	if got := (Adapter{}).GetStatus(clientId); got != core.StatusExpired {
		t.Fatalf("pre-condition: expected Expired, got %s", got)
	}

	freshCons := encodableConsensusState(nowNanos())
	csBytes, consBytes := encodeState(t, cs, freshCons)
	applyForceUpdate(clientId, csBytes, consBytes)

	if got := (Adapter{}).GetStatus(clientId); got != core.StatusActive {
		t.Fatalf("post force-update: expected Active, got %s", got)
	}
}

func TestForceUpdateClientUnfreezesFrozenClient(t *testing.T) {
	resetAdapterEntries()
	clientId := core.ClientId(1)
	cs := activeAdapterClientState()
	cs.FrozenHeight = cometblsp.FrozenHeight
	installAdapterClient(clientId, cs, encodableConsensusState(nowNanos()))

	if got := (Adapter{}).GetStatus(clientId); got != core.StatusFrozen {
		t.Fatalf("pre-condition: expected Frozen, got %s", got)
	}

	// Pass a client state that still has FrozenHeight set; applyForceUpdate must clear it.
	csBytes, consBytes := encodeState(t, cs, encodableConsensusState(nowNanos()))
	applyForceUpdate(clientId, csBytes, consBytes)

	if got := (Adapter{}).GetStatus(clientId); got != core.StatusActive {
		t.Fatalf("post force-update: expected Active, got %s", got)
	}
	if entries[clientId].cs.FrozenHeight != 0 {
		t.Fatalf("FrozenHeight not cleared: got %d", entries[clientId].cs.FrozenHeight)
	}
}

func TestForceUpdateClientPanicsOnHeightRegression(t *testing.T) {
	resetAdapterEntries()
	clientId := core.ClientId(1)
	cs := activeAdapterClientState()
	cs.LatestHeight = cometblsp.Height(100)
	installAdapterClient(clientId, cs, encodableConsensusState(nowNanos()))

	lowerCs := activeAdapterClientState()
	lowerCs.LatestHeight = cometblsp.Height(50)
	csBytes, consBytes := encodeState(t, lowerCs, encodableConsensusState(nowNanos()))

	uassert.AbortsContains(t, "force-update height must not regress", func(_ realm) {
		applyForceUpdate(clientId, csBytes, consBytes)
	})
}

func TestForceUpdateClientClearsHistoricalConsensusStates(t *testing.T) {
	resetAdapterEntries()
	clientId := core.ClientId(1)
	cs := activeAdapterClientState()
	cs.LatestHeight = cometblsp.Height(10)
	e := newAdapterClientEntry(cs, encodableConsensusState(nowNanos()))
	// Seed an extra historical state at height 5.
	e.consensusStates[cometblsp.Height(5)] = encodableConsensusState(1)
	entries[clientId] = e

	newCs := activeAdapterClientState()
	newCs.LatestHeight = cometblsp.Height(20)
	csBytes, consBytes := encodeState(t, newCs, encodableConsensusState(nowNanos()))
	applyForceUpdate(clientId, csBytes, consBytes)

	if len(entries[clientId].consensusStates) != 1 {
		t.Fatalf("expected 1 consensus state, got %d", len(entries[clientId].consensusStates))
	}
	if _, ok := entries[clientId].consensusStates[cometblsp.Height(20)]; !ok {
		t.Fatal("consensus state at new height not found")
	}
}

func TestForceUpdateClientPanicsOnInvalidClientStateBytes(t *testing.T) {
	resetAdapterEntries()
	clientId := core.ClientId(1)
	installAdapterClient(clientId, activeAdapterClientState(), encodableConsensusState(nowNanos()))

	uassert.AbortsContains(t, "cometbls: invalid client state", func(_ realm) {
		// 0xff alone is a truncated protobuf varint — guaranteed decode error.
		applyForceUpdate(clientId, []byte{0xff}, nil)
	})
}
