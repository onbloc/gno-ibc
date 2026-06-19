// Test vectors and cases are based on the following references:
//
//	https://github.com/ethereum/go-ethereum/blob/master/accounts/abi/packing_test.go
package abi

import (
	"encoding/hex"
	"testing"

	u256 "gno.land/p/gnoswap/uint256"
)

func TestGoEthereumPrimitiveVectors(t *testing.T) {
	// bool
	boolSchema := Schema{Fields: []Field{{Type: TypeBool}}}
	assertEncodeHex(t, "bool_true", boolSchema, []any{true},
		"0000000000000000000000000000000000000000000000000000000000000001")
	assertEncodeHex(t, "bool_false", boolSchema, []any{false},
		"0000000000000000000000000000000000000000000000000000000000000000")

	// unsigned integers
	assertEncodeHex(t, "uint8_2", Schema{Fields: []Field{{Type: TypeUint8}}}, []any{uint8(2)},
		"0000000000000000000000000000000000000000000000000000000000000002")
	assertEncodeHex(t, "uint32_1", Schema{Fields: []Field{{Type: TypeUint32}}}, []any{uint32(1)},
		"0000000000000000000000000000000000000000000000000000000000000001")
	assertEncodeHex(t, "uint64_2", Schema{Fields: []Field{{Type: TypeUint64}}}, []any{uint64(2)},
		"0000000000000000000000000000000000000000000000000000000000000002")
	assertEncodeHex(t, "uint256_2", Schema{Fields: []Field{{Type: TypeUint256}}}, []any{u256.NewUint(2)},
		"0000000000000000000000000000000000000000000000000000000000000002")

	// bytes32: 32 fixed bytes, MSB-first in slot (left-aligned, no length prefix)
	var b32 [32]byte
	b32[0] = 1
	assertEncodeHex(t, "bytes32_leading_one", Schema{Fields: []Field{{Type: TypeBytes32}}}, []any{b32},
		"0100000000000000000000000000000000000000000000000000000000000000")

	// bytes: outer offset(0x20) + length + data (dynamic type)
	assertEncodeHex(t, "bytes_32b", Schema{Fields: []Field{{Type: TypeBytes}}},
		[]any{mustHex("0100000000000000000000000000000000000000000000000000000000000000")},
		"0000000000000000000000000000000000000000000000000000000000000020"+
			"0000000000000000000000000000000000000000000000000000000000000020"+
			"0100000000000000000000000000000000000000000000000000000000000000")

	// string: identical wire format to bytes
	assertEncodeHex(t, "string_foobar", Schema{Fields: []Field{{Type: TypeString}}},
		[]any{"foobar"},
		"0000000000000000000000000000000000000000000000000000000000000020"+
			"0000000000000000000000000000000000000000000000000000000000000006"+
			"666f6f6261720000000000000000000000000000000000000000000000000000")

	// static tuple(uint256, uint256) — go-ethereum: tuple(int256(1), int256(2)), same encoding for positive values
	staticPairSchema := Schema{Fields: []Field{{
		Type: TypeStruct,
		Sub:  &Schema{Fields: []Field{{Type: TypeUint256}, {Type: TypeUint256}}},
	}}}
	assertEncodeHex(t, "static_tuple_two_uint256", staticPairSchema,
		[]any{[]any{u256.NewUint(1), u256.NewUint(2)}},
		"0000000000000000000000000000000000000000000000000000000000000001"+
			"0000000000000000000000000000000000000000000000000000000000000002")
}

func TestGoEthereumArrayVectors(t *testing.T) {
	// bytes[] — outer offset(0x20) + count(2) + per-elem offsets + length-prefixed data
	bytesSliceSchema := Schema{Fields: []Field{{Type: TypeArray, Elem: &Field{Type: TypeBytes}}}}
	assertEncodeHex(t, "bytes_slice_two_elems", bytesSliceSchema,
		[]any{[]any{[]byte{0xf0, 0xf0, 0xf0}, []byte{0xf0, 0xf0, 0xf0}}},
		"0000000000000000000000000000000000000000000000000000000000000020"+
			"0000000000000000000000000000000000000000000000000000000000000002"+
			"0000000000000000000000000000000000000000000000000000000000000040"+
			"0000000000000000000000000000000000000000000000000000000000000080"+
			"0000000000000000000000000000000000000000000000000000000000000003"+
			"f0f0f00000000000000000000000000000000000000000000000000000000000"+
			"0000000000000000000000000000000000000000000000000000000000000003"+
			"f0f0f00000000000000000000000000000000000000000000000000000000000")

	// string[] {"Ethereum", "go-ethereum"}
	strSliceSchema := Schema{Fields: []Field{{Type: TypeArray, Elem: &Field{Type: TypeString}}}}
	assertEncodeHex(t, "string_slice_two_elems", strSliceSchema,
		[]any{[]any{"Ethereum", "go-ethereum"}},
		"0000000000000000000000000000000000000000000000000000000000000020"+
			"0000000000000000000000000000000000000000000000000000000000000002"+
			"0000000000000000000000000000000000000000000000000000000000000040"+
			"0000000000000000000000000000000000000000000000000000000000000080"+
			"0000000000000000000000000000000000000000000000000000000000000008"+
			"457468657265756d000000000000000000000000000000000000000000000000"+
			"000000000000000000000000000000000000000000000000000000000000000b"+
			"676f2d657468657265756d000000000000000000000000000000000000000000")
}

