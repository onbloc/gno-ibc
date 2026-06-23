package types

import (
	"testing"
)

func TestKeccak(t *testing.T) {
	tests := []struct {
		name string
		input []byte
		want string
	}{
		{
			name: "empty input",
			input: []byte{},
			want: "c5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470",
		},
		{
			name: "single byte zero",
			input: []byte{0x00},
			want: "bc36789e7a1e281436464229828f817d6612f7b477d66591ff96a9e064bcc98a",
		},
		{
			name: "single byte non-zero",
			input: []byte{0x42},
			want: "1f675bff07515f5df96737194ea945c36c41e7b4fcef307b7cd4d0e602a69111",
		},
		{
			name: "simple ascii",
			input: []byte("abc"),
			want: "4e03657aea45a94fc7d47ba826c8d667c0d1e6e33a64a036ec44f58fa12d6c45",
		},
		{
			name: "longer ascii",
			input: []byte("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq"),
			want: "45d3b367a6904e6e8d502ee04999a7c27647f91fa845d456525fd352ae3d7371",
		},
		{
			name: "hex bytes pattern",
			input: []byte{0xab, 0xcd},
			want: "dbe576b4818846aa77e82f4ed5fa78f92766b141f282d36703886d196df39322",
		},
		{
			name: "all zeros 32 bytes",
			input: make([]byte, 32),
			want: "290decd9548b62a8d60345a988386fc84ba6bc95484008f6362f93160ef3e563",
		},
		{
			name: "all ones 32 bytes",
			input: func() []byte {
				bz := make([]byte, 32)
				for i := range bz {
					bz[i] = 0xff
				}
				return bz
			}(),
			want: "a9c584056064687e149968cbab758a3376d22aedc6a55823d1b3ecbee81b8fb9",
		},
		{
			name: "pattern 0xAA 16 bytes",
			input: func() []byte {
				bz := make([]byte, 16)
				for i := range bz {
					bz[i] = 0xaa
				}
				return bz
			}(),
			want: "8d0a9e4fa3f4029913833f358dd046f87d98750b2782e03bc302c31fee4f2777",
		},
		{
			name: "incrementing bytes",
			input: []byte{0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09},
			want: "f0ae86a6257e615bce8b0fe73794934deda00c13d58f80b466a9354e306c9eb0",
		},
		{
			name: "decrementing bytes",
			input: []byte{0xff, 0xfe, 0xfd, 0xfc, 0xfb, 0xfa, 0xf9, 0xf8},
			want: "4194660100c503cb676584018dc2cf85ab8bbb9190211bd5de1588025867221d",
		},
		{
			name: "repeated byte sequence",
			input: []byte{0x12, 0x34, 0x12, 0x34, 0x12, 0x34, 0x12, 0x34},
			want: "8ab50888cc2f032b242af2cb0110a74a6a8bdabbc8af3d9cc09e7ff2213755fc",
		},
		{
			name: "IBC packet-like data",
			input: []byte{0x00, 0x01, 0x00, 0x02, 0xab, 0xcd, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x03},
			want: "1ab30b41799f2d97d2dc9cf5986cfcb3ff579a9a7d279a0cb069a87e70e55d95",
		},
		{
			name: "64 byte hash input",
			input: func() []byte {
				bz := make([]byte, 64)
				for i := range bz {
					bz[i] = byte(i % 256)
				}
				return bz
			}(),
			want: "002030bde3d4cf89919649775cd71875c4d0ab1708a380e03fefc3a28aa24831",
		},
		{
			name: "single word string",
			input: []byte("test"),
			want: "9c22ff5f21f0b81b113e63f7db6da94fedef11b2119b4088b89664fb9a3cb658",
		},
		{
			name: "keccak256 test vector 1",
			input: []byte{},
			want: "c5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470",
		},
		{
			name: "keccak256 test vector 2",
			input: []byte("abc"),
			want: "4e03657aea45a94fc7d47ba826c8d667c0d1e6e33a64a036ec44f58fa12d6c45",
		},
		{
			name: "keccak256 test vector 3",
			input: []byte("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq"),
			want: "45d3b367a6904e6e8d502ee04999a7c27647f91fa845d456525fd352ae3d7371",
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			got := Keccak(tc.input)
			assertHex(t, tc.name, got[:], tc.want)
		})
	}
}

func TestKeccakInternal(t *testing.T) {
	tests := []struct {
		name string
		input []byte
		want string
	}{
		{
			name: "empty input",
			input: []byte{},
			want: "c5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470",
		},
		{
			name: "single byte",
			input: []byte{0x00},
			want: "bc36789e7a1e281436464229828f817d6612f7b477d66591ff96a9e064bcc98a",
		},
		{
			name: "ascii string",
			input: []byte("test"),
			want: "9c22ff5f21f0b81b113e63f7db6da94fedef11b2119b4088b89664fb9a3cb658",
		},
		{
			name: "hex pattern",
			input: []byte{0xab, 0xcd, 0xef},
			want: "800d501693feda2226878e1ec7869eef8919dbc5bd10c2bcd031b94d73492860",
		},
		{
			name: "32 bytes zeros",
			input: make([]byte, 32),
			want: "290decd9548b62a8d60345a988386fc84ba6bc95484008f6362f93160ef3e563",
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			got := keccak(tc.input)
			assertHex(t, tc.name, got[:], tc.want)
		})
	}
}

func TestKeccakEquivalence(t *testing.T) {
	tests := []struct {
		name string
		input []byte
	}{
		{
			name: "empty",
			input: []byte{},
		},
		{
			name: "single byte",
			input: []byte{0x42},
		},
		{
			name: "multiple bytes",
			input: []byte{0x01, 0x02, 0x03, 0x04, 0x05},
		},
		{
			name: "ascii string",
			input: []byte("hello world"),
		},
		{
			name: "longer bytes",
			input: func() []byte {
				bz := make([]byte, 100)
				for i := range bz {
					bz[i] = byte(i % 256)
				}
				return bz
			}(),
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			exported := Keccak(tc.input)
			internal := keccak(tc.input)

			for i := range exported {
				if exported[i] != internal[i] {
					t.Fatalf("mismatch at byte %d: exported=%x internal=%x", i, exported[i], internal[i])
				}
			}
		})
	}
}
