package cometbls

import (
	"bytes"
	"testing"

	"gno.land/p/onbloc/ibc/union/types"
)

func TestClientStateCodecRoundTrip(t *testing.T) {
	cs := &ClientState{
		ChainID:         "union-devnet-1",
		TrustingPeriod:  100,
		UnbondingPeriod: 200,
		MaxClockDrift:   30,
		FrozenHeight:    types.NewHeight(0),
		LatestHeight:    types.NewHeight(42),
		ContractAddress: types.H256(repeat32Arr(0xAB)),
	}

	bz, err := EncodeClientState(cs)
	if err != nil {
		t.Fatalf("EncodeClientState: %v", err)
	}
	got, err := DecodeClientState(bz)
	if err != nil {
		t.Fatalf("DecodeClientState: %v", err)
	}
	if got.ChainID != cs.ChainID ||
		got.TrustingPeriod != cs.TrustingPeriod ||
		got.UnbondingPeriod != cs.UnbondingPeriod ||
		got.MaxClockDrift != cs.MaxClockDrift ||
		!got.FrozenHeight.EQ(cs.FrozenHeight) ||
		!got.LatestHeight.EQ(cs.LatestHeight) ||
		got.ContractAddress != cs.ContractAddress {
		t.Fatalf("client state round-trip mismatch: got %#v want %#v", got, cs)
	}
}

func TestConsensusStateCodecRoundTrip(t *testing.T) {
	cs := &ConsensusState{
		Timestamp:          1234567890,
		Root:               MerkleRoot{Hash: repeat32(0xCD)},
		NextValidatorsHash: repeat32(0xEF),
	}

	bz, err := EncodeConsensusState(cs)
	if err != nil {
		t.Fatalf("EncodeConsensusState: %v", err)
	}
	got, err := DecodeConsensusState(bz)
	if err != nil {
		t.Fatalf("DecodeConsensusState: %v", err)
	}
	if got.Timestamp != cs.Timestamp ||
		!bytes.Equal(got.Root.Hash, cs.Root.Hash) ||
		!bytes.Equal(got.NextValidatorsHash, cs.NextValidatorsHash) {
		t.Fatalf("consensus state round-trip mismatch: got %#v want %#v", got, cs)
	}
}

func repeat32Arr(b byte) [32]byte {
	var out [32]byte
	for i := range out {
		out[i] = b
	}
	return out
}
