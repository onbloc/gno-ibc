package types

import (
	"bytes"
	"testing"
)

func TestWrapABIEncode(t *testing.T) {
	tests := []struct {
		name    string
		encoded []byte
		want    string
	}{
		{
			name:    "empty dynamic payload",
			encoded: nil,
			want:    "0000000000000000000000000000000000000000000000000000000000000020",
		},
		{
			name:    "payload appended after top-level offset",
			encoded: []byte{0x12, 0x34},
			want:    "00000000000000000000000000000000000000000000000000000000000000201234",
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			got := wrapABIEncode(tc.encoded)
			assertHex(t, tc.name, got, tc.want)
		})
	}
}

func TestEncodeABIPacketArray(t *testing.T) {
	packet := Packet{
		SourceChannelId:      1,
		DestinationChannelId: 2,
		Data:                 []byte{0xab, 0xcd},
		TimeoutTimestamp:     3,
	}
	packetEncoded, err := packet.EncodeABI()
	if err != nil {
		t.Fatalf("encode packet fixture: %v", err)
	}

	tests := []struct {
		name    string
		packets []Packet
		want    []byte
	}{
		{
			name:    "empty",
			packets: nil,
			want:    mustBytes(t, "0000000000000000000000000000000000000000000000000000000000000000"),
		},
		{
			name:    "single packet",
			packets: []Packet{packet},
			want: append(
				mustBytes(t, "00000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000020"),
				packetEncoded...,
			),
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			got, err := encodeABIPacketArray(tc.packets)
			if err != nil {
				t.Fatalf("encodeABIPacketArray error: %v", err)
			}
			if !bytes.Equal(got, tc.want) {
				t.Fatalf("%s: got %x want %x", tc.name, got, tc.want)
			}
		})
	}
}

func TestEncodeABIBytesArray(t *testing.T) {
	tests := []struct {
		name  string
		items [][]byte
		want  string
	}{
		{
			name:  "empty",
			items: nil,
			want:  "0000000000000000000000000000000000000000000000000000000000000000",
		},
		{
			name:  "two byte arrays",
			items: [][]byte{{0xaa}, nil},
			want: "0000000000000000000000000000000000000000000000000000000000000002" +
				"0000000000000000000000000000000000000000000000000000000000000040" +
				"0000000000000000000000000000000000000000000000000000000000000080" +
				"0000000000000000000000000000000000000000000000000000000000000001" +
				"aa00000000000000000000000000000000000000000000000000000000000000" +
				"0000000000000000000000000000000000000000000000000000000000000000",
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			got := encodeABIBytesArray(tc.items)
			assertHex(t, tc.name, got, tc.want)
		})
	}
}

func TestEncodeABIBytes(t *testing.T) {
	tests := []struct {
		name string
		bz   []byte
		want string
	}{
		{
			name: "empty",
			bz:   nil,
			want: "0000000000000000000000000000000000000000000000000000000000000000",
		},
		{
			name: "short value is right padded",
			bz:   []byte{0x12, 0x34},
			want: "0000000000000000000000000000000000000000000000000000000000000002" +
				"1234000000000000000000000000000000000000000000000000000000000000",
		},
		{
			name: "full word has no extra padding",
			bz: mustBytes(t,
				"000102030405060708090a0b0c0d0e0f"+
					"101112131415161718191a1b1c1d1e1f",
			),
			want: "0000000000000000000000000000000000000000000000000000000000000020" +
				"000102030405060708090a0b0c0d0e0f" +
				"101112131415161718191a1b1c1d1e1f",
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			got := encodeABIBytes(tc.bz)
			assertHex(t, tc.name, got, tc.want)
		})
	}
}

func TestU32ToH256(t *testing.T) {
	tests := []struct {
		name string
		n    uint32
		want string
	}{
		{
			name: "zero",
			n:    0,
			want: "0000000000000000000000000000000000000000000000000000000000000000",
		},
		{
			name: "big endian low word",
			n:    0x01020304,
			want: "0000000000000000000000000000000000000000000000000000000001020304",
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			got := u32ToH256(tc.n)
			assertHex(t, tc.name, got, tc.want)
		})
	}
}

func TestU64ToH256(t *testing.T) {
	tests := []struct {
		name string
		n    uint64
		want string
	}{
		{
			name: "zero",
			n:    0,
			want: "0000000000000000000000000000000000000000000000000000000000000000",
		},
		{
			name: "big endian low word",
			n:    0x0102030405060708,
			want: "0000000000000000000000000000000000000000000000000102030405060708",
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			got := u64ToH256(tc.n)
			assertHex(t, tc.name, got, tc.want)
		})
	}
}
