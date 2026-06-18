package ics23mpt

import (
	"bytes"
	"testing"
)

func TestExtractConsensusStateRejectsShortData(t *testing.T) {
	// Union reference: extract_consensus_state reads timestamp/state root/storage
	// root at offsets from client_state.extra,
	// https://github.com/unionlabs/union/blob/1bb07590230e/cosmwasm/lightclient/state-lens-ics23-mpt/src/client.rs#L146.
	_, err := ExtractConsensusState([]byte{0x01}, ClientState{
		TimestampOffset:   0,
		StateRootOffset:   0,
		StorageRootOffset: 0,
	})
	if err != ErrConsensusStateTooShort {
		t.Fatalf("ExtractConsensusState: got %v want %v", err, ErrConsensusStateTooShort)
	}
}

func TestExtractConsensusStateAtConfiguredOffsets(t *testing.T) {
	// Union reference: extract_consensus_state uses the configured offsets for
	// each field,
	// https://github.com/unionlabs/union/blob/1bb07590230e/cosmwasm/lightclient/state-lens-ics23-mpt/src/client.rs#L146.
	stateRoot := bytes.Repeat([]byte{0x11}, 32)
	storageRoot := bytes.Repeat([]byte{0x22}, 32)
	data := make([]byte, 88)
	copy(data[3:35], stateRoot)
	copy(data[40:72], storageRoot)
	putUint64BE(data[80:88], 0x0102030405060708)

	got, err := ExtractConsensusState(data, ClientState{
		StateRootOffset:   3,
		StorageRootOffset: 40,
		TimestampOffset:   80,
	})
	if err != nil {
		t.Fatalf("ExtractConsensusState: %v", err)
	}
	if got.Timestamp != 0x0102030405060708 {
		t.Fatalf("timestamp: got %#x want %#x", got.Timestamp, uint64(0x0102030405060708))
	}
	if !bytes.Equal(got.StateRoot, stateRoot) {
		t.Fatalf("state root: got %x want %x", got.StateRoot, stateRoot)
	}
	if !bytes.Equal(got.StorageRoot, storageRoot) {
		t.Fatalf("storage root: got %x want %x", got.StorageRoot, storageRoot)
	}
}

func TestExtractConsensusStateRejectsOutOfRangeOffsets(t *testing.T) {
	// Union reference: extract_consensus_state performs offset-based reads of
	// timestamp/state root/storage root,
	// https://github.com/unionlabs/union/blob/1bb07590230e/cosmwasm/lightclient/state-lens-ics23-mpt/src/client.rs#L151.
	testCases := []struct {
		name  string
		state ClientState
	}{
		{
			name: "timestamp offset outside data",
			state: ClientState{
				TimestampOffset:   57,
				StateRootOffset:   0,
				StorageRootOffset: 32,
			},
		},
		{
			name: "state root offset outside data",
			state: ClientState{
				TimestampOffset:   0,
				StateRootOffset:   33,
				StorageRootOffset: 32,
			},
		},
		{
			name: "storage root offset outside data",
			state: ClientState{
				TimestampOffset:   0,
				StateRootOffset:   0,
				StorageRootOffset: 33,
			},
		},
	}

	data := make([]byte, 64)
	for _, tc := range testCases {
		t.Run(tc.name, func(t *testing.T) {
			_, err := ExtractConsensusState(data, tc.state)
			if err != ErrConsensusStateTooShort {
				t.Fatalf("ExtractConsensusState: got %v want %v", err, ErrConsensusStateTooShort)
			}
		})
	}
}

func putUint64BE(out []byte, v uint64) {
	out[0] = byte(v >> 56)
	out[1] = byte(v >> 48)
	out[2] = byte(v >> 40)
	out[3] = byte(v >> 32)
	out[4] = byte(v >> 24)
	out[5] = byte(v >> 16)
	out[6] = byte(v >> 8)
	out[7] = byte(v)
}
