// Test vectors and cases are based on the following references:
//
//	https://github.com/ethereum/go-ethereum/blob/master/accounts/abi/packing_test.go
package abi

import (
	"testing"

	u256 "gno.land/p/gnoswap/uint256"
)

func TestEncodeTuple(t *testing.T) {
	maxUint256 := new(u256.Uint).SetAllOne()
	cases := []struct {
		name    string
		fields  []Field
		values  []any
		wantHex string
		wantErr error
	}{
		{
			name:    "empty tuple",
			fields:  nil,
			values:  nil,
			wantHex: "",
		},
		{
			name:   "static values",
			fields: []Field{{Type: TypeBool}, {Type: TypeUint256}},
			values: []any{true, maxUint256},
			wantHex: "0000000000000000000000000000000000000000000000000000000000000001" +
				"ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff",
		},
		{
			name:   "dynamic bytes after static value",
			fields: []Field{{Type: TypeUint8}, {Type: TypeBytes}},
			values: []any{uint8(7), []byte{0xab}},
			wantHex: "0000000000000000000000000000000000000000000000000000000000000007" +
				"0000000000000000000000000000000000000000000000000000000000000040" +
				"0000000000000000000000000000000000000000000000000000000000000001" +
				"ab00000000000000000000000000000000000000000000000000000000000000",
		},
		{
			name:   "static struct is inlined",
			fields: []Field{{Type: TypeStruct, Sub: &Schema{Fields: []Field{{Type: TypeUint256}, {Type: TypeUint256}}}}},
			values: []any{[]any{u256.NewUint(1), u256.NewUint(2)}},
			wantHex: "0000000000000000000000000000000000000000000000000000000000000001" +
				"0000000000000000000000000000000000000000000000000000000000000002",
		},
		{
			name:   "dynamic struct with string",
			fields: []Field{{Type: TypeStruct, Sub: &Schema{Fields: []Field{{Type: TypeUint8}, {Type: TypeString}}}}},
			values: []any{[]any{uint8(1), "test"}},
			wantHex: "0000000000000000000000000000000000000000000000000000000000000020" +
				"0000000000000000000000000000000000000000000000000000000000000001" +
				"0000000000000000000000000000000000000000000000000000000000000040" +
				"0000000000000000000000000000000000000000000000000000000000000004" +
				"7465737400000000000000000000000000000000000000000000000000000000",
		},
		{
			name:   "dynamic struct with bytes",
			fields: []Field{{Type: TypeStruct, Sub: &Schema{Fields: []Field{{Type: TypeBytes}, {Type: TypeUint8}}}}},
			values: []any{[]any{[]byte{0xab, 0xcd}, uint8(2)}},
			wantHex: "0000000000000000000000000000000000000000000000000000000000000020" +
				"0000000000000000000000000000000000000000000000000000000000000040" +
				"0000000000000000000000000000000000000000000000000000000000000002" +
				"0000000000000000000000000000000000000000000000000000000000000002" +
				"abcd000000000000000000000000000000000000000000000000000000000000",
		},
		{
			name:    "wrong value count",
			fields:  []Field{{Type: TypeUint8}},
			values:  []any{},
			wantErr: ErrInvalidValue,
		},
		{
			name:    "invalid field schema",
			fields:  []Field{{Type: TypeStruct, Sub: &Schema{Fields: []Field{{Type: TypeStruct}}}}},
			values:  []any{[]any{[]any{}}},
			wantErr: ErrInvalidSchema,
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got, err := encodeTuple(tc.fields, tc.values)
			assertError(t, err, tc.wantErr)
			if tc.wantErr != nil {
				return
			}
			assertHex(t, tc.name, got, tc.wantHex)
		})
	}
}

