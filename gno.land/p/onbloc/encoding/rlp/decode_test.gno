// Test vectors and cases are based on the following references:
//
//	https://ethereum.org/developers/docs/data-structures-and-encoding/rlp/
package rlp

import (
	"bytes"
	"encoding/hex"
	"testing"
)

func TestDecodeValueEntrypoint(t *testing.T) {
	cases := []struct {
		name string
		data []byte
		want error
	}{
		{"valid single item", mustHex("c88363617483646f67"), nil},
		{"trailing bytes", mustHex("8080"), ErrTrailingBytes},
		{"empty input", nil, ErrUnexpectedEOF},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			v, err := DecodeValue(tc.data)
			if err != tc.want {
				t.Fatalf("DecodeValue error = %v, want %v", err, tc.want)
			}
			if tc.want != nil {
				return
			}
			if v.Kind != KindList || len(v.List) != 2 {
				t.Fatalf("list shape mismatch")
			}
			if string(v.List[0].Bytes) != "cat" || string(v.List[1].Bytes) != "dog" {
				t.Fatalf("list values mismatch")
			}
		})
	}

	t.Run("long string", func(t *testing.T) {
		payload := make([]byte, 56)
		for i := range payload {
			payload[i] = byte(i)
		}
		v, err := DecodeValue(EncodeBytes(payload))
		if err != nil {
			t.Fatalf("DecodeValue long: %v", err)
		}
		if v.Kind != KindString || hex.EncodeToString(v.Bytes) != hex.EncodeToString(payload) {
			t.Fatalf("long string content mismatch")
		}
	})

	t.Run("depth limit", func(t *testing.T) {
		b := EncodeList()
		for i := 0; i < 257; i++ {
			b = EncodeList(b)
		}
		_, err := DecodeValue(b)
		if err != ErrDepthLimit {
			t.Fatalf("ErrDepthLimit: got %v", err)
		}
	})
}

func TestSplit(t *testing.T) {
	cases := []struct {
		name        string
		data        []byte
		wantKind    Kind
		wantContent string
		wantRest    string
		wantErr     error
	}{
		{"single byte with rest", []byte{0x7f, 0x80}, KindByte, "7f", "80", nil},
		{"short string with rest", []byte{0x83, 'd', 'o', 'g', 0x80}, KindString, "646f67", "80", nil},
		{"empty input", nil, 0, "", "", ErrUnexpectedEOF},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			gotKind, gotContent, gotRest, err := split(tc.data)
			if err != tc.wantErr {
				t.Fatalf("split error = %v, want %v", err, tc.wantErr)
			}
			if err != nil {
				return
			}
			if gotKind != tc.wantKind || hex.EncodeToString(gotContent) != tc.wantContent || hex.EncodeToString(gotRest) != tc.wantRest {
				t.Fatalf("split = (%d,%x,%x), want (%d,%s,%s)", gotKind, gotContent, gotRest, tc.wantKind, tc.wantContent, tc.wantRest)
			}
		})
	}
}

func TestDecodeValue(t *testing.T) {
	cases := []struct {
		name     string
		data     []byte
		depth    int
		wantKind Kind
		wantRest string
		wantErr  error
		check    func(*testing.T, Value)
	}{
		{"byte", []byte{0x7f, 0x80}, 0, KindByte, "80", nil, func(t *testing.T, v Value) {
			if string(v.Bytes) != string([]byte{0x7f}) {
				t.Fatalf("byte payload mismatch: %x", v.Bytes)
			}
		}},
		{"list", mustHex("c88363617483646f6780"), 0, KindList, "80", nil, func(t *testing.T, v Value) {
			if len(v.List) != 2 || string(v.List[0].Bytes) != "cat" || string(v.List[1].Bytes) != "dog" {
				t.Fatalf("list values mismatch")
			}
		}},
		{"depth limit", []byte{0xc0}, maxDecodeDepth + 1, 0, "c0", ErrDepthLimit, nil},
		{"child decode error preserves original rest", []byte{0xc2, 0x83, 0x01}, 0, 0, "c28301", ErrValueTooLarge, nil},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			v, rest, err := decodeValue(tc.data, tc.depth)
			if err != tc.wantErr {
				t.Fatalf("decodeValue error = %v, want %v", err, tc.wantErr)
			}
			if hex.EncodeToString(rest) != tc.wantRest {
				t.Fatalf("decodeValue rest = %x, want %s", rest, tc.wantRest)
			}
			if err != nil {
				return
			}
			if v.Kind != tc.wantKind {
				t.Fatalf("decodeValue kind = %d, want %d", v.Kind, tc.wantKind)
			}
			if tc.check != nil {
				tc.check(t, v)
			}
		})
	}
}

