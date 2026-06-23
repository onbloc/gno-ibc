package types

import "testing"

func TestNewConsensusStateUpdate(t *testing.T) {
	tests := []struct {
		name                string
		height              Height
		consensusStateBytes []byte
		clientStateBytes    []byte
		wantHeight          Height
		wantConsensusBytes  []byte
		wantClientBytes     []byte
	}{
		{
			name:                "all fields with simple height",
			height:              NewHeight(100),
			consensusStateBytes: []byte{0x01, 0x02, 0x03},
			clientStateBytes:    []byte{0x04, 0x05, 0x06},
			wantHeight:          NewHeight(100),
			wantConsensusBytes:  []byte{0x01, 0x02, 0x03},
			wantClientBytes:     []byte{0x04, 0x05, 0x06},
		},
		{
			name:                "all fields with revision height",
			height:              NewHeightWithRevision(1, 50),
			consensusStateBytes: []byte{0xaa, 0xbb},
			clientStateBytes:    []byte{0xcc, 0xdd},
			wantHeight:          NewHeightWithRevision(1, 50),
			wantConsensusBytes:  []byte{0xaa, 0xbb},
			wantClientBytes:     []byte{0xcc, 0xdd},
		},
		{
			name:                "zero height",
			height:              NewHeight(0),
			consensusStateBytes: []byte{0x01},
			clientStateBytes:    []byte{0x02},
			wantHeight:          NewHeight(0),
			wantConsensusBytes:  []byte{0x01},
			wantClientBytes:     []byte{0x02},
		},
		{
			name:                "empty consensus state bytes",
			height:              NewHeight(10),
			consensusStateBytes: []byte{},
			clientStateBytes:    []byte{0x01},
			wantHeight:          NewHeight(10),
			wantConsensusBytes:  []byte{},
			wantClientBytes:     []byte{0x01},
		},
		{
			name:                "empty client state bytes",
			height:              NewHeight(20),
			consensusStateBytes: []byte{0x01},
			clientStateBytes:    []byte{},
			wantHeight:          NewHeight(20),
			wantConsensusBytes:  []byte{0x01},
			wantClientBytes:     []byte{},
		},
		{
			name:                "both byte arrays empty",
			height:              NewHeight(30),
			consensusStateBytes: []byte{},
			clientStateBytes:    []byte{},
			wantHeight:          NewHeight(30),
			wantConsensusBytes:  []byte{},
			wantClientBytes:     []byte{},
		},
		{
			name:                "large byte arrays",
			height:              NewHeight(9999),
			consensusStateBytes: []byte{0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09},
			clientStateBytes:    []byte{0xff, 0xfe, 0xfd, 0xfc, 0xfb, 0xfa, 0xf9, 0xf8, 0xf7, 0xf6},
			wantHeight:          NewHeight(9999),
			wantConsensusBytes:  []byte{0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09},
			wantClientBytes:     []byte{0xff, 0xfe, 0xfd, 0xfc, 0xfb, 0xfa, 0xf9, 0xf8, 0xf7, 0xf6},
		},
		{
			name:                "max revision and height values",
			height:              NewHeightWithRevision(18446744073709551615, 18446744073709551615),
			consensusStateBytes: []byte{0xde, 0xad},
			clientStateBytes:    []byte{0xbe, 0xef},
			wantHeight:          NewHeightWithRevision(18446744073709551615, 18446744073709551615),
			wantConsensusBytes:  []byte{0xde, 0xad},
			wantClientBytes:     []byte{0xbe, 0xef},
		},
		{
			name:                "single byte consensus state",
			height:              NewHeight(5),
			consensusStateBytes: []byte{0xff},
			clientStateBytes:    []byte{0xee, 0xdd},
			wantHeight:          NewHeight(5),
			wantConsensusBytes:  []byte{0xff},
			wantClientBytes:     []byte{0xee, 0xdd},
		},
		{
			name:                "single byte client state",
			height:              NewHeight(7),
			consensusStateBytes: []byte{0xaa, 0xbb},
			clientStateBytes:    []byte{0xcc},
			wantHeight:          NewHeight(7),
			wantConsensusBytes:  []byte{0xaa, 0xbb},
			wantClientBytes:     []byte{0xcc},
		},
		{
			name:                "nil consensus state bytes",
			height:              NewHeight(42),
			consensusStateBytes: nil,
			clientStateBytes:    []byte{0x01},
			wantHeight:          NewHeight(42),
			wantConsensusBytes:  nil,
			wantClientBytes:     []byte{0x01},
		},
		{
			name:                "nil client state bytes",
			height:              NewHeight(43),
			consensusStateBytes: []byte{0x01},
			clientStateBytes:    nil,
			wantHeight:          NewHeight(43),
			wantConsensusBytes:  []byte{0x01},
			wantClientBytes:     nil,
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			got := NewConsensusStateUpdate(tc.height, tc.consensusStateBytes, tc.clientStateBytes)

			if got.Height != tc.wantHeight {
				t.Errorf("Height: got %v want %v", got.Height, tc.wantHeight)
			}

			if !equalBytes(got.ConsensusStateBytes, tc.wantConsensusBytes) {
				t.Errorf("ConsensusStateBytes: got %x want %x", got.ConsensusStateBytes, tc.wantConsensusBytes)
			}

			if !equalBytes(got.ClientStateBytes, tc.wantClientBytes) {
				t.Errorf("ClientStateBytes: got %x want %x", got.ClientStateBytes, tc.wantClientBytes)
			}
		})
	}
}

func equalBytes(a, b []byte) bool {
	if len(a) != len(b) {
		return false
	}
	for i := range a {
		if a[i] != b[i] {
			return false
		}
	}
	return true
}
