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
		NextValidatorsHash: []byte{0x02},
	}
}

func installAdapterClient(clientId core.ClientId, cs cometblsp.ClientState, cons cometblsp.ConsensusState) {
	entries[clientId] = newAdapterClientEntry(cs, cons)
}

func TestWasmContractStoreKey(t *testing.T) {
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

func TestMutatingEntrypointsRequireCoreCaller(t *testing.T) {
	resetAdapterEntries()
	adapter := Adapter{}

	uassert.AbortsContains(t, "cometbls: core only", func(cur realm) {
		adapter.CreateClient(cross, core.ClientId(1), nil, nil)
	})
	uassert.AbortsContains(t, "cometbls: core only", func(cur realm) {
		adapter.UpdateClient(cross, core.ClientId(1), nil)
	})
	uassert.AbortsContains(t, "cometbls: core only", func(cur realm) {
		adapter.Misbehaviour(cross, core.ClientId(1), nil)
	})
}

func TestVerifyMembershipAndNonMembershipRejectInactiveBeforeProofDecode(t *testing.T) {
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
			uassert.AbortsContains(t, "cometbls: client is "+tc.statusLabel, func(cur realm) {
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
			uassert.AbortsContains(t, "cometbls: client is "+tc.statusLabel, func(cur realm) {
				Adapter{}.VerifyNonMembership(clientId, core.Height(cs.LatestHeight), []byte{0xff}, []byte("key"))
			})
		})
	}
}

func TestGetLatestHeightReturnsStoredClientStateHeight(t *testing.T) {
	resetAdapterEntries()
	clientId := core.ClientId(1)
	cs := activeAdapterClientState()
	cs.LatestHeight = cometblsp.Height(42)
	installAdapterClient(clientId, cs, activeAdapterConsensusState())

	if got := (Adapter{}).GetLatestHeight(clientId); got != core.Height(42) {
		t.Fatalf("got %d want %d", got, core.Height(42))
	}
}

func TestGetTimestampReturnsStoredConsensusTimestamp(t *testing.T) {
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

func TestGetTimestampPanicsWhenConsensusStateMissing(t *testing.T) {
	resetAdapterEntries()
	clientId := core.ClientId(1)
	installAdapterClient(clientId, activeAdapterClientState(), activeAdapterConsensusState())

	uassert.AbortsContains(t, "cometbls: consensus state not found at height 99", func(cur realm) {
		Adapter{}.GetTimestamp(clientId, core.Height(99))
	})
}

func TestGetStatusActive(t *testing.T) {
	resetAdapterEntries()
	clientId := core.ClientId(1)
	installAdapterClient(clientId, activeAdapterClientState(), activeAdapterConsensusState())

	if got := (Adapter{}).GetStatus(clientId); got != core.StatusActive {
		t.Fatalf("got %s want %s", got, core.StatusActive)
	}
}

func TestGetStatusFrozen(t *testing.T) {
	resetAdapterEntries()
	clientId := core.ClientId(1)
	cs := activeAdapterClientState()
	cs.FrozenHeight = cometblsp.FrozenHeight
	installAdapterClient(clientId, cs, activeAdapterConsensusState())

	if got := (Adapter{}).GetStatus(clientId); got != core.StatusFrozen {
		t.Fatalf("got %s want %s", got, core.StatusFrozen)
	}
}

func TestGetStatusExpiredWhenLatestConsensusStateMissing(t *testing.T) {
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