func TestReadKind(t *testing.T) {
	cases := []struct {
		name     string
		data     []byte
		wantKind Kind
		wantTag  int
		wantSize int
		wantErr  error
	}{
		{"empty input", nil, 0, 0, 0, ErrUnexpectedEOF},
		{"literal byte", []byte{0x7f}, KindByte, 0, 1, nil},
		{"short string empty", []byte{0x80}, KindString, 1, 0, nil},
		{"short string", []byte{0x83, 'd', 'o', 'g'}, KindString, 1, 3, nil},
		{"single byte encoded as string", []byte{0x81, 0x00}, 0, 0, 0, ErrCanonSize},
		{"short string truncated", []byte{0x83, 0x01, 0x02}, 0, 0, 0, ErrValueTooLarge},
		{"long string", append([]byte{0xb8, 0x38}, bytes.Repeat([]byte{0xaa}, 56)...), KindString, 2, 56, nil},
		{"long string payload truncated", []byte{0xb8, 0x38, 0x01}, 0, 0, 0, ErrValueTooLarge},
		{"short list empty", []byte{0xc0}, KindList, 1, 0, nil},
		{"short list", []byte{0xc1, 0x80}, KindList, 1, 1, nil},
		{"short list truncated", []byte{0xc2, 0x80}, 0, 0, 0, ErrValueTooLarge},
		{"long list", append([]byte{0xf8, 0x38}, bytes.Repeat([]byte{0xc0}, 56)...), KindList, 2, 56, nil},
		{"long list payload truncated", []byte{0xf8, 0x38, 0xc0}, 0, 0, 0, ErrValueTooLarge},
		{"non-canonical long-form string below threshold", append([]byte{0xb8, 0x37}, bytes.Repeat([]byte{0xaa}, 55)...), 0, 0, 0, ErrCanonSize},
		{"non-canonical long-form list below threshold", append([]byte{0xf8, 0x37}, bytes.Repeat([]byte{0xc0}, 55)...), 0, 0, 0, ErrCanonSize},
	}
	for _, tc := range cases {
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
}

func TestReadLongItem(t *testing.T) {
	cases := []struct {
		name     string
		data     []byte
		sizeLen  int
		kind     Kind
		wantKind Kind
		wantTag  int
		wantSize int
		wantErr  error
	}{
		{"valid string", append([]byte{0xb8, 0x38}, bytes.Repeat([]byte{0xaa}, 56)...), 1, KindString, KindString, 2, 56, nil},
		{"valid list", append([]byte{0xf8, 0x38}, bytes.Repeat([]byte{0xc0}, 56)...), 1, KindList, KindList, 2, 56, nil},
		{"size read error", []byte{0xb8}, 1, KindString, 0, 0, 0, ErrUnexpectedEOF},
		{"payload too large", []byte{0xb8, 0x38, 0x01}, 1, KindString, 0, 0, 0, ErrValueTooLarge},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			gotKind, gotTag, gotSize, err := readLongItem(tc.data, tc.sizeLen, tc.kind)
			if err != tc.wantErr {
				t.Fatalf("readLongItem error = %v, want %v", err, tc.wantErr)
			}
			if gotKind != tc.wantKind || gotTag != tc.wantTag || gotSize != tc.wantSize {
				t.Fatalf("readLongItem = (%d,%d,%d), want (%d,%d,%d)", gotKind, gotTag, gotSize, tc.wantKind, tc.wantTag, tc.wantSize)
			}
		})
	}
}

func TestReadSize(t *testing.T) {
	cases := []struct {
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
		{"size exceeds maxInt", []byte{0x80, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00}, 8, 0, ErrValueTooLarge},
	}
	for _, tc := range cases {
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
