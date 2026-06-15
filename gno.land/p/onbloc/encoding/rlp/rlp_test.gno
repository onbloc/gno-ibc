package rlp

import (
	"encoding/hex"
	"testing"
)

func TestEncodeKnownEthereumExamples(t *testing.T) {
	// Vectors from ethereum.org's RLP examples:
	// https://ethereum.org/developers/docs/data-structures-and-encoding/rlp/#examples
	assertHex(t, "dog", EncodeString("dog"), "83646f67")
	assertHex(t, "empty string", EncodeBytes(nil), "80")
	assertHex(t, "empty list", EncodeList(), "c0")
	assertHex(t, "cat dog list", EncodeList(EncodeString("cat"), EncodeString("dog")), "c88363617483646f67")
	assertHex(t, "zero", EncodeUint64(0), "80")
	assertHex(t, "zero byte", EncodeBytes([]byte{0x00}), "00")
	assertHex(t, "fifteen", EncodeUint64(15), "0f")
	assertHex(t, "bytes 0400", EncodeBytes([]byte{0x04, 0x00}), "820400")
	assertHex(t, "set theoretical three", EncodeList(
		EncodeList(),
		EncodeList(EncodeList()),
		EncodeList(EncodeList(), EncodeList(EncodeList())),
	), "c7c0c1c0c3c0c1c0")
	assertHex(t, "lorem long string", EncodeString("Lorem ipsum dolor sit amet, consectetur adipisicing elit"),
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

	round := EncodeValue(v)
	assertHex(t, "roundtrip", round, "c88363617483646f67")
}

func TestSplitHelpers(t *testing.T) {
	b := append(EncodeString("dog"), EncodeUint64(1024)...)
	content, rest, err := SplitString(b)
	if err != nil {
		t.Fatalf("SplitString: %v", err)
	}
	if string(content) != "dog" {
		t.Fatalf("content: got %q", string(content))
	}
	x, rest, err := SplitUint64(rest)
	if err != nil {
		t.Fatalf("SplitUint64: %v", err)
	}
	if x != 1024 || len(rest) != 0 {
		t.Fatalf("uint/rest mismatch: %d/%d", x, len(rest))
	}

	values, err := SplitListValues(EncodeList(EncodeUint64(1), EncodeUint64(2), EncodeUint64(3)))
	if err != nil {
		t.Fatalf("SplitListValues: %v", err)
	}
	if len(values) != 3 || hex.EncodeToString(values[2]) != "03" {
		t.Fatalf("values mismatch")
	}
}

func TestCanonicalRejections(t *testing.T) {
	assertDecodeErr(t, "single byte encoded as string", mustHex("8100"), ErrCanonSize)
	assertDecodeErr(t, "short string encoded as long", mustHex("b80100"), ErrCanonSize)
	assertDecodeErr(t, "trailing bytes", mustHex("8080"), ErrTrailingBytes)

	_, _, err := SplitUint64(mustHex("820001"))
	if err != ErrCanonInt {
		t.Fatalf("SplitUint64 canonical integer error: got %v", err)
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
	content, rest, err := SplitString(encoded)
	if err != nil {
		t.Fatalf("SplitString long: %v", err)
	}
	if len(rest) != 0 || hex.EncodeToString(content) != hex.EncodeToString(payload) {
		t.Fatalf("long string content mismatch")
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
