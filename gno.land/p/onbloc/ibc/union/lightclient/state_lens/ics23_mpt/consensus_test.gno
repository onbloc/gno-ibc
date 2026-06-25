package ics23mpt

import "testing"

func TestExtractConsensusStateRejectsShortData(t *testing.T) {
	_, err := ClientState{
		TimestampOffset:   0,
		StateRootOffset:   0,
		StorageRootOffset: 0,
	}.ExtractConsensusState([]byte{0x01})
	if err != ErrConsensusStateTooShort {
		t.Fatalf("ExtractConsensusState: got %v want %v", err, ErrConsensusStateTooShort)
	}
}
