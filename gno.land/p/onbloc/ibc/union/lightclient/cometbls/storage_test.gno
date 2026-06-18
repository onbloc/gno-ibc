package cometbls

import (
	"sort"
	"testing"

	"gno.land/p/onbloc/ibc/union/types"
)

func TestHeightKeyLexicographicOrder(t *testing.T) {
	heights := []types.Height{
		{RevisionNumber: 1, RevisionHeight: 10},
		{RevisionNumber: 0, RevisionHeight: 1000},
		{RevisionNumber: 0, RevisionHeight: 2},
		{RevisionNumber: 1, RevisionHeight: 2},
		{RevisionNumber: 0, RevisionHeight: 10},
		{RevisionNumber: 0, RevisionHeight: 1},
		{RevisionNumber: 1, RevisionHeight: 1},
	}

	keys := make([]string, len(heights))
	for i, height := range heights {
		keys[i] = heightKey(height)
	}
	sort.Strings(keys)

	want := []string{
		heightKey(types.Height{RevisionNumber: 0, RevisionHeight: 1}),
		heightKey(types.Height{RevisionNumber: 0, RevisionHeight: 2}),
		heightKey(types.Height{RevisionNumber: 0, RevisionHeight: 10}),
		heightKey(types.Height{RevisionNumber: 0, RevisionHeight: 1000}),
		heightKey(types.Height{RevisionNumber: 1, RevisionHeight: 1}),
		heightKey(types.Height{RevisionNumber: 1, RevisionHeight: 2}),
		heightKey(types.Height{RevisionNumber: 1, RevisionHeight: 10}),
	}
	for i := range want {
		if keys[i] != want[i] {
			t.Fatalf("sorted key[%d]: got %q want %q; keys=%v", i, keys[i], want[i], keys)
		}
	}
}

func TestConsensusStateExactHeightLookup(t *testing.T) {
	c := newTestClient(t)
	c.setConsensusState(types.NewHeight(10), &ConsensusState{
		Timestamp:          10,
		Root:               MerkleRoot{Hash: repeat32(0x10)},
		NextValidatorsHash: repeat32(0x11),
	})
	c.setConsensusState(types.NewHeight(20), &ConsensusState{
		Timestamp:          20,
		Root:               MerkleRoot{Hash: repeat32(0x20)},
		NextValidatorsHash: repeat32(0x21),
	})
	c.setConsensusState(types.NewHeight(1000), &ConsensusState{
		Timestamp:          1000,
		Root:               MerkleRoot{Hash: repeat32(0x30)},
		NextValidatorsHash: repeat32(0x31),
	})

	for _, tc := range []struct {
		height uint64
		want   types.Timestamp
	}{
		{10, 10},
		{20, 20},
		{100, types.Timestamp(testNow)},
		{1000, 1000},
	} {
		got, err := c.GetTimestampAtHeight(tc.height)
		if err != nil {
			t.Fatalf("GetTimestampAtHeight(%d): %v", tc.height, err)
		}
		if got != tc.want {
			t.Fatalf("GetTimestampAtHeight(%d): got %d want %d", tc.height, got, tc.want)
		}
	}

	if _, err := c.GetTimestampAtHeight(11); err == nil {
		t.Fatal("GetTimestampAtHeight(11): expected missing exact height error")
	}
}
