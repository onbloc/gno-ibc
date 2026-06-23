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
	tests := []struct {
		name   string
		schema Schema
		values []any
		want   error
	}{
		{
			name:   "wrong type",
			schema: Schema{Fields: []Field{{Type: TypeUint8}}},
			values: []any{int(1)},
			want:   ErrInvalidValue,
		},
		{
			name:   "wrong count",
			schema: Schema{Fields: []Field{{Type: TypeUint8}}},
			values: []any{},
			want:   ErrInvalidValue,
		},
		{
			name:   "nil struct sub",
			schema: Schema{Fields: []Field{{Type: TypeStruct}}},
			values: []any{[]any{}},
			want:   ErrInvalidSchema,
		},
		{
			name:   "nil array elem",
			schema: Schema{Fields: []Field{{Type: TypeArray}}},
			values: []any{[]any{}},
			want:   ErrInvalidSchema,
		},
		{
			name:   "nil uint256",
			schema: Schema{Fields: []Field{{Type: TypeUint256}}},
			values: []any{(*u256.Uint)(nil)},
			want:   ErrInvalidValue,
		},
		{
			name:   "short address",
			schema: Schema{Fields: []Field{{Type: TypeAddress}}},
			values: []any{[]byte{0x01, 0x02}},
			want:   ErrInvalidValue,
		},
		{
			name:   "long address",
			schema: Schema{Fields: []Field{{Type: TypeAddress}}},
			values: []any{make([]byte, 32)},
			want:   ErrInvalidValue,
		},
		{
			name:   "wrong address type",
			schema: Schema{Fields: []Field{{Type: TypeAddress}}},
			values: []any{"not_a_byte_slice"},
			want:   ErrInvalidValue,
		},
		{
			name:   "short bytes32",
			schema: Schema{Fields: []Field{{Type: TypeBytes32}}},
			values: []any{[]byte{0x01}},
			want:   ErrInvalidValue,
		},
		{
			name:   "long bytes32",
			schema: Schema{Fields: []Field{{Type: TypeBytes32}}},
			values: []any{[64]byte{}},
			want:   ErrInvalidValue,
		},
		{
			name: "array wrong element type",
			schema: Schema{
				Fields: []Field{
					{
						Type: TypeArray,
						Elem: &Field{Type: TypeBytes},
					},
				},
			},
			values: []any{[]any{"not_bytes"}},
			want:   ErrInvalidValue,
		},
		{
			name: "array non-slice",
			schema: Schema{
				Fields: []Field{
					{
						Type: TypeArray,
						Elem: &Field{Type: TypeUint8},
					},
				},
			},
			values: []any{"not_a_slice"},
			want:   ErrInvalidValue,
		},
		{
			name:   "string wrong type",
			schema: Schema{Fields: []Field{{Type: TypeString}}},
			values: []any{[]byte{0x01}},
			want:   ErrInvalidValue,
		},
		{
			name:   "bytes wrong type",
			schema: Schema{Fields: []Field{{Type: TypeBytes}}},
			values: []any{"not_bytes"},
			want:   ErrInvalidValue,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			_, err := Encode(tt.schema, tt.values)
			if err != tt.want {
				t.Fatalf("got %v want %v", err, tt.want)
			}
		})
	}
}

