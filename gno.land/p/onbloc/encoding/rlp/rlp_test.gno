// Test vectors and cases are based on the following references:
//   https://ethereum.org/developers/docs/data-structures-and-encoding/rlp/
//   https://github.com/ethereum/go-ethereum/blob/8c540cb082bf60a4260c2fef8ea30375c802e7f7/rlp/raw_test.go
package rlp

import (
	"encoding/hex"
	"testing"
)

func TestEncodeKnownEthereumExamples(t *testing.T) {
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

func TestSplitString(t *testing.T) {
	content, rest, err := SplitString(append(EncodeString("dog"), EncodeUint64(1024)...))
	if err != nil || string(content) != "dog" || len(rest) == 0 {
		t.Fatalf("SplitString success: content=%q rest=%x err=%v", content, rest, err)
	}

	for _, input := range []string{
		"C0",
		"C100",
		"C3010203",
		"C88363617483646F67",
		"F8384C6F72656D20697073756D20646F6C6F722073697420616D65742C20636F6E7365637465747572206164697069736963696E6720656C6974",
	} {
		_, _, err := SplitString(mustHex(input))
		if err != ErrExpectedString {
			t.Fatalf("SplitString(%s): got %v, want ErrExpectedString", input, err)
		}
	}
}

func TestSplitUint64(t *testing.T) {
	tests := []struct {
		input   string
		wantX   uint64
		wantR   string
		wantErr error
	}{
		{"01", 1, "", nil},
		{"7FFF", 0x7F, "ff", nil},
		{"80FF", 0, "ff", nil},
		{"81FAFF", 0xFA, "ff", nil},
		{"82FAFAFF", 0xFAFA, "ff", nil},
		{"83FAFAFAFF", 0xFAFAFA, "ff", nil},
		{"84FAFAFAFAFF", 0xFAFAFAFA, "ff", nil},
		{"85FAFAFAFAFAFF", 0xFAFAFAFAFA, "ff", nil},
		{"86FAFAFAFAFAFAFF", 0xFAFAFAFAFAFA, "ff", nil},
		{"87FAFAFAFAFAFAFAFF", 0xFAFAFAFAFAFAFA, "ff", nil},
		{"88FAFAFAFAFAFAFAFAFF", 0xFAFAFAFAFAFAFAFA, "ff", nil},
		{"", 0, "", ErrUnexpectedEOF},
		{"00", 0, "", ErrCanonInt},
		{"81", 0, "", ErrValueTooLarge},
		{"8100", 0, "", ErrCanonSize},
		{"8200FF", 0, "", ErrCanonInt},
		{"8103FF", 0, "", ErrCanonSize},
		{"89FAFAFAFAFAFAFAFAFA", 0, "", ErrValueTooLarge},
	}
	for _, tc := range tests {
		x, rest, err := SplitUint64(mustHex(tc.input))
		if err != tc.wantErr {
			t.Fatalf("SplitUint64(%s): err got %v want %v", tc.input, err, tc.wantErr)
		}
		if tc.wantErr != nil {
			continue
		}
		if x != tc.wantX || hex.EncodeToString(rest) != tc.wantR {
			t.Fatalf("SplitUint64(%s): got x=%d rest=%x, want x=%d rest=%s", tc.input, x, rest, tc.wantX, tc.wantR)
		}
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

func TestAppendBytes(t *testing.T) {
	assertHex(t, "single byte ≤0x7f", AppendBytes(nil, []byte{0x7f}), "7f")
	assertHex(t, "0x80 needs header", AppendBytes(nil, []byte{0x80}), "8180")
	assertHex(t, "appends to existing slice", AppendBytes([]byte{0xde, 0xad}, []byte("dog")), "dead83646f67")
}

func TestAppendUint64(t *testing.T) {
	tests := []struct {
		input  uint64
		slice  string
		output string
	}{
		{0, "", "80"},
		{1, "", "01"},
		{2, "", "02"},
		{127, "", "7f"},
		{128, "", "8180"},
		{129, "", "8181"},
		{0xFFFFFF, "", "83ffffff"},
		{127, "010203", "0102037f"},
		{0xFFFFFF, "010203", "01020383ffffff"},
	}
	for _, tc := range tests {
		slice := mustHex(tc.slice)
		got := AppendUint64(slice, tc.input)
		if hex.EncodeToString(got) != tc.output {
			t.Fatalf("AppendUint64(%d): got %x, want %s", tc.input, got, tc.output)
		}
		if IntSize(tc.input) != len(got)-len(slice) {
			t.Fatalf("IntSize(%d): got %d, want %d", tc.input, IntSize(tc.input), len(got)-len(slice))
		}
	}
}

func TestBytesSize(t *testing.T) {
	tests := []struct {
		v    []byte
		size int
	}{
		{[]byte{}, 1},
		{[]byte{0x01}, 1},
		{[]byte{0x7E}, 1},
		{[]byte{0x7F}, 1},
		{[]byte{0x80}, 2},
		{[]byte{0xFF}, 2},
		{[]byte{0xFF, 0xF0}, 3},
		{make([]byte, 55), 56},
		{make([]byte, 56), 58},
	}
	for _, tc := range tests {
		if s := BytesSize(tc.v); s != tc.size {
			t.Fatalf("BytesSize(%x): got %d, want %d", tc.v, s, tc.size)
		}
		if s := StringSize(string(tc.v)); s != tc.size {
			t.Fatalf("StringSize(%x): got %d, want %d", tc.v, s, tc.size)
		}
	}
}

func TestListSize(t *testing.T) {
	if ListSize(0) != 1 {
		t.Fatalf("ListSize(0): want 1")
	}
	if ListSize(55) != 56 {
		t.Fatalf("ListSize(55): want 56")
	}
	if ListSize(56) != 58 {
		t.Fatalf("ListSize(56) (long header): want 58")
	}
}

func TestSplit(t *testing.T) {
	tests := []struct {
		input   string
		wantK   Kind
		wantC   string
		wantR   string
		wantErr error
	}{
		{"00FFFF", KindByte, "00", "ffff", nil},
		{"7FFFFF", KindByte, "7f", "ffff", nil},
		{"80FFFF", KindString, "", "ffff", nil},
		{"C3010203", KindList, "010203", "", nil},
		{"", 0, "", "", ErrUnexpectedEOF},
		{"8141", 0, "", "", ErrCanonSize},
		{"B800", 0, "", "", ErrCanonSize},
		{"81", 0, "", "", ErrValueTooLarge},
	}
	for _, tc := range tests {
		k, content, rest, err := Split(mustHex(tc.input))
		if err != tc.wantErr {
			t.Fatalf("Split(%s): err got %v want %v", tc.input, err, tc.wantErr)
		}
		if tc.wantErr != nil {
			continue
		}
		if k != tc.wantK || hex.EncodeToString(content) != tc.wantC || hex.EncodeToString(rest) != tc.wantR {
			t.Fatalf("Split(%s): got k=%v c=%s r=%s", tc.input, k, hex.EncodeToString(content), hex.EncodeToString(rest))
		}
	}
}

func TestSplitList(t *testing.T) {
	tests := []struct {
		input   string
		wantC   string
		wantR   string
		wantErr error
	}{
		{"C0", "", "", nil},
		{"C3010203FF", "010203", "ff", nil},
		{"01", "", "", ErrExpectedList},
		{"83646f67", "", "", ErrExpectedList},
	}
	for _, tc := range tests {
		content, rest, err := SplitList(mustHex(tc.input))
		if err != tc.wantErr {
			t.Fatalf("SplitList(%s): err got %v want %v", tc.input, err, tc.wantErr)
		}
		if tc.wantErr != nil {
			continue
		}
		if hex.EncodeToString(content) != tc.wantC || hex.EncodeToString(rest) != tc.wantR {
			t.Fatalf("SplitList(%s): got c=%x r=%x, want c=%s r=%s", tc.input, content, rest, tc.wantC, tc.wantR)
		}
	}
}

func TestSplitListValues(t *testing.T) {
	check := func(input string, elems ...string) {
		t.Helper()
		vals, err := SplitListValues(mustHex(input))
		if err != nil {
			t.Fatalf("SplitListValues(%s): %v", input, err)
		}
		if len(vals) != len(elems) {
			t.Fatalf("SplitListValues(%s): got %d elems, want %d", input, len(vals), len(elems))
		}
		for i, want := range elems {
			if got := hex.EncodeToString(vals[i]); got != want {
				t.Fatalf("SplitListValues(%s)[%d]: got %s, want %s", input, i, got, want)
			}
		}
	}
	checkErr := func(input string, wantErr error) {
		t.Helper()
		_, err := SplitListValues(mustHex(input))
		if err != wantErr {
			t.Fatalf("SplitListValues(%s): got %v, want %v", input, err, wantErr)
		}
	}

	check("C0")
	check("C101", "01")
	check("C180", "80")
	check("C20102", "01", "02")
	check("C3010203", "01", "02", "03")
	check("C80182020283030303", "01", "820202", "83030303")
	check("C88363617483646f67", "83636174", "83646f67")
	check("C4C3010203", "c3010203")
	check("C6C20102C20304", "c20102", "c20304")

	checkErr("01", ErrExpectedList)
	checkErr("83636174", ErrExpectedList)
	checkErr("C60102030405", ErrValueTooLarge)

	_, err := SplitListValues([]byte{})
	if err != ErrUnexpectedEOF {
		t.Fatalf("SplitListValues empty: got %v, want ErrUnexpectedEOF", err)
	}
}

func TestCountValues(t *testing.T) {
	tests := []struct {
		input   string
		want    int
		wantErr error
	}{
		{"", 0, nil},
		{"00", 1, nil},
		{"80", 1, nil},
		{"C0", 1, nil},
		{"010203", 3, nil},
		{"01C40607080902", 3, nil},
		{"820101820202840303030304", 4, nil},
		{"8142", 0, ErrCanonSize},
		{"01018142", 0, ErrCanonSize},
		{"0284020202", 0, ErrValueTooLarge},
	}
	for _, tc := range tests {
		n, err := CountValues(mustHex(tc.input))
		if err != tc.wantErr {
			t.Fatalf("CountValues(%s): err got %v want %v", tc.input, err, tc.wantErr)
		}
		if tc.wantErr == nil && n != tc.want {
			t.Fatalf("CountValues(%s): got %d, want %d", tc.input, n, tc.want)
		}
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
