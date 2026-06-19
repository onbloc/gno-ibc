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
	_, err := DecodeValue(nil)
	if err != ErrUnexpectedEOF {
		t.Fatalf("DecodeValue nil: got %v, want ErrUnexpectedEOF", err)
	}

	_, err = DecodeValue([]byte{0x83, 0x01, 0x02})
	if err != ErrValueTooLarge {
		t.Fatalf("DecodeValue truncated: got %v, want ErrValueTooLarge", err)
	}

	b := EncodeList()
	for i := 0; i < 257; i++ {
		b = EncodeList(b)
	}
	_, err = DecodeValue(b)
	if err != ErrDepthLimit {
		t.Fatalf("ErrDepthLimit: got %v", err)
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