func TestEncodeValue(t *testing.T) {
	var b32 [32]byte
	b32[0] = 1
	addr := filledBytes(20, 0x01)
	cases := []struct {
		name    string
		field   Field
		value   any
		wantHex string
		wantErr error
	}{
		{"uint8", Field{Type: TypeUint8}, uint8(2), "0000000000000000000000000000000000000000000000000000000000000002", nil},
		{"uint32", Field{Type: TypeUint32}, uint32(1), "0000000000000000000000000000000000000000000000000000000000000001", nil},
		{"uint64", Field{Type: TypeUint64}, uint64(2), "0000000000000000000000000000000000000000000000000000000000000002", nil},
		{"uint256", Field{Type: TypeUint256}, u256.NewUint(2), "0000000000000000000000000000000000000000000000000000000000000002", nil},
		{"bytes32", Field{Type: TypeBytes32}, b32, "0100000000000000000000000000000000000000000000000000000000000000", nil},
		{"bytes", Field{Type: TypeBytes}, []byte{0xab}, "0000000000000000000000000000000000000000000000000000000000000001ab00000000000000000000000000000000000000000000000000000000000000", nil},
		{"string", Field{Type: TypeString}, "foobar", "0000000000000000000000000000000000000000000000000000000000000006666f6f6261720000000000000000000000000000000000000000000000000000", nil},
		{"bool true", Field{Type: TypeBool}, true, "0000000000000000000000000000000000000000000000000000000000000001", nil},
		{"bool false", Field{Type: TypeBool}, false, "0000000000000000000000000000000000000000000000000000000000000000", nil},
		{"address", Field{Type: TypeAddress}, addr, "0000000000000000000000000101010101010101010101010101010101010101", nil},
		{"struct", Field{Type: TypeStruct, Sub: &Schema{Fields: []Field{{Type: TypeUint8}, {Type: TypeBool}}}}, []any{uint8(1), true}, "00000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000001", nil},
		{"array", Field{Type: TypeArray, Elem: &Field{Type: TypeUint8}}, []any{uint8(1), uint8(2)}, "000000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000002", nil},
		{"wrong uint8 type", Field{Type: TypeUint8}, int(1), "", ErrInvalidValue},
		{"nil uint256", Field{Type: TypeUint256}, (*u256.Uint)(nil), "", ErrInvalidValue},
		{"wrong bytes32 type", Field{Type: TypeBytes32}, []byte{0x01}, "", ErrInvalidValue},
		{"wrong bytes type", Field{Type: TypeBytes}, "not_bytes", "", ErrInvalidValue},
		{"wrong string type", Field{Type: TypeString}, []byte{0x01}, "", ErrInvalidValue},
		{"wrong bool type", Field{Type: TypeBool}, uint8(1), "", ErrInvalidValue},
		{"short address", Field{Type: TypeAddress}, []byte{0x01, 0x02}, "", ErrInvalidValue},
		{"long address", Field{Type: TypeAddress}, make([]byte, 32), "", ErrInvalidValue},
		{"nil struct schema", Field{Type: TypeStruct}, []any{}, "", ErrInvalidSchema},
		{"wrong struct value type", Field{Type: TypeStruct, Sub: &Schema{}}, "not_values", "", ErrInvalidValue},
		{"nil array elem", Field{Type: TypeArray}, []any{}, "", ErrInvalidSchema},
		{"wrong array value type", Field{Type: TypeArray, Elem: &Field{Type: TypeUint8}}, "not_values", "", ErrInvalidValue},
		{"unsupported type", Field{Type: Type(99)}, nil, "", ErrUnsupportedType},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got, err := encodeValue(tc.field, tc.value)
			assertError(t, err, tc.wantErr)
			if tc.wantErr != nil {
				return
			}
			assertHex(t, tc.name, got, tc.wantHex)
		})
	}
}

func TestEncodeArray(t *testing.T) {
	cases := []struct {
		name    string
		elem    Field
		values  []any
		wantHex string
		wantErr error
	}{
		{
			name:    "empty static array",
			elem:    Field{Type: TypeUint256},
			values:  []any{},
			wantHex: "0000000000000000000000000000000000000000000000000000000000000000",
		},
		{
			name:   "static uint256 values",
			elem:   Field{Type: TypeUint256},
			values: []any{u256.NewUint(1), u256.NewUint(2), u256.NewUint(3)},
			wantHex: "0000000000000000000000000000000000000000000000000000000000000003" +
				"0000000000000000000000000000000000000000000000000000000000000001" +
				"0000000000000000000000000000000000000000000000000000000000000002" +
				"0000000000000000000000000000000000000000000000000000000000000003",
		},
		{
			name:   "dynamic bytes values",
			elem:   Field{Type: TypeBytes},
			values: []any{[]byte{0xf0, 0xf0, 0xf0}, []byte{0xf0, 0xf0, 0xf0}},
			wantHex: "0000000000000000000000000000000000000000000000000000000000000002" +
				"0000000000000000000000000000000000000000000000000000000000000040" +
				"0000000000000000000000000000000000000000000000000000000000000080" +
				"0000000000000000000000000000000000000000000000000000000000000003" +
				"f0f0f00000000000000000000000000000000000000000000000000000000000" +
				"0000000000000000000000000000000000000000000000000000000000000003" +
				"f0f0f00000000000000000000000000000000000000000000000000000000000",
		},
		{
			name:    "invalid static element value",
			elem:    Field{Type: TypeUint8},
			values:  []any{"not_uint8"},
			wantErr: ErrInvalidValue,
		},
		{
			name:    "invalid dynamic element value",
			elem:    Field{Type: TypeBytes},
			values:  []any{"not_bytes"},
			wantErr: ErrInvalidValue,
		},
		{
			name:    "invalid dynamic element schema with struct",
			elem:    Field{Type: TypeStruct},
			values:  []any{[]any{uint8(1)}},
			wantErr: ErrInvalidSchema,
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got, err := encodeArray(tc.elem, tc.values)
			assertError(t, err, tc.wantErr)
			if tc.wantErr != nil {
				return
			}
			assertHex(t, tc.name, got, tc.wantHex)
		})
	}
}