func TestAddressEncoding(t *testing.T) {
	addrSchema := Schema{Fields: []Field{{Type: TypeAddress}}}

	addr := make([]byte, 20)
	for i := range addr {
		addr[i] = 0x01
	}
	assertEncodeHex(t, "address_all_ones", addrSchema, []any{addr},
		"0000000000000000000000000101010101010101010101010101010101010101")

	// non-zero bytes in the 12-byte left padding must be rejected
	_, err := Decode(addrSchema, mustHex("0000000000000000000000ff0101010101010101010101010101010101010101"))
	if err != ErrInvalidData {
		t.Fatalf("address non-zero padding: got %v want ErrInvalidData", err)
	}
}

func TestStaticElementArray(t *testing.T) {
	uint256ArraySchema := Schema{Fields: []Field{{Type: TypeArray, Elem: &Field{Type: TypeUint256}}}}

	// static elem path in encodeArray/arrayAt: no per-element offset words
	assertEncodeHex(t, "uint256_array_three", uint256ArraySchema,
		[]any{[]any{u256.NewUint(1), u256.NewUint(2), u256.NewUint(3)}},
		"0000000000000000000000000000000000000000000000000000000000000020"+
			"0000000000000000000000000000000000000000000000000000000000000003"+
			"0000000000000000000000000000000000000000000000000000000000000001"+
			"0000000000000000000000000000000000000000000000000000000000000002"+
			"0000000000000000000000000000000000000000000000000000000000000003")

	// empty array: encodeArray early-return path, count word only
	assertEncodeHex(t, "uint256_array_empty", uint256ArraySchema,
		[]any{[]any{}},
		"0000000000000000000000000000000000000000000000000000000000000020"+
			"0000000000000000000000000000000000000000000000000000000000000000")
}

func TestEncodeBoundaryCases(t *testing.T) {
	maxUint256 := new(u256.Uint).SetAllOne()
	var zeroBytes32 [32]byte

	cases := []struct {
		name    string
		schema  Schema
		values  []any
		wantHex string
		wantErr error
	}{
		{
			name:    "empty schema with nil values",
			schema:  Schema{},
			values:  nil,
			wantHex: "",
		},
		{
			name:    "uint256 zero",
			schema:  Schema{Fields: []Field{{Type: TypeUint256}}},
			values:  []any{u256.Zero()},
			wantHex: "0000000000000000000000000000000000000000000000000000000000000000",
		},
		{
			name:    "uint256 max",
			schema:  Schema{Fields: []Field{{Type: TypeUint256}}},
			values:  []any{maxUint256},
			wantHex: "ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff",
		},
		{
			name:    "bytes32 zero value",
			schema:  Schema{Fields: []Field{{Type: TypeBytes32}}},
			values:  []any{zeroBytes32},
			wantHex: "0000000000000000000000000000000000000000000000000000000000000000",
		},
		{
			name:   "bytes nil slice",
			schema: Schema{Fields: []Field{{Type: TypeBytes}}},
			values: []any{([]byte)(nil)},
			wantHex: "0000000000000000000000000000000000000000000000000000000000000020" +
				"0000000000000000000000000000000000000000000000000000000000000000",
		},
		{
			name:   "single element dynamic array",
			schema: Schema{Fields: []Field{{Type: TypeArray, Elem: &Field{Type: TypeBytes}}}},
			values: []any{[]any{[]byte{0xab}}},
			wantHex: "0000000000000000000000000000000000000000000000000000000000000020" +
				"0000000000000000000000000000000000000000000000000000000000000001" +
				"0000000000000000000000000000000000000000000000000000000000000020" +
				"0000000000000000000000000000000000000000000000000000000000000001" +
				"ab00000000000000000000000000000000000000000000000000000000000000",
		},
		{
			name:    "uint256 nil pointer",
			schema:  Schema{Fields: []Field{{Type: TypeUint256}}},
			values:  []any{(*u256.Uint)(nil)},
			wantErr: ErrInvalidValue,
		},
		{
			name:    "address nil slice",
			schema:  Schema{Fields: []Field{{Type: TypeAddress}}},
			values:  []any{([]byte)(nil)},
			wantErr: ErrInvalidValue,
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got, err := Encode(tc.schema, tc.values)
			if err != tc.wantErr {
				t.Fatalf("Encode error = %v, want %v", err, tc.wantErr)
			}
			if tc.wantErr != nil {
				return
			}
			if hex.EncodeToString(got) != tc.wantHex {
				t.Fatalf("Encode hex = %s, want %s", hex.EncodeToString(got), tc.wantHex)
			}
			decoded, err := Decode(tc.schema, got)
			if err != nil {
				t.Fatalf("Decode(encoded): %v", err)
			}
			encodedAgain, err := Encode(tc.schema, decoded)
			if err != nil {
				t.Fatalf("Encode(decoded): %v", err)
			}
			if hex.EncodeToString(encodedAgain) != tc.wantHex {
				t.Fatalf("round-trip hex = %s, want %s", hex.EncodeToString(encodedAgain), tc.wantHex)
			}
		})
	}
}

