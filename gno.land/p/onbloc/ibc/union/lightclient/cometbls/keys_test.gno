package cometbls

import (
	"testing"

	"gno.land/p/onbloc/ibc/union/types"
)

func TestMakeStoreKey(t *testing.T) {
	var standardAddr H256
	for i := 0; i < len(standardAddr); i++ {
		standardAddr[i] = byte(i + 1)
	}
	longKey := make([]byte, 100)
	for i := range longKey {
		longKey[i] = byte(i)
	}

	cases := []struct {
		name string
		addr H256
		key  []byte
	}{
		{"standard case", standardAddr, []byte("packet-commitment")},
		{"zero address", H256{}, []byte("test-key")},
		{"long key", H256{}, longKey},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got := makeStoreKey(tc.addr, tc.key)

			if len(got) != 1+len(tc.addr)+1+len(tc.key) {
				t.Fatalf("length: got %d want %d", len(got), 1+len(tc.addr)+1+len(tc.key))
			}
			if got[0] != 0x03 {
				t.Fatalf("prefix: got %x want 03", got[0])
			}
			bytesEq(t, "address segment", got[1:33], tc.addr[:])
			if got[33] != 0x00 {
				t.Fatalf("separator: got %x want 00", got[33])
			}
			bytesEq(t, "key segment", got[34:], tc.key)
		})
	}
}

func TestMakeStoreKeyEmptyKey(t *testing.T) {
	cases := []struct {
		name string
		addr H256
		key  []byte
	}{
		{"nil key", H256{}, nil},
		{"empty key", H256{}, []byte{}},
	}
	cases[0].addr[31] = 0xff
	cases[1].addr[31] = 0xff

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got := makeStoreKey(tc.addr, tc.key)

			if len(got) != 34 {
				t.Fatalf("length: got %d want 34", len(got))
			}
			if got[0] != 0x03 || got[33] != 0x00 {
				t.Fatalf("framing: got prefix %x separator %x", got[0], got[33])
			}
			bytesEq(t, "address segment", got[1:33], tc.addr[:])
			bytesEq(t, "key segment", got[34:], tc.key)
		})
	}
}

func TestHeightKey_LexicographicWidth(t *testing.T) {
	cases := []struct {
		name       string
		height     types.Height
		want       string
		wantLength int
	}{
		{
			name:   "standard height",
			height: types.Height{RevisionNumber: 2, RevisionHeight: 10},
			want:   "00000000000000000002-00000000000000000010",
		},
		{
			name:   "zero height",
			height: types.Height{RevisionNumber: 0, RevisionHeight: 0},
			want:   "00000000000000000000-00000000000000000000",
		},
		{
			name:       "max values",
			height:     types.Height{RevisionNumber: ^uint64(0), RevisionHeight: ^uint64(0)},
			wantLength: 41,
		},
		{
			name:   "single digit values",
			height: types.Height{RevisionNumber: 1, RevisionHeight: 1},
			want:   "00000000000000000001-00000000000000000001",
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got := heightKey(tc.height)
			if tc.want != "" && got != tc.want {
				t.Fatalf("heightKey: got %q want %q", got, tc.want)
			}
			if tc.wantLength != 0 && len(got) != tc.wantLength {
				t.Fatalf("heightKey length: got %d want %d", len(got), tc.wantLength)
			}
		})
	}
}

func TestZeroPadDecimalUint64(t *testing.T) {
	cases := []struct {
		name string
		num  uint64
		want string
	}{
		{"zero", 0, "00000000000000000000"},
		{"one", 1, "00000000000000000001"},
		{"nineteen digits", 9999999999999999999, "09999999999999999999"},
		{"twenty digits", 10000000000000000000, "10000000000000000000"},
		{"max", ^uint64(0), "18446744073709551615"},
		{"boundary before overflow", 18446744073709551615, "18446744073709551615"},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got := zeroPadDecimalUint64(tc.num)
			if got != tc.want {
				t.Fatalf("zeroPadDecimalUint64(%d): got %q want %q", tc.num, got, tc.want)
			}
			if len(got) != 20 {
				t.Fatalf("zeroPadDecimalUint64(%d): length got %d want 20", tc.num, len(got))
			}
		})
	}
}
