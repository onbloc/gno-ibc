// Test vectors and cases are based on the following references:
//
//	https://ethereum.org/developers/docs/data-structures-and-encoding/rlp/
package rlp

import (
	"encoding/hex"
	"testing"
)

func TestEncodeKnownEthereumExamples(t *testing.T) {
	assertHex(t, "dog", EncodeBytes([]byte("dog")), "83646f67")
	assertHex(t, "empty string", EncodeBytes(nil), "80")
	assertHex(t, "empty list", EncodeList(), "c0")
	assertHex(t, "cat dog list", EncodeList(EncodeBytes([]byte("cat")), EncodeBytes([]byte("dog"))), "c88363617483646f67")
	assertHex(t, "zero byte", EncodeBytes([]byte{0x00}), "00")
	assertHex(t, "bytes 0400", EncodeBytes([]byte{0x04, 0x00}), "820400")
	assertHex(t, "set theoretical three", EncodeList(
		EncodeList(),
		EncodeList(EncodeList()),
		EncodeList(EncodeList(), EncodeList(EncodeList())),
	), "c7c0c1c0c3c0c1c0")
	assertHex(t, "lorem long string", EncodeBytes([]byte("Lorem ipsum dolor sit amet, consectetur adipisicing elit")),
		"b8384c6f72656d20697073756d20646f6c6f722073697420616d65742c20636f6e7365637465747572206164697069736963696e6720656c6974")
}

func TestDecodeValue(t *testing.T) {
	v, err := DecodeValue(mustHex("c88363617483646f67"))
	if err != nil {
		t.Fatalf("DecodeValue: %v", err)
	}
	if v.Kind != KindList || len(v.List) != 2 {
		t.Fatalf("list shape mismatch")
	}
	if string(v.List[0].Bytes) != "cat" || string(v.List[1].Bytes) != "dog" {
		t.Fatalf("list values mismatch")
	}
}

func TestCanonicalRejections(t *testing.T) {
	tests := []struct {
		name string
		hex  string
		want error
	}{
		{"single byte encoded as string", "8100", ErrCanonSize},
		{"short string encoded as long", "b80100", ErrCanonSize},
		{"long string size has leading zero", "b800", ErrCanonSize},
		{"short list encoded as long", "f801c0", ErrCanonSize},
		{"long list size has leading zero", "f800", ErrCanonSize},
		{"trailing bytes", "8080", ErrTrailingBytes},
	}
	for _, tc := range tests {
		assertDecodeErr(t, tc.name, mustHex(tc.hex), tc.want)
	}
}

func TestLongPayloads(t *testing.T) {
	payload := make([]byte, 56)
	for i := range payload {
		payload[i] = byte(i)
	}
	encoded := EncodeBytes(payload)
	if len(encoded) != 58 || encoded[0] != 0xb8 || encoded[1] != 56 {
		t.Fatalf("long string header mismatch: %x", encoded[:2])
	}
	v, err := DecodeValue(encoded)
	if err != nil {
		t.Fatalf("DecodeValue long: %v", err)
	}
	if v.Kind != KindString || hex.EncodeToString(v.Bytes) != hex.EncodeToString(payload) {
		t.Fatalf("long string content mismatch")
	}
}

func TestAdditionalErrors(t *testing.T) {
	cases := []struct {
		name string
		data []byte
		want error
	}{
		{"empty input", nil, ErrUnexpectedEOF},
		{"short string truncated", []byte{0x83, 0x01, 0x02}, ErrValueTooLarge},
		{"long string payload truncated", []byte{0xb8, 0x38, 0x01}, ErrValueTooLarge},
		{"short list truncated", []byte{0xc2, 0x80}, ErrValueTooLarge},
		{"long list payload truncated", []byte{0xf8, 0x38, 0xc0}, ErrValueTooLarge},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			_, err := DecodeValue(tc.data)
			if err != tc.want {
				t.Fatalf("DecodeValue error = %v, want %v", err, tc.want)
			}
		})
	}

	b := EncodeList()
	for i := 0; i < 257; i++ {
		b = EncodeList(b)
	}
	_, err := DecodeValue(b)
	if err != ErrDepthLimit {
		t.Fatalf("ErrDepthLimit: got %v", err)
	}
}

