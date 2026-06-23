package types

import "testing"

func TestClientIdString(t *testing.T) {
	tests := []struct {
		name string
		id   ClientId
		want string
	}{
		{
			name: "zero id",
			id:   0,
			want: "0",
		},
		{
			name: "single digit id",
			id:   5,
			want: "5",
		},
		{
			name: "double digit id",
			id:   42,
			want: "42",
		},
		{
			name: "large id",
			id:   1234567,
			want: "1234567",
		},
		{
			name: "max uint32 id",
			id:   4294967295,
			want: "4294967295",
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			got := tc.id.String()
			if got != tc.want {
				t.Fatalf("ClientId(%v).String() = %q, want %q", tc.id, got, tc.want)
			}
		})
	}
}

func TestConnectionIdString(t *testing.T) {
	tests := []struct {
		name string
		id   ConnectionId
		want string
	}{
		{
			name: "zero id",
			id:   0,
			want: "0",
		},
		{
			name: "single digit id",
			id:   1,
			want: "1",
		},
		{
			name: "double digit id",
			id:   99,
			want: "99",
		},
		{
			name: "large id",
			id:   987654,
			want: "987654",
		},
		{
			name: "max uint32 id",
			id:   4294967295,
			want: "4294967295",
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			got := tc.id.String()
			if got != tc.want {
				t.Fatalf("ConnectionId(%v).String() = %q, want %q", tc.id, got, tc.want)
			}
		})
	}
}

func TestTimestampString(t *testing.T) {
	tests := []struct {
		name string
		ts   Timestamp
		want string
	}{
		{
			name: "zero timestamp",
			ts:   0,
			want: "0",
		},
		{
			name: "single digit timestamp",
			ts:   1,
			want: "1",
		},
		{
			name: "double digit timestamp",
			ts:   50,
			want: "50",
		},
		{
			name: "large timestamp",
			ts:   1719876543,
			want: "1719876543",
		},
		{
			name: "max uint64 timestamp",
			ts:   18446744073709551615,
			want: "18446744073709551615",
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			got := tc.ts.String()
			if got != tc.want {
				t.Fatalf("Timestamp(%v).String() = %q, want %q", tc.ts, got, tc.want)
			}
		})
	}
}

func TestBytesString(t *testing.T) {
	tests := []struct {
		name string
		bz   Bytes
		want string
	}{
		{
			name: "empty bytes",
			bz:   Bytes{},
			want: "0x",
		},
		{
			name: "single zero byte",
			bz:   Bytes{0x00},
			want: "0x00",
		},
		{
			name: "single non-zero byte",
			bz:   Bytes{0xff},
			want: "0xff",
		},
		{
			name: "multiple bytes",
			bz:   Bytes{0x01, 0x02, 0x03, 0x04},
			want: "0x01020304",
		},
		{
			name: "full byte range",
			bz:   Bytes{0x00, 0x01, 0x0f, 0x10, 0xff, 0xaa, 0x55},
			want: "0x00010f10ffaa55",
		},
		{
			name: "32 bytes (hash length)",
			bz:   mustBytes(t, "0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f20"),
			want: "0x0102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f20",
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			got := tc.bz.String()
			if got != tc.want {
				t.Fatalf("Bytes(%v).String() = %q, want %q", tc.bz, got, tc.want)
			}
		})
	}
}

func TestBytesBytes(t *testing.T) {
	tests := []struct {
		name string
		bz   Bytes
		want []byte
	}{
		{
			name: "empty bytes",
			bz:   Bytes{},
			want: []byte{},
		},
		{
			name: "single zero byte",
			bz:   Bytes{0x00},
			want: []byte{0x00},
		},
		{
			name: "single non-zero byte",
			bz:   Bytes{0x42},
			want: []byte{0x42},
		},
		{
			name: "multiple bytes",
			bz:   Bytes{0x01, 0x02, 0x03, 0x04},
			want: []byte{0x01, 0x02, 0x03, 0x04},
		},
		{
			name: "full byte range",
			bz:   Bytes{0x00, 0xff, 0x55, 0xaa},
			want: []byte{0x00, 0xff, 0x55, 0xaa},
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			got := tc.bz.Bytes()
			if len(got) != len(tc.want) {
				t.Fatalf("Bytes(%v).Bytes() length = %d, want %d", tc.bz, len(got), len(tc.want))
			}
			for i := range got {
				if got[i] != tc.want[i] {
					t.Fatalf("Bytes(%v).Bytes()[%d] = %d, want %d", tc.bz, i, got[i], tc.want[i])
				}
			}
		})
	}
}

