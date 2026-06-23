package cometbls

import "testing"

func TestChainIDToString(t *testing.T) {
	cases := []struct {
		name string
		src  []byte
		want string
	}{
		{"plain", []byte("union-testnet-9"), "union-testnet-9"},
		{"leading zero padding", []byte{0, 0, 'u', 'n', 'i', 'o', 'n'}, "union"},
		{"middle zero preserved", []byte{'a', 0, 'b'}, string([]byte{'a', 0, 'b'})},
		{"max length exactly", repeatBytes('x', maxChainIDLen), string(repeatBytes('x', maxChainIDLen))},
		{"special chars", []byte("chain-123_abc"), "chain-123_abc"},
		{"numeric only", []byte("12345"), "12345"},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got, err := chainIdToString(tc.src)
			if err != nil {
				t.Fatalf("chainIdToString: %v", err)
			}
			if got != tc.want {
				t.Fatalf("chainIdToString: got %q want %q", got, tc.want)
			}
		})
	}
}

func TestChainIDToStringRejectsInvalidInput(t *testing.T) {
	cases := []struct {
		name string
		src  []byte
		want string
	}{
		{"empty", nil, "empty source"},
		{"too long", repeatBytes('x', maxChainIDLen+1), "source exceeds max length"},
		{"all zero", make([]byte, maxChainIDLen), "source is all zero padding"},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			_, err := chainIdToString(tc.src)
			requireErrorContains(t, err, tc.want)
		})
	}
}
