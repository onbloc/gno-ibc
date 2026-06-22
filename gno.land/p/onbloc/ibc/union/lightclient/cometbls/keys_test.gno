package cometbls

import (
	"testing"

	"gno.land/p/onbloc/ibc/union/types"
)

func TestMakeStoreKey(t *testing.T) {
	var addr H256
	for i := 0; i < len(addr); i++ {
		addr[i] = byte(i + 1)
	}
	key := []byte("packet-commitment")

	got := makeStoreKey(addr, key)

	if len(got) != 1+len(addr)+1+len(key) {
		t.Fatalf("length: got %d want %d", len(got), 1+len(addr)+1+len(key))
	}
	if got[0] != 0x03 {
		t.Fatalf("prefix: got %x want 03", got[0])
	}
	bytesEq(t, "address segment", got[1:33], addr[:])
	if got[33] != 0x00 {
		t.Fatalf("separator: got %x want 00", got[33])
	}
	bytesEq(t, "key segment", got[34:], key)
}

func TestMakeStoreKeyEmptyKey(t *testing.T) {
	var addr H256
	addr[31] = 0xff

	got := makeStoreKey(addr, nil)

	if len(got) != 34 {
		t.Fatalf("length: got %d want 34", len(got))
	}
	if got[0] != 0x03 || got[33] != 0x00 {
		t.Fatalf("framing: got prefix %x separator %x", got[0], got[33])
	}
	bytesEq(t, "address segment", got[1:33], addr[:])
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

func TestHeightKeyLexicographicWidth(t *testing.T) {
	got := heightKey(types.Height{RevisionNumber: 2, RevisionHeight: 10})
	want := "00000000000000000002-00000000000000000010"
	if got != want {
		t.Fatalf("heightKey: got %q want %q", got, want)
	}
}