func TestBytesClone(t *testing.T) {
	tests := []struct {
		name string
		bz   Bytes
	}{
		{
			name: "empty bytes",
			bz:   Bytes{},
		},
		{
			name: "single byte",
			bz:   Bytes{0x42},
		},
		{
			name: "multiple bytes",
			bz:   Bytes{0x01, 0x02, 0x03, 0x04},
		},
		{
			name: "32 bytes (hash length)",
			bz:   mustBytes(t, "aa11111111111111111111111111111111111111111111111111111111111111"),
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			original := make(Bytes, len(tc.bz))
			copy(original, tc.bz)

			cloned := tc.bz.Clone()

			// Verify clone has same content
			if len(cloned) != len(tc.bz) {
				t.Fatalf("Clone() length = %d, want %d", len(cloned), len(tc.bz))
			}
			for i := range cloned {
				if cloned[i] != tc.bz[i] {
					t.Fatalf("Clone()[%d] = %d, want %d", i, cloned[i], tc.bz[i])
				}
			}

			// Verify independence: modify clone and check original unchanged
			if len(cloned) > 0 {
				cloned[0] = cloned[0] ^ 0xff // flip all bits
				if tc.bz[0] != original[0] {
					t.Fatal("modifying clone changed original Bytes")
				}
			}
		})
	}
}

func TestH256String(t *testing.T) {
	tests := []struct {
		name string
		h    H256
		want string
	}{
		{
			name: "zero hash",
			h:    H256{},
			want: "0x0000000000000000000000000000000000000000000000000000000000000000",
		},
		{
			name: "hash with single non-zero byte at start",
			h:    mustH256(t, "0100000000000000000000000000000000000000000000000000000000000000"),
			want: "0x0100000000000000000000000000000000000000000000000000000000000000",
		},
		{
			name: "hash with single non-zero byte at end",
			h:    mustH256(t, "0000000000000000000000000000000000000000000000000000000000000001"),
			want: "0x0000000000000000000000000000000000000000000000000000000000000001",
		},
		{
			name: "hash with alternating bytes",
			h:    mustH256(t, "aa11111111111111111111111111111111111111111111111111111111111111"),
			want: "0xaa11111111111111111111111111111111111111111111111111111111111111",
		},
		{
			name: "hash with all ff bytes",
			h:    mustH256(t, "ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"),
			want: "0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff",
		},
		{
			name: "hash with mixed bytes",
			h:    mustH256(t, "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"),
			want: "0x0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			got := tc.h.String()
			if got != tc.want {
				t.Fatalf("H256{}.String() = %q, want %q", got, tc.want)
			}
		})
	}
}

func TestClientTypeString(t *testing.T) {
	tests := []struct {
		name string
		ct   ClientType
		want string
	}{
		{
			name: "empty client type",
			ct:   "",
			want: "",
		},
		{
			name: "simple client type",
			ct:   "07-tendermint",
			want: "07-tendermint",
		},
		{
			name: "another client type",
			ct:   "05-cosmos",
			want: "05-cosmos",
		},
		{
			name: "client type with numbers",
			ct:   "solomachine-123",
			want: "solomachine-123",
		},
		{
			name: "client type with special chars",
			ct:   "client-type-v1",
			want: "client-type-v1",
		},
		{
			name: "long client type",
			ct:   "very-long-client-type-name-with-many-parts-12345",
			want: "very-long-client-type-name-with-many-parts-12345",
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			got := tc.ct.String()
			if got != tc.want {
				t.Fatalf("ClientType(%q).String() = %q, want %q", tc.ct, got, tc.want)
			}
		})
	}
}
