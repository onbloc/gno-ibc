package cometbls

import (
	"testing"

	cometblsp "gno.land/p/core/ibc/lightclients/cometbls"
	"gno.land/p/nt/uassert/v0"
	"gno.land/r/core/ibc/v1/core"
)

func resetAdapterEntries() {
	entries = make(map[core.ClientId]*clientEntry)
}

func newAdapterClientEntry(cs cometblsp.ClientState, cons cometblsp.ConsensusState) *clientEntry {
	states := make(map[cometblsp.Height]cometblsp.ConsensusState)
	client := cometblsp.New(
		func(h cometblsp.Height) (cometblsp.ConsensusState, bool) {
			s, ok := states[h]
			return s, ok
		},
		func(h cometblsp.Height, s cometblsp.ConsensusState) {
			states[h] = s
		},
	)
	if err := client.Initialize(cs, cons); err != nil {
		panic(err)
	}
	return &clientEntry{
		client:          client,
		consensusStates: states,
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

func TestVerifyMembershipRejectsFrozenClientBeforeProofDecode(t *testing.T) {
	resetAdapterEntries()
	clientId := core.ClientId(1)
	cs := activeAdapterClientState()
	cs.FrozenHeight = cometblsp.FrozenHeight
	installAdapterClient(clientId, cs, activeAdapterConsensusState())

	uassert.AbortsContains(t, "cometbls: client is Frozen", func(cur realm) {
		Adapter{}.VerifyMembership(clientId, core.Height(cs.LatestHeight), []byte{0xff}, []byte("key"), []byte("value"))
	})
}

func TestVerifyNonMembershipRejectsFrozenClientBeforeProofDecode(t *testing.T) {
	resetAdapterEntries()
	clientId := core.ClientId(1)
	cs := activeAdapterClientState()
	cs.FrozenHeight = cometblsp.FrozenHeight
	installAdapterClient(clientId, cs, activeAdapterConsensusState())

	uassert.AbortsContains(t, "cometbls: client is Frozen", func(cur realm) {
		Adapter{}.VerifyNonMembership(clientId, core.Height(cs.LatestHeight), []byte{0xff}, []byte("key"))
	})
}

func TestVerifyMembershipRejectsExpiredClientBeforeProofDecode(t *testing.T) {
	resetAdapterEntries()
	clientId := core.ClientId(1)
	cs := activeAdapterClientState()
	cs.TrustingPeriod = 1
	cons := activeAdapterConsensusState()
	cons.Timestamp = 1
	installAdapterClient(clientId, cs, cons)

	uassert.AbortsContains(t, "cometbls: client is Expired", func(cur realm) {
		Adapter{}.VerifyMembership(clientId, core.Height(cs.LatestHeight), []byte{0xff}, []byte("key"), []byte("value"))
	})
}

func TestVerifyNonMembershipRejectsExpiredClientBeforeProofDecode(t *testing.T) {
	resetAdapterEntries()
	clientId := core.ClientId(1)
	cs := activeAdapterClientState()
	cs.TrustingPeriod = 1
	cons := activeAdapterConsensusState()
	cons.Timestamp = 1
	installAdapterClient(clientId, cs, cons)

	uassert.AbortsContains(t, "cometbls: client is Expired", func(cur realm) {
		Adapter{}.VerifyNonMembership(clientId, core.Height(cs.LatestHeight), []byte{0xff}, []byte("key"))
	})
}
