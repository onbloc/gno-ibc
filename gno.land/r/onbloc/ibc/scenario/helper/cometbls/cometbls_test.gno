package cometbls

import (
	"crypto/keccak256"
	"testing"

	"gno.land/p/onbloc/ibc/union/lightclient"
	lc "gno.land/p/onbloc/ibc/union/lightclient/cometbls"
	types "gno.land/p/onbloc/ibc/union/types"
)

// TestProveConsensusAcceptedByRealClient asserts the inline ICS23 proof built by
// L1.ProveConsensus is accepted by a real cometbls light client seeded with the
// returned root — i.e. the genuine VerifyMembership path passes.
func TestProveConsensusAcceptedByRealClient(t *testing.T) {
	const (
		l1Height = uint64(100)
		l2Height = uint64(200)
	)

	var contractAddr types.H256 // zero
	l2ClientId := types.ClientId(7)

	l2Consensus := make([]byte, 72)
	for i := range l2Consensus {
		l2Consensus[i] = byte(i)
	}

	proof, root := ProveConsensus(contractAddr, l2ClientId, l2Height, l2Consensus)

	client, err := lc.NewCometblsLightClient(
		&lc.ClientState{
			ChainID:         "l1",
			TrustingPeriod:  1 << 62,
			UnbondingPeriod: 1 << 63,
			MaxClockDrift:   1 << 30,
			LatestHeight:    types.NewHeight(0, l1Height),
			ContractAddress: contractAddr,
		},
		&lc.ConsensusState{
			Timestamp:          1,
			Root:               lc.MerkleRoot{Hash: root},
			NextValidatorsHash: make([]byte, 32),
		},
	)
	if err != nil {
		t.Fatalf("new client: %v", err)
	}

	// The proof-verification path requires the L1 to be Active; a too-short
	// trusting period would report Expired (consensus timestamp is epoch).
	if status := client.Status(); status != lightclient.Active {
		t.Fatalf("L1 client status: got %v, want Active", status)
	}

	consensusPath := types.ConsensusStatePath(l2ClientId, types.NewHeight(0, l2Height))
	valueHash := keccak256.Sum256(l2Consensus)

	if err := client.VerifyMembership(l1Height, consensusPath[:], proof, valueHash[:]); err != nil {
		t.Fatalf("real cometbls rejected the inline proof: %v", err)
	}
}
