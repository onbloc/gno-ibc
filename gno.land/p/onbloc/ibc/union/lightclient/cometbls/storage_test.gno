package cometbls

import (
	"sort"
	"testing"

	"gno.land/p/onbloc/ibc/union/types"
)

func TestHeightKeyLexicographicOrder(t *testing.T) {
	// Union reference: consensus_state_keys_lexicographically_ordered,
	// https://github.com/unionlabs/union/blob/1bb07590230e/cosmwasm/lightclient/cometbls/src/storage.rs#L270.
	heights := []types.Height{
		{RevisionNumber: 2, RevisionHeight: 22},
		{RevisionNumber: 1, RevisionHeight: 5115},
		{RevisionNumber: 0, RevisionHeight: 23451},
		{RevisionNumber: 3, RevisionHeight: 1234},
		{RevisionNumber: 1, RevisionHeight: 2123},
		{RevisionNumber: 1, RevisionHeight: 1000},
		{RevisionNumber: 0, RevisionHeight: 132},
		{RevisionNumber: 0, RevisionHeight: 18446744073709551615}, // u64::MAX
	}

	keys := make([]string, len(heights))
	for i, height := range heights {
		keys[i] = heightKey(height)
	}
	sort.Strings(keys)

	want := []string{
		heightKey(types.Height{RevisionNumber: 0, RevisionHeight: 132}),
		heightKey(types.Height{RevisionNumber: 0, RevisionHeight: 23451}),
		heightKey(types.Height{RevisionNumber: 0, RevisionHeight: 18446744073709551615}), // u64::MAX
		heightKey(types.Height{RevisionNumber: 1, RevisionHeight: 1000}),
		heightKey(types.Height{RevisionNumber: 1, RevisionHeight: 2123}),
		heightKey(types.Height{RevisionNumber: 1, RevisionHeight: 5115}),
		heightKey(types.Height{RevisionNumber: 2, RevisionHeight: 22}),
		heightKey(types.Height{RevisionNumber: 3, RevisionHeight: 1234}),
	}
	for i := range want {
		if keys[i] != want[i] {
			t.Fatalf("sorted key[%d]: got %q want %q; keys=%v", i, keys[i], want[i], keys)
		}
	}
}

func TestConsensusStateExactHeightLookup(t *testing.T) {
	// Union reference: next_prev_consensus_state_key_works,
	// https://github.com/unionlabs/union/blob/1bb07590230e/cosmwasm/lightclient/cometbls/src/storage.rs#L210.
	c := newTestClient(t)
	// Set up consensus states matching Union's ordered_heights array:
	// (revision_number, revision_height, timestamp)
	orderedHeights := []struct {
		revNum    uint64
		revH      uint64
		timestamp uint64
	}{
		{0, 132, 1231238123},
		{0, 23451, 12323},
		{0, 18446744073709551615 - 1, 23713}, // u64::MAX - 1
		{1, 1000, 9},
		{1, 2123, 3781273413},
		{1, 5115, 2377281},
		{2, 22, 2391232},
		{3, 1234, 238918392},
	}
	for _, h := range orderedHeights {
		c.setConsensusState(types.Height{RevisionNumber: h.revNum, RevisionHeight: h.revH}, &ConsensusState{
			Timestamp:          h.timestamp,
			Root:               MerkleRoot{Hash: repeat32(0x10)},
			NextValidatorsHash: repeat32(0x11),
		})
	}

	// Test exact lookups for revision 0 heights (what GetTimestampAtHeight supports)
	rev0Heights := []struct{ h, ts uint64 }{
		{132, 1231238123},
		{23451, 12323},
		{18446744073709551615 - 1, 23713}, // u64::MAX - 1
	}
	for _, h := range rev0Heights {
		got, err := c.GetTimestampAtHeight(h.h)
		if err != nil {
			t.Fatalf("GetTimestampAtHeight(%d): %v", h.h, err)
		}
		if got != types.Timestamp(h.ts) {
			t.Fatalf("GetTimestampAtHeight(%d): got %d want %d", h.h, got, h.ts)
		}
	}

	// Test missing height (between 132 and 23451, not present)
	if _, err := c.GetTimestampAtHeight(1000); err == nil {
		t.Fatal("GetTimestampAtHeight(1000): expected missing exact height error")
	}
}