func TestEmptyDynamicEncoding(t *testing.T) {
	// encodeBytes with len=0: (32-0%32)%32 == 0, so no padding word appended
	assertEncodeHex(t, "bytes_empty", Schema{Fields: []Field{{Type: TypeBytes}}}, []any{[]byte{}},
		"0000000000000000000000000000000000000000000000000000000000000020"+
			"0000000000000000000000000000000000000000000000000000000000000000")
}

func TestRejectIntegerOverflow(t *testing.T) {
	// uint8 word value 256 (0x100) — decoder rejects v > 255
	_, err := Decode(Schema{Fields: []Field{{Type: TypeUint8}}},
		mustHex("0000000000000000000000000000000000000000000000000000000000000100"))
	if err != ErrInvalidData {
		t.Fatalf("uint8 overflow: got %v want ErrInvalidData", err)
	}

	// uint32 word value 0x1_00000000 — decoder rejects v > 0xFFFFFFFF
	_, err = Decode(Schema{Fields: []Field{{Type: TypeUint32}}},
		mustHex("0000000000000000000000000000000000000000000000000000000100000000"))
	if err != ErrInvalidData {
		t.Fatalf("uint32 overflow: got %v want ErrInvalidData", err)
	}
}

func TestEncodeErrors(t *testing.T) {
	// wrong Go type for a field
	if _, err := Encode(Schema{Fields: []Field{{Type: TypeUint8}}}, []any{int(1)}); err != ErrInvalidValue {
		t.Fatalf("wrong type: got %v want ErrInvalidValue", err)
	}

	// wrong number of values
	if _, err := Encode(Schema{Fields: []Field{{Type: TypeUint8}}}, []any{}); err != ErrInvalidValue {
		t.Fatalf("wrong count: got %v want ErrInvalidValue", err)
	}

	// TypeStruct with nil Sub
	if _, err := Encode(Schema{Fields: []Field{{Type: TypeStruct}}}, []any{[]any{}}); err != ErrInvalidSchema {
		t.Fatalf("nil Sub: got %v want ErrInvalidSchema", err)
	}

	// TypeArray with nil Elem
	if _, err := Encode(Schema{Fields: []Field{{Type: TypeArray}}}, []any{[]any{}}); err != ErrInvalidSchema {
		t.Fatalf("nil Elem: got %v want ErrInvalidSchema", err)
	}
}

