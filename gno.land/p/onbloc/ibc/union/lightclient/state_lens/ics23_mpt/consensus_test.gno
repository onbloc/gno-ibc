package ics23mpt

import (
	"bytes"
	"testing"

	"gno.land/p/onbloc/verifier/evm/storage"
)

func TestExtractConsensusState(t *testing.T) {
	stateRoot := bytes.Repeat([]byte{0xaa}, 32)
	storageRoot := bytes.Repeat([]byte{0xbb}, 32)
	valid := makeConsensusBytes(77, stateRoot, storageRoot)
	cs := ClientState{
		TimestampOffset:   64,
		StateRootOffset:   0,
		StorageRootOffset: 32,
	}
	tests := []struct {
		name    string
		data    []byte
		cs      ClientState
		wantErr error
	}{
		{name: "success", data: valid, cs: cs},
		{name: "timestamp too short", data: valid[:71], cs: cs, wantErr: ErrConsensusStateTooShort},
		{name: "state root too short", data: valid[:31], cs: ClientState{StateRootOffset: 0}, wantErr: ErrConsensusStateTooShort},
		{name: "storage root too short", data: valid[:63], cs: ClientState{StateRootOffset: 0, StorageRootOffset: 32}, wantErr: ErrConsensusStateTooShort},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got, err := ExtractConsensusState(tt.data, tt.cs)
			if err != tt.wantErr {
				t.Fatalf("ExtractConsensusState error: got %v want %v", err, tt.wantErr)
			}
			if err != nil {
				return
			}
			if got.Timestamp != 77 {
				t.Fatalf("timestamp: got %d want 77", got.Timestamp)
			}
			assertBytes(t, "state root", got.StateRoot, stateRoot)
			assertBytes(t, "storage root", got.StorageRoot, storageRoot)
		})
	}
}

func TestExtractUint64(t *testing.T) {
	tests := []struct {
		name    string
		data    []byte
		offset  int
		want    uint64
		wantErr error
	}{
		{name: "zero offset", data: []byte{0, 0, 0, 0, 0, 0, 0, 5}, offset: 0, want: 5},
		{name: "non-zero offset", data: []byte{0xff, 0xff, 0, 0, 0, 0, 0, 0, 0, 9}, offset: 2, want: 9},
		{name: "negative offset", data: []byte{0, 0, 0, 0, 0, 0, 0, 5}, offset: -1, wantErr: ErrConsensusStateTooShort},
		{name: "short data", data: []byte{0, 0, 0, 0, 0, 0, 0}, offset: 0, wantErr: ErrConsensusStateTooShort},
		{name: "offset exceeds data", data: []byte{0, 0, 0, 0, 0, 0, 0, 5}, offset: 1, wantErr: ErrConsensusStateTooShort},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got, err := extractUint64(tt.data, tt.offset)
			if err != tt.wantErr {
				t.Fatalf("extractUint64 error: got %v want %v", err, tt.wantErr)
			}
			if err != nil {
				return
			}
			if got != tt.want {
				t.Fatalf("extractUint64: got %d want %d", got, tt.want)
			}
		})
	}
}

func TestExtractBytes32(t *testing.T) {
	word := bytes.Repeat([]byte{0xaa}, 32)
	prefixed := append([]byte{0x01, 0x02}, word...)
	tests := []struct {
		name    string
		data    []byte
		offset  int
		want    []byte
		wantErr error
	}{
		{name: "zero offset", data: word, offset: 0, want: word},
		{name: "non-zero offset", data: prefixed, offset: 2, want: word},
		{name: "negative offset", data: word, offset: -1, wantErr: ErrConsensusStateTooShort},
		{name: "short data", data: word[:31], offset: 0, wantErr: ErrConsensusStateTooShort},
		{name: "offset exceeds data", data: prefixed, offset: 3, wantErr: ErrConsensusStateTooShort},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got, err := extractBytes32(tt.data, tt.offset)
			if err != tt.wantErr {
				t.Fatalf("extractBytes32 error: got %v want %v", err, tt.wantErr)
			}
			if err != nil {
				return
			}
			assertBytes(t, "extractBytes32", got, tt.want)
			got[0] ^= 0xff
			if bytes.Equal(got, tt.data[tt.offset:tt.offset+32]) {
				t.Fatalf("extractBytes32 returned an aliased slice")
			}
		})
	}
}

func TestVerifyCommitmentKey(t *testing.T) {
	path := bytes.Repeat([]byte{0x11}, 32)
	slot, err := storage.IBCCommitmentKey(path)
	if err != nil {
		t.Fatalf("IBCCommitmentKey: %v", err)
	}

	tests := []struct {
		name     string
		path     []byte
		proofKey []byte
		wantErr  error
	}{
		{name: "success", path: path, proofKey: slot[:]},
		{name: "invalid path length", path: []byte{0x01}, proofKey: slot[:], wantErr: ErrInvalidCommitmentKey},
		{name: "mismatched proof key", path: path, proofKey: bytes.Repeat([]byte{0x22}, 32), wantErr: ErrInvalidCommitmentKey},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if err := VerifyCommitmentKey(tt.path, tt.proofKey); err != tt.wantErr {
				t.Fatalf("VerifyCommitmentKey: got %v want %v", err, tt.wantErr)
			}
		})
	}
}