func TestRejectMalformedData(t *testing.T) {
	cases := []struct {
		name       string
		schema     Schema
		data       []byte
		wantErr    error
		wantString string
		wantUint8  uint8
	}{
		{
			name:    "data length is not word aligned",
			schema:  Schema{Fields: []Field{{Type: TypeUint256}}},
			data:    []byte{1, 2, 3},
			wantErr: ErrInvalidData,
		},
		{
			name:    "bool value greater than one",
			schema:  Schema{Fields: []Field{{Type: TypeBool}}},
			data:    mustHex("0000000000000000000000000000000000000000000000000000000000000002"),
			wantErr: ErrInvalidData,
		},
		{
			name:    "bool value greater than one (0xff)",
			schema:  Schema{Fields: []Field{{Type: TypeBool}}},
			data:    mustHex("00000000000000000000000000000000000000000000000000000000000000ff"),
			wantErr: ErrInvalidData,
		},
		{
			name:    "uint64 high padding is non-zero",
			schema:  Schema{Fields: []Field{{Type: TypeUint64}}},
			data:    mustHex("0000000000000000000000000000000000000000000000010000000000000000"),
			wantErr: ErrInvalidData,
		},
		{
			name:    "address left padding is non-zero",
			schema:  Schema{Fields: []Field{{Type: TypeAddress}}},
			data:    mustHex("0000000000000000000000ff0101010101010101010101010101010101010101"),
			wantErr: ErrInvalidData,
		},
		{
			name:       "empty string",
			schema:     Schema{Fields: []Field{{Type: TypeString}}},
			wantString: "",
			data: mustHex("0000000000000000000000000000000000000000000000000000000000000020" +
				"0000000000000000000000000000000000000000000000000000000000000000"),
		},
		{
			name:    "address decode from short data",
			schema:  Schema{Fields: []Field{{Type: TypeAddress}}},
			data:    make([]byte, 16),
			wantErr: ErrInvalidData,
		},
		{
			name:    "bytes32 decode from short data",
			schema:  Schema{Fields: []Field{{Type: TypeBytes32}}},
			data:    make([]byte, 16),
			wantErr: ErrInvalidData,
		},
		{
			name:    "uint8 overflow (256)",
			schema:  Schema{Fields: []Field{{Type: TypeUint8}}},
			data:    mustHex("0000000000000000000000000000000000000000000000000000000000000100"),
			wantErr: ErrInvalidData,
		},
		{
			name:      "uint8 boundary value (255) should succeed",
			schema:    Schema{Fields: []Field{{Type: TypeUint8}}},
			data:      mustHex("00000000000000000000000000000000000000000000000000000000000000ff"),
			wantUint8: 255,
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got, err := Decode(tc.schema, tc.data)
			if err != tc.wantErr {
				t.Fatalf("got %v want %v", err, tc.wantErr)
			}
			if tc.wantErr != nil {
				return
			}
			if len(got) != 1 {
				t.Fatalf("decoded values length = %d, want 1", len(got))
			}
			if tc.schema.Fields[0].Type == TypeString && got[0].(string) != tc.wantString {
				t.Fatalf("decoded string = %q, want %q", got[0].(string), tc.wantString)
			}
			if tc.schema.Fields[0].Type == TypeUint8 && got[0].(uint8) != tc.wantUint8 {
				t.Fatalf("decoded uint8 = %d, want %d", got[0].(uint8), tc.wantUint8)
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

func TestIsDynamic(t *testing.T) {
	cases := []struct {
		name  string
		field Field
		want  bool
	}{
		// Dynamic types
		{"bytes is dynamic", Field{Type: TypeBytes}, true},
		{"string is dynamic", Field{Type: TypeString}, true},
		{"array is dynamic", Field{Type: TypeArray, Elem: &Field{Type: TypeUint8}}, true},
		{"struct with nil schema is treated dynamic", Field{Type: TypeStruct}, true},
		{"struct with dynamic child", Field{Type: TypeStruct, Sub: &Schema{Fields: []Field{{Type: TypeUint8}, {Type: TypeString}}}}, true},
		// Static types
		{"uint8 is static", Field{Type: TypeUint8}, false},
		{"uint32 is static", Field{Type: TypeUint32}, false},
		{"uint64 is static", Field{Type: TypeUint64}, false},
		{"uint256 is static", Field{Type: TypeUint256}, false},
		{"bytes32 is static", Field{Type: TypeBytes32}, false},
		{"bool is static", Field{Type: TypeBool}, false},
		{"address is static", Field{Type: TypeAddress}, false},
		{"static nested struct", Field{Type: TypeStruct, Sub: &Schema{Fields: []Field{{Type: TypeUint8}, {Type: TypeUint32}}}}, false},
		{"deep static struct remains static", Field{Type: TypeStruct, Sub: &Schema{Fields: []Field{
			{Type: TypeStruct, Sub: &Schema{Fields: []Field{{Type: TypeStruct, Sub: &Schema{Fields: []Field{{Type: TypeUint8}}}}}}},
		}}}, false},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			if got := isDynamic(tc.field); got != tc.want {
				t.Fatalf("isDynamic = %v, want %v", got, tc.want)
			}
		})
	}
}

func TestStaticHeadSize(t *testing.T) {
	cases := []struct {
		name    string
		field   Field
		want    int
		wantErr error
	}{
		{"single static field", Field{Type: TypeUint8}, wordSize, nil},
		{"dynamic field head size", Field{Type: TypeBytes}, wordSize, nil},
		{"dynamic array head size", Field{Type: TypeArray, Elem: &Field{Type: TypeUint8}}, wordSize, nil},
		{"dynamic string head size", Field{Type: TypeString}, wordSize, nil},
		{"nested static struct", Field{Type: TypeStruct, Sub: &Schema{Fields: []Field{{Type: TypeUint8}, {Type: TypeStruct, Sub: &Schema{Fields: []Field{{Type: TypeUint32}, {Type: TypeBool}}}}}}}, wordSize * 3, nil},
		{"struct with dynamic child returns head size", Field{Type: TypeStruct, Sub: &Schema{Fields: []Field{{Type: TypeUint8}, {Type: TypeString}}}}, wordSize, nil},
		{"deeply nested static struct", Field{Type: TypeStruct, Sub: &Schema{Fields: []Field{
			{Type: TypeStruct, Sub: &Schema{Fields: []Field{
				{Type: TypeStruct, Sub: &Schema{Fields: []Field{
					{Type: TypeUint8},
					{Type: TypeUint32},
				}}},
			}}},
		}}}, wordSize * 2, nil},
		{"nil struct schema", Field{Type: TypeStruct, Sub: nil}, 0, ErrInvalidSchema},
		{"nested struct with nil schema in child", Field{Type: TypeStruct, Sub: &Schema{Fields: []Field{
			{Type: TypeUint8},
			{Type: TypeStruct, Sub: nil},
		}}}, 0, ErrInvalidSchema},
	}
	for _, tc := range cases {
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
}

func TestRoundUp32(t *testing.T) {
	cases := []struct {
		in   uint64
		want uint64
	}{
		{0, 0},
		{1, 32},
		{32, 32},
		{33, 64},
	}
	for _, tc := range cases {
		t.Run("", func(t *testing.T) {
			if got := roundUp32(tc.in); got != tc.want {
				t.Fatalf("roundUp32(%d) = %d, want %d", tc.in, got, tc.want)
			}
		})
	}
}

func TestDecodeWordUint64(t *testing.T) {
	cases := []struct {
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
	for _, tc := range cases {
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