func TestRejectMalformedData(t *testing.T) {
	cases := []struct {
		name   string
		schema Schema
		data   []byte
	}{
		{
			name:   "data length is not word aligned",
			schema: Schema{Fields: []Field{{Type: TypeUint256}}},
			data:   []byte{1, 2, 3},
		},
		{
			name:   "bool value greater than one",
			schema: Schema{Fields: []Field{{Type: TypeBool}}},
			data:   mustHex("0000000000000000000000000000000000000000000000000000000000000002"),
		},
		{
			name:   "uint64 high padding is non-zero",
			schema: Schema{Fields: []Field{{Type: TypeUint64}}},
			data:   mustHex("0000000000000000000000000000000000000000000000010000000000000000"),
		},
		{
			name:   "address left padding is non-zero",
			schema: Schema{Fields: []Field{{Type: TypeAddress}}},
			data:   mustHex("0000000000000000000000ff0101010101010101010101010101010101010101"),
		},
		{
			name:   "empty string",
			schema: Schema{Fields: []Field{{Type: TypeString}}},
			data: mustHex("0000000000000000000000000000000000000000000000000000000000000020" +
				"0000000000000000000000000000000000000000000000000000000000000000"),
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got, err := Decode(tc.schema, tc.data)
			if tc.name == "empty string" {
				if err != nil {
					t.Fatalf("Decode empty string: %v", err)
				}
				if got[0].(string) != "" {
					t.Fatalf("empty string decoded as %q", got[0].(string))
				}
				return
			}
			if err != ErrInvalidData {
				t.Fatalf("got %v want ErrInvalidData", err)
			}
		})
	}
}

func TestRejectOutOfRangeTupleOffsets(t *testing.T) {
	schema := Schema{Fields: []Field{{Type: TypeBytes}}}
	cases := []struct {
		name string
		data []byte
	}{
		{
			"overflow offset",
			mustHex("000000000000000000000000000000000000000000000000fffffffffffffe00"),
		},
		{
			"plain out-of-range offset",
			mustHex("0000000000000000000000000000000000000000000000000000000000000040"),
		},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			_, err := Decode(schema, tc.data)
			if err != ErrInvalidData {
				t.Fatalf("got %v want ErrInvalidData", err)
			}
		})
	}
}

func TestRejectOutOfRangeArrayOffsets(t *testing.T) {
	bytesArraySchema := Schema{Fields: []Field{{Type: TypeArray, Elem: &Field{Type: TypeBytes}}}}
	cases := []struct {
		name string
		data []byte
	}{
		{
			"overflow offset",
			mustHex("0000000000000000000000000000000000000000000000000000000000000020" +
				"0000000000000000000000000000000000000000000000000000000000000001" +
				"000000000000000000000000000000000000000000000000fffffffffffffe00"),
		},
		{
			"plain out-of-range offset",
			mustHex("0000000000000000000000000000000000000000000000000000000000000020" +
				"0000000000000000000000000000000000000000000000000000000000000001" +
				"0000000000000000000000000000000000000000000000000000000000000040"),
		},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			_, err := Decode(bytesArraySchema, tc.data)
			if err != ErrInvalidData {
				t.Fatalf("got %v want ErrInvalidData", err)
			}
		})
	}
}

func TestRejectOutOfRangeBytesLength(t *testing.T) {
	bytesSchema := Schema{Fields: []Field{{Type: TypeBytes}}}
	stringSchema := Schema{Fields: []Field{{Type: TypeString}}}
	cases := []struct {
		name   string
		schema Schema
		data   []byte
	}{
		{
			"bytes huge length",
			bytesSchema,
			mustHex("0000000000000000000000000000000000000000000000000000000000000020" +
				"0000000000000000000000000000000000000000000000008000000000000000"),
		},
		{
			"string huge length",
			stringSchema,
			mustHex("0000000000000000000000000000000000000000000000000000000000000020" +
				"0000000000000000000000000000000000000000000000008000000000000000"),
		},
		{
			"bytes plain out-of-range length",
			bytesSchema,
			mustHex("0000000000000000000000000000000000000000000000000000000000000020" +
				"0000000000000000000000000000000000000000000000000000000000000040"),
		},
		{
			"bytes roundUp32 wrap length",
			bytesSchema,
			mustHex("0000000000000000000000000000000000000000000000000000000000000020" +
				"000000000000000000000000000000000000000000000000ffffffffffffffff"),
		},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			_, err := Decode(tc.schema, tc.data)
			if err != ErrInvalidData {
				t.Fatalf("got %v want ErrInvalidData", err)
			}
		})
	}

	out, err := Decode(bytesSchema, mustHex("0000000000000000000000000000000000000000000000000000000000000020"+
		"0000000000000000000000000000000000000000000000000000000000000004"+
		"aabbccdd00000000000000000000000000000000000000000000000000000000"))
	if err != nil {
		t.Fatalf("Decode valid bytes: %v", err)
	}
	if hex.EncodeToString(out[0].([]byte)) != "aabbccdd" {
		t.Fatalf("decoded valid bytes mismatch")
	}
}

func TestDecodeDepthLimit(t *testing.T) {
	data := mustHex("0000000000000000000000000000000000000000000000000000000000000020" +
		"0000000000000000000000000000000000000000000000000000000000000000")
	d := decoder{data: data, maxDepth: 0}
	_, err := d.tupleAt([]Field{{Type: TypeBytes}}, 0, len(data), 0)
	if err != ErrDepthLimit {
		t.Fatalf("got %v want ErrDepthLimit", err)
	}
}

