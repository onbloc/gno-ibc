package statelensics23mpt

import "testing"

func TestExtractConsensusStateRejectsShortData(t *testing.T) {
	_, err := ExtractConsensusState([]byte{0x01}, ClientState{
		TimestampOffset:   0,
		StateRootOffset:   0,
		StorageRootOffset: 0,
	})
	if err != ErrConsensusStateTooShort {
		t.Fatalf("ExtractConsensusState: got %v want %v", err, ErrConsensusStateTooShort)
	}
}