func TestEncodeHelperBoundaries(t *testing.T) {
	byteCases := []struct {
		name string
		in   []byte
		want string
	}{
		{"single byte zero stays literal", []byte{0x00}, "00"},
		{"single byte 0x7f stays literal", []byte{0x7f}, "7f"},
		{"single byte 0x80 gets string header", []byte{0x80}, "8180"},
		{"fifty five byte string uses short header", repeatByte(0xaa, 55), "b7" + repeatHex("aa", 55)},
		{"fifty six byte string uses long header", repeatByte(0xaa, 56), "b838" + repeatHex("aa", 56)},
	}
	for _, tc := range byteCases {
		t.Run(tc.name, func(t *testing.T) {
			if got := EncodeBytes(tc.in); hex.EncodeToString(got) != tc.want {
				t.Fatalf("EncodeBytes = %s, want %s", hex.EncodeToString(got), tc.want)
			}
			if got := bytesSize(tc.in); got != len(mustHex(tc.want)) {
				t.Fatalf("bytesSize = %d, want %d", got, len(mustHex(tc.want)))
			}
		})
	}

	headerCases := []struct {
		payload int
		want    int
	}{
		{0, 1},
		{55, 1},
		{56, 2},
		{255, 2},
		{256, 3},
	}
	for _, tc := range headerCases {
		t.Run("headerSize", func(t *testing.T) {
			if got := headerSize(tc.payload); got != tc.want {
				t.Fatalf("headerSize(%d) = %d, want %d", tc.payload, got, tc.want)
			}
		})
	}

	intCases := []struct {
		in   uint64
		want int
	}{
		{0, 1},
		{1<<8 - 1, 1},
		{1 << 8, 2},
		{1 << 16, 3},
		{1 << 24, 4},
		{1 << 32, 5},
		{1 << 40, 6},
		{1 << 48, 7},
		{1 << 56, 8},
	}
	for _, tc := range intCases {
		t.Run("intSize", func(t *testing.T) {
			if got := intSize(tc.in); got != tc.want {
				t.Fatalf("intSize(%d) = %d, want %d", tc.in, got, tc.want)
			}
		})
	}

	appendCases := []struct {
		name string
		x    uint64
		n    int
		want string
	}{
		{"zero bytes", 0xab, 0, ""},
		{"zero one byte", 0, 1, "00"},
		{"one byte", 0xab, 1, "ab"},
		{"eight bytes", 0x0102030405060708, 8, "0102030405060708"},
	}
	for _, tc := range appendCases {
		t.Run(tc.name, func(t *testing.T) {
			got := appendBigEndianUint(nil, tc.x, tc.n)
			if hex.EncodeToString(got) != tc.want {
				t.Fatalf("appendBigEndianUint = %s, want %s", hex.EncodeToString(got), tc.want)
			}
		})
	}
}

func TestDecodeHelperBoundaries(t *testing.T) {
	kindCases := []struct {
		name     string
		data     []byte
		wantKind Kind
		wantTag  int
		wantSize int
		wantErr  error
	}{
		{"literal byte", []byte{0x7f}, KindByte, 0, 1, nil},
		{"short string empty", []byte{0x80}, KindString, 1, 0, nil},
		{"short string", []byte{0x83, 'd', 'o', 'g'}, KindString, 1, 3, nil},
		{"long string", append([]byte{0xb8, 0x38}, repeatByte(0xaa, 56)...), KindString, 2, 56, nil},
		{"short list empty", []byte{0xc0}, KindList, 1, 0, nil},
		{"short list", []byte{0xc1, 0x80}, KindList, 1, 1, nil},
		{"long list", append([]byte{0xf8, 0x38}, repeatByte(0xc0, 56)...), KindList, 2, 56, nil},
	}
	for _, tc := range kindCases {
		t.Run(tc.name, func(t *testing.T) {
			gotKind, gotTag, gotSize, err := readKind(tc.data)
			if err != tc.wantErr {
				t.Fatalf("readKind error = %v, want %v", err, tc.wantErr)
			}
			if gotKind != tc.wantKind || gotTag != tc.wantTag || gotSize != tc.wantSize {
				t.Fatalf("readKind = (%d,%d,%d), want (%d,%d,%d)", gotKind, gotTag, gotSize, tc.wantKind, tc.wantTag, tc.wantSize)
			}
		})
	}

	sizeCases := []struct {
		name    string
		data    []byte
		sizeLen int
		want    int
		wantErr error
	}{
		{"zero sizeLen", []byte{0x38}, 0, 0, ErrUnexpectedEOF},
		{"too large sizeLen", []byte{0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09}, 9, 0, ErrUnexpectedEOF},
		{"truncated size", []byte{0x38}, 2, 0, ErrUnexpectedEOF},
		{"leading zero", []byte{0x00}, 1, 0, ErrCanonSize},
		{"long form below threshold", []byte{0x37}, 1, 0, ErrCanonSize},
		{"valid one byte size", []byte{0x38}, 1, 56, nil},
		{"valid two byte size", []byte{0x01, 0x00}, 2, 256, nil},
	}
	for _, tc := range sizeCases {
		t.Run(tc.name, func(t *testing.T) {
			got, err := readSize(tc.data, tc.sizeLen)
			if err != tc.wantErr {
				t.Fatalf("readSize error = %v, want %v", err, tc.wantErr)
			}
			if got != tc.want {
				t.Fatalf("readSize = %d, want %d", got, tc.want)
			}
		})
	}
}

func assertHex(t *testing.T, name string, got []byte, want string) {
	t.Helper()
	if hex.EncodeToString(got) != want {
		t.Fatalf("%s: got %x want %s", name, got, want)
	}
}

func assertDecodeErr(t *testing.T, name string, data []byte, want error) {
	t.Helper()
	_, err := DecodeValue(data)
	if err != want {
		t.Fatalf("%s: got %v want %v", name, err, want)
	}
}

func mustHex(s string) []byte {
	bz, err := hex.DecodeString(s)
	if err != nil {
		panic(err)
	}
	return bz
}

func repeatByte(b byte, n int) []byte {
	out := make([]byte, n)
	for i := range out {
		out[i] = b
	}
	return out
}

func repeatHex(s string, n int) string {
	out := ""
	for i := 0; i < n; i++ {
		out += s
	}
	return out
}
