package types

import "testing"

func TestKeccak(t *testing.T) {
	tests := []struct {
		name string
		bz   []byte
		want string
	}{
		{
			name: "empty",
			bz:   nil,
			want: "c5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470",
		},
		{
			name: "abc",
			bz:   []byte("abc"),
			want: "4e03657aea45a94fc7d47ba826c8d667c0d1e6e33a64a036ec44f58fa12d6c45",
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			got := keccak(tc.bz)
			assertHex(t, tc.name, got[:], tc.want)
		})
	}
}