func TestEncodeBytes(t *testing.T) {
	cases := []struct {
		name    string
		value   []byte
		wantHex string
	}{
		{"nil", nil, "0000000000000000000000000000000000000000000000000000000000000000"},
		{"empty", []byte{}, "0000000000000000000000000000000000000000000000000000000000000000"},
		{"short", []byte{0xab}, "0000000000000000000000000000000000000000000000000000000000000001ab00000000000000000000000000000000000000000000000000000000000000"},
		{"exact word", mustHex("0100000000000000000000000000000000000000000000000000000000000000"), "00000000000000000000000000000000000000000000000000000000000000200100000000000000000000000000000000000000000000000000000000000000"},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			assertHex(t, tc.name, encodeBytes(tc.value), tc.wantHex)
		})
	}
}

func TestEncodeUint64Word(t *testing.T) {
	cases := []struct {
		name    string
		value   uint64
		wantHex string
	}{
		{"zero", 0, "0000000000000000000000000000000000000000000000000000000000000000"},
		{"one", 1, "0000000000000000000000000000000000000000000000000000000000000001"},
		{"max", ^uint64(0), "000000000000000000000000000000000000000000000000ffffffffffffffff"},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			assertHex(t, tc.name, encodeUint64Word(tc.value), tc.wantHex)
		})
	}
}

func TestEncodeUint256Word(t *testing.T) {
	cases := []struct {
		name    string
		value   *u256.Uint
		wantHex string
	}{
		{"zero", u256.Zero(), "0000000000000000000000000000000000000000000000000000000000000000"},
		{"two", u256.NewUint(2), "0000000000000000000000000000000000000000000000000000000000000002"},
		{"max", new(u256.Uint).SetAllOne(), "ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			assertHex(t, tc.name, encodeUint256Word(tc.value), tc.wantHex)
		})
	}
}

func TestIsDynamic(t *testing.T) {
	cases := []struct {
		name  string
		field Field
		want  bool
	}{
		{"bytes", Field{Type: TypeBytes}, true},
		{"string", Field{Type: TypeString}, true},
		{"array", Field{Type: TypeArray, Elem: &Field{Type: TypeUint8}}, true},
		{"nil struct schema", Field{Type: TypeStruct}, true},
		{"struct with dynamic child", Field{Type: TypeStruct, Sub: &Schema{Fields: []Field{{Type: TypeUint8}, {Type: TypeString}}}}, true},
		{"uint8", Field{Type: TypeUint8}, false},
		{"uint32", Field{Type: TypeUint32}, false},
		{"uint64", Field{Type: TypeUint64}, false},
		{"uint256", Field{Type: TypeUint256}, false},
		{"bytes32", Field{Type: TypeBytes32}, false},
		{"bool", Field{Type: TypeBool}, false},
		{"address", Field{Type: TypeAddress}, false},
		{"static nested struct", Field{Type: TypeStruct, Sub: &Schema{Fields: []Field{{Type: TypeUint8}, {Type: TypeStruct, Sub: &Schema{Fields: []Field{{Type: TypeBool}}}}}}}, false},
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
		{"struct with dynamic child", Field{Type: TypeStruct, Sub: &Schema{Fields: []Field{{Type: TypeUint8}, {Type: TypeString}}}}, wordSize, nil},
		{"deeply nested static struct", Field{Type: TypeStruct, Sub: &Schema{Fields: []Field{
			{Type: TypeStruct, Sub: &Schema{Fields: []Field{
				{Type: TypeStruct, Sub: &Schema{Fields: []Field{
					{Type: TypeUint8},
					{Type: TypeUint32},
				}}},
			}}},
		}}}, wordSize * 2, nil},
		{"nil struct schema", Field{Type: TypeStruct}, wordSize, nil},
		{"nested struct with nil schema child", Field{Type: TypeStruct, Sub: &Schema{Fields: []Field{{Type: TypeUint8}, {Type: TypeStruct}}}}, wordSize, nil},
		{"nil array elem", Field{Type: TypeArray}, wordSize, nil},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got, err := staticHeadSize(tc.field)
			assertError(t, err, tc.wantErr)
			if got != tc.want {
				t.Fatalf("staticHeadSize = %d, want %d", got, tc.want)
			}
		})
	}
}

func TestEncode(t *testing.T) {
	cases := []struct {
		name    string
		schema  Schema
		values  []any
		wantHex string
		wantErr error
	}{
		{
			name:    "empty",
			schema:  Schema{Fields: nil},
			values:  nil,
			wantHex: "",
		},
		{
			name:   "static values",
			schema: Schema{Fields: []Field{{Type: TypeUint8}, {Type: TypeBool}}},
			values: []any{uint8(42), true},
			wantHex: "000000000000000000000000000000000000000000000000000000000000002a" +
				"0000000000000000000000000000000000000000000000000000000000000001",
		},
		{
			name:    "wrong value count",
			schema:  Schema{Fields: []Field{{Type: TypeUint8}}},
			values:  []any{},
			wantErr: ErrInvalidValue,
		},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got, err := Encode(tc.schema, tc.values)
			assertError(t, err, tc.wantErr)
			if tc.wantErr != nil {
				return
			}
			assertHex(t, tc.name, got, tc.wantHex)
		})
	}
}