func TestInternalBoundaryHelpers(t *testing.T) {
	dynamicCases := []struct {
		name  string
		field Field
		want  bool
	}{
		{"bytes is dynamic", Field{Type: TypeBytes}, true},
		{"array is dynamic", Field{Type: TypeArray, Elem: &Field{Type: TypeUint8}}, true},
		{"struct with nil schema is treated dynamic", Field{Type: TypeStruct}, true},
		{"static nested struct", Field{Type: TypeStruct, Sub: &Schema{Fields: []Field{{Type: TypeUint8}, {Type: TypeUint32}}}}, false},
		{"struct with dynamic child", Field{Type: TypeStruct, Sub: &Schema{Fields: []Field{{Type: TypeUint8}, {Type: TypeString}}}}, true},
	}
	for _, tc := range dynamicCases {
		t.Run(tc.name, func(t *testing.T) {
			if got := isDynamic(tc.field); got != tc.want {
				t.Fatalf("isDynamic = %v, want %v", got, tc.want)
			}
		})
	}

	sizeCases := []struct {
		name    string
		field   Field
		want    int
		wantErr error
	}{
		{"single static field", Field{Type: TypeUint8}, wordSize, nil},
		{"dynamic field head size", Field{Type: TypeBytes}, wordSize, nil},
		{"nested static struct", Field{Type: TypeStruct, Sub: &Schema{Fields: []Field{{Type: TypeUint8}, {Type: TypeStruct, Sub: &Schema{Fields: []Field{{Type: TypeUint32}, {Type: TypeBool}}}}}}}, wordSize * 3, nil},
		{"nil struct schema", Field{Type: TypeStruct, Sub: nil}, wordSize, nil},
	}
	for _, tc := range sizeCases {
		t.Run(tc.name, func(t *testing.T) {
			got, err := staticHeadSize(tc.field)
			if err != tc.wantErr {
				t.Fatalf("staticHeadSize error = %v, want %v", err, tc.wantErr)
			}
			if got != tc.want {
				t.Fatalf("staticHeadSize = %d, want %d", got, tc.want)
			}
		})
	}

	roundCases := []struct {
		in   uint64
		want uint64
	}{
		{0, 0},
		{1, 32},
		{32, 32},
		{33, 64},
	}
	for _, tc := range roundCases {
		t.Run("roundUp32", func(t *testing.T) {
			if got := roundUp32(tc.in); got != tc.want {
				t.Fatalf("roundUp32(%d) = %d, want %d", tc.in, got, tc.want)
			}
		})
	}

	wordCases := []struct {
		name    string
		word    []byte
		want    uint64
		wantErr error
	}{
		{"valid zero", make([]byte, wordSize), 0, nil},
		{"valid low word", mustHex("000000000000000000000000000000000000000000000000000000000000002a"), 42, nil},
		{"non-zero high padding", mustHex("0000000000000000000000000000000000000000000000010000000000000000"), 0, ErrInvalidData},
		{"short word", []byte{0}, 0, ErrInvalidData},
	}
	for _, tc := range wordCases {
		t.Run(tc.name, func(t *testing.T) {
			got, err := decodeWordUint64(tc.word)
			if err != tc.wantErr {
				t.Fatalf("decodeWordUint64 error = %v, want %v", err, tc.wantErr)
			}
			if got != tc.want {
				t.Fatalf("decodeWordUint64 = %d, want %d", got, tc.want)
			}
		})
	}
}

func assertEncodeHex(t *testing.T, name string, schema Schema, values []any, want string) {
	got, err := Encode(schema, values)
	if err != nil {
		t.Fatalf("%s Encode: %v", name, err)
	}
	if hex.EncodeToString(got) != want {
		t.Fatalf("%s\n got %s\nwant %s", name, hex.EncodeToString(got), want)
	}

	decoded, err := Decode(schema, got)
	if err != nil {
		t.Fatalf("%s Decode(encoded): %v", name, err)
	}
	encodedAgain, err := Encode(schema, decoded)
	if err != nil {
		t.Fatalf("%s Encode(decoded): %v", name, err)
	}
	if hex.EncodeToString(encodedAgain) != want {
		t.Fatalf("%s round-trip changed bytes", name)
	}
}

func mustHex(s string) []byte {
	bz, err := hex.DecodeString(s)
	if err != nil {
		panic(err)
	}
	return bz
}
