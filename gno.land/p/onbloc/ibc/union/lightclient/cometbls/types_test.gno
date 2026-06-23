package cometbls

import (
	"testing"
)

func TestMerkleRootGetHash(t *testing.T) {
	tests := []struct {
		name     string
		input    MerkleRoot
		expected []byte
	}{
		{
			name:     "empty hash returns nil",
			input:    MerkleRoot{Hash: nil},
			expected: nil,
		},
		{
			name:     "empty slice returns empty slice",
			input:    MerkleRoot{Hash: []byte{}},
			expected: []byte{},
		},
		{
			name:     "non-empty hash returns same hash",
			input:    MerkleRoot{Hash: []byte{1, 2, 3, 4}},
			expected: []byte{1, 2, 3, 4},
		},
		{
			name: "32 byte hash returns same hash",
			input: MerkleRoot{Hash: []byte{
				0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15,
				16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31,
			}},
			expected: []byte{
				0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15,
				16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31,
			},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := tt.input.GetHash()
			if len(result) != len(tt.expected) {
				t.Errorf("expected length %d, got %d", len(tt.expected), len(result))
			}
			for i := range tt.expected {
				if result[i] != tt.expected[i] {
					t.Errorf("byte %d: expected %d, got %d", i, tt.expected[i], result[i])
				}
			}
		})
	}
}

func TestMerkleRootEmptyTypes(t *testing.T) {
	tests := []struct {
		name     string
		input    MerkleRoot
		expected bool
	}{
		{
			name:     "nil hash returns true",
			input:    MerkleRoot{Hash: nil},
			expected: true,
		},
		{
			name:     "empty slice returns true",
			input:    MerkleRoot{Hash: []byte{}},
			expected: true,
		},
		{
			name:     "single byte returns false",
			input:    MerkleRoot{Hash: []byte{0}},
			expected: false,
		},
		{
			name:     "non-empty byte returns false",
			input:    MerkleRoot{Hash: []byte{1, 2, 3}},
			expected: false,
		},
		{
			name: "32 byte hash returns false",
			input: MerkleRoot{Hash: []byte{
				0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15,
				16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31,
			}},
			expected: false,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := tt.input.Empty()
			if result != tt.expected {
				t.Errorf("expected %v, got %v", tt.expected, result)
			}
		})
	}
}

func TestValidateHash(t *testing.T) {
	tests := []struct {
		name        string
		input       []byte
		expectError bool
		errorSubstr string // substring expected in error message
	}{
		{
			name:        "nil hash returns nil",
			input:       nil,
			expectError: false,
		},
		{
			name:        "empty slice returns nil",
			input:       []byte{},
			expectError: false,
		},
		{
			name:        "32 byte hash returns nil",
			input:       make([]byte, 32),
			expectError: false,
		},
		{
			name:        "31 byte hash returns error",
			input:       make([]byte, 31),
			expectError: true,
			errorSubstr: "expected size to be 32 bytes, got 31 bytes",
		},
		{
			name:        "33 byte hash returns error",
			input:       make([]byte, 33),
			expectError: true,
			errorSubstr: "expected size to be 32 bytes, got 33 bytes",
		},
		{
			name:        "1 byte hash returns error",
			input:       []byte{0},
			expectError: true,
			errorSubstr: "expected size to be 32 bytes, got 1 bytes",
		},
		{
			name:        "16 byte hash returns error",
			input:       make([]byte, 16),
			expectError: true,
			errorSubstr: "expected size to be 32 bytes, got 16 bytes",
		},
		{
			name:        "64 byte hash returns error",
			input:       make([]byte, 64),
			expectError: true,
			errorSubstr: "expected size to be 32 bytes, got 64 bytes",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			err := validateHash(tt.input)
			if tt.expectError {
				if err == nil {
					t.Errorf("expected error containing %q, got nil", tt.errorSubstr)
				} else if tt.errorSubstr != "" && err.Error() != tt.errorSubstr {
					t.Errorf("expected error %q, got %q", tt.errorSubstr, err.Error())
				}
			} else {
				if err != nil {
					t.Errorf("expected nil error, got %v", err)
				}
			}
		})
	}
}
