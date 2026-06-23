package abi

import (
	"testing"

	u256 "gno.land/p/gnoswap/uint256"
)

func TestTupleAt(t *testing.T) {
	cases := []struct {
		name       string
		data       []byte
		fields     []Field
		start      int
		end        int
		maxDepth   int
		wantErr    error
		wantLen    int
		wantString string
	}{
		{
			name:     "static tuple",
			data:     mustHex("0000000000000000000000000000000000000000000000000000000000000001"),
			fields:   []Field{{Type: TypeUint8}},
			end:      32,
			maxDepth: maxDecodeDepth,
			wantLen:  1,
		},
		{
			name: "dynamic string",
			data: mustHex("0000000000000000000000000000000000000000000000000000000000000020" +
				"0000000000000000000000000000000000000000000000000000000000000006" +
				"666f6f6261720000000000000000000000000000000000000000000000000000"),
			fields:     []Field{{Type: TypeString}},
			end:        96,
			maxDepth:   maxDecodeDepth,
			wantLen:    1,
			wantString: "foobar",
		},
		{
			name:     "depth limit",
			data:     make([]byte, 32),
			fields:   []Field{{Type: TypeUint8}},
			end:      32,
			maxDepth: 0,
			wantErr:  ErrDepthLimit,
		},
		{
			name:     "invalid bounds",
			data:     make([]byte, 32),
			fields:   []Field{{Type: TypeUint8}},
			start:    -1,
			end:      32,
			maxDepth: maxDecodeDepth,
			wantErr:  ErrInvalidData,
		},
		{
			name:     "cursor exceeds end",
			data:     make([]byte, 32),
			fields:   []Field{{Type: TypeUint8}},
			end:      16,
			maxDepth: maxDecodeDepth,
			wantErr:  ErrInvalidData,
		},
		{
			name:     "dynamic offset out of range",
			data:     mustHex("0000000000000000000000000000000000000000000000000000000000000040"),
			fields:   []Field{{Type: TypeBytes}},
			end:      32,
			maxDepth: maxDecodeDepth,
			wantErr:  ErrInvalidData,
		},
		{
			name:     "dynamic offset is not word aligned",
			data:     mustHex("0000000000000000000000000000000000000000000000000000000000000001"),
			fields:   []Field{{Type: TypeBytes}},
			end:      32,
			maxDepth: maxDecodeDepth,
			wantErr:  ErrInvalidData,
		},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			d := decoder{data: tc.data, maxDepth: tc.maxDepth}
			got, err := d.tupleAt(tc.fields, tc.start, tc.end, 0)
			assertError(t, err, tc.wantErr)
			if tc.wantErr != nil {
				return
			}
			if len(got) != tc.wantLen {
				t.Fatalf("tupleAt len = %d, want %d", len(got), tc.wantLen)
			}
			if tc.wantString != "" && got[0].(string) != tc.wantString {
				t.Fatalf("tupleAt string = %q, want %q", got[0].(string), tc.wantString)
			}
		})
	}
}

func TestValueAt(t *testing.T) {
	data := mustHex("0000000000000000000000000000000000000000000000000000000000000006" +
		"666f6f6261720000000000000000000000000000000000000000000000000000")
	arrayData := mustHex("0000000000000000000000000000000000000000000000000000000000000002" +
		"0000000000000000000000000000000000000000000000000000000000000001" +
		"0000000000000000000000000000000000000000000000000000000000000002")
	cases := []struct {
		name       string
		data       []byte
		field      Field
		wantErr    error
		wantString string
		wantLen    int
	}{
		{"bytes", data, Field{Type: TypeBytes}, nil, "", 6},
		{"string", data, Field{Type: TypeString}, nil, "foobar", 0},
		{"struct", arrayData, Field{Type: TypeStruct, Sub: &Schema{Fields: []Field{{Type: TypeUint8}, {Type: TypeUint8}}}}, nil, "", 2},
		{"array", arrayData, Field{Type: TypeArray, Elem: &Field{Type: TypeUint8}}, nil, "", 2},
		{"nil struct schema", data, Field{Type: TypeStruct}, ErrInvalidSchema, "", 0},
		{"nil array elem", data, Field{Type: TypeArray}, ErrInvalidSchema, "", 0},
		{"unsupported", data, Field{Type: Type(99)}, ErrUnsupportedType, "", 0},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			d := decoder{data: tc.data, maxDepth: maxDecodeDepth}
			got, err := d.valueAt(tc.field, 0, len(tc.data), 0)
			assertError(t, err, tc.wantErr)
			if tc.wantErr != nil {
				return
			}
			if tc.wantString != "" && got.(string) != tc.wantString {
				t.Fatalf("valueAt string = %q, want %q", got.(string), tc.wantString)
			}
			if tc.wantLen != 0 {
				switch v := got.(type) {
				case []byte:
					if len(v) != tc.wantLen {
						t.Fatalf("valueAt []byte len = %d, want %d", len(v), tc.wantLen)
					}
				case []any:
					if len(v) != tc.wantLen {
						t.Fatalf("valueAt []any len = %d, want %d", len(v), tc.wantLen)
					}
				default:
					t.Fatalf("unexpected valueAt type %T", got)
				}
			}
		})
	}
}

func TestStaticValue(t *testing.T) {
	addrWord := mustHex("0000000000000000000000000101010101010101010101010101010101010101")
	var b32 [32]byte
	b32[0] = 1
	cases := []struct {
		name    string
		data    []byte
		field   Field
		wantErr error
	}{
		{"uint8", encodeUint64Word(255), Field{Type: TypeUint8}, nil},
		{"uint8 overflow", mustHex("0000000000000000000000000000000000000000000000000000000000000100"), Field{Type: TypeUint8}, ErrInvalidData},
		{"uint32", encodeUint64Word(0xffffffff), Field{Type: TypeUint32}, nil},
		{"uint32 overflow", mustHex("0000000000000000000000000000000000000000000000000000000100000000"), Field{Type: TypeUint32}, ErrInvalidData},
		{"uint64", encodeUint64Word(2), Field{Type: TypeUint64}, nil},
		{"uint64 high padding", mustHex("0000000000000000000000000000000000000000000000010000000000000000"), Field{Type: TypeUint64}, ErrInvalidData},
		{"uint256", encodeUint256Word(u256.NewUint(2)), Field{Type: TypeUint256}, nil},
		{"bytes32", b32[:], Field{Type: TypeBytes32}, nil},
		{"bool true", encodeUint64Word(1), Field{Type: TypeBool}, nil},
		{"bool false", encodeUint64Word(0), Field{Type: TypeBool}, nil},
		{"bool invalid", encodeUint64Word(2), Field{Type: TypeBool}, ErrInvalidData},
		{"address", addrWord, Field{Type: TypeAddress}, nil},
		{"address non-zero padding", mustHex("0000000000000000000000ff0101010101010101010101010101010101010101"), Field{Type: TypeAddress}, ErrInvalidData},
		{"struct", append(encodeUint64Word(1), encodeUint64Word(2)...), Field{Type: TypeStruct, Sub: &Schema{Fields: []Field{{Type: TypeUint8}, {Type: TypeUint8}}}}, nil},
		{"nil struct schema", make([]byte, 32), Field{Type: TypeStruct}, ErrInvalidSchema},
		{"short data", make([]byte, 16), Field{Type: TypeUint8}, ErrInvalidData},
		{"unsupported", make([]byte, 32), Field{Type: TypeBytes}, ErrUnsupportedType},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			d := decoder{data: tc.data, maxDepth: maxDecodeDepth}
			_, err := d.staticValue(tc.field, 0, len(tc.data), 0)
			assertError(t, err, tc.wantErr)
		})
	}
}

func TestArrayAt(t *testing.T) {
	staticData := mustHex("0000000000000000000000000000000000000000000000000000000000000003" +
		"0000000000000000000000000000000000000000000000000000000000000001" +
		"0000000000000000000000000000000000000000000000000000000000000002" +
		"0000000000000000000000000000000000000000000000000000000000000003")
	dynamicData := mustHex("0000000000000000000000000000000000000000000000000000000000000001" +
		"0000000000000000000000000000000000000000000000000000000000000020" +
		"0000000000000000000000000000000000000000000000000000000000000001" +
		"ab00000000000000000000000000000000000000000000000000000000000000")
	cases := []struct {
		name     string
		data     []byte
		elem     Field
		maxDepth int
		wantErr  error
		wantLen  int
	}{
		{"empty", make([]byte, 32), Field{Type: TypeUint8}, maxDecodeDepth, nil, 0},
		{"static values", staticData, Field{Type: TypeUint256}, maxDecodeDepth, nil, 3},
		{"dynamic values", dynamicData, Field{Type: TypeBytes}, maxDecodeDepth, nil, 1},
		{"depth limit", make([]byte, 32), Field{Type: TypeUint8}, 0, ErrDepthLimit, 0},
		{"short data", make([]byte, 16), Field{Type: TypeUint8}, maxDecodeDepth, ErrInvalidData, 0},
		{"length exceeds data", encodeUint64Word(2), Field{Type: TypeUint8}, maxDecodeDepth, ErrInvalidData, 0},
		{"dynamic offset out of range", mustHex("0000000000000000000000000000000000000000000000000000000000000001" + "0000000000000000000000000000000000000000000000000000000000000040"), Field{Type: TypeBytes}, maxDecodeDepth, ErrInvalidData, 0},
		{"dynamic offset not aligned", mustHex("0000000000000000000000000000000000000000000000000000000000000001" + "0000000000000000000000000000000000000000000000000000000000000001"), Field{Type: TypeBytes}, maxDecodeDepth, ErrInvalidData, 0},
		{"invalid dynamic elem schema", append(encodeUint64Word(1), encodeUint64Word(0)...), Field{Type: TypeStruct}, maxDecodeDepth, ErrInvalidSchema, 0},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			d := decoder{data: tc.data, maxDepth: tc.maxDepth}
			got, err := d.arrayAt(tc.elem, 0, len(tc.data), 0)
			assertError(t, err, tc.wantErr)
			if tc.wantErr != nil {
				return
			}
			if len(got) != tc.wantLen {
				t.Fatalf("arrayAt len = %d, want %d", len(got), tc.wantLen)
			}
		})
	}
}

func TestBytesAt(t *testing.T) {
	cases := []struct {
		name    string
		data    []byte
		wantHex string
		wantErr error
	}{
		{"empty", make([]byte, 32), "", nil},
		{"valid", mustHex("0000000000000000000000000000000000000000000000000000000000000004aabbccdd00000000000000000000000000000000000000000000000000000000"), "aabbccdd", nil},
		{"short", make([]byte, 16), "", ErrInvalidData},
		{"huge length", mustHex("0000000000000000000000000000000000000000000000008000000000000000"), "", ErrInvalidData},
		{"plain out of range", mustHex("0000000000000000000000000000000000000000000000000000000000000040"), "", ErrInvalidData},
		{"roundUp32 wrap", mustHex("000000000000000000000000000000000000000000000000ffffffffffffffff"), "", ErrInvalidData},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			d := decoder{data: tc.data, maxDepth: maxDecodeDepth}
			got, err := d.bytesAt(0, len(tc.data))
			assertError(t, err, tc.wantErr)
			if tc.wantErr != nil {
				return
			}
			assertHex(t, tc.name, got, tc.wantHex)
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
			assertError(t, err, tc.wantErr)
			if got != tc.want {
				t.Fatalf("decodeWordUint64 = %d, want %d", got, tc.want)
			}
		})
	}
}

func TestRoundUp32(t *testing.T) {
	cases := []struct {
		name string
		in   uint64
		want uint64
	}{
		{"zero", 0, 0},
		{"one", 1, 32},
		{"word", 32, 32},
		{"word plus one", 33, 64},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			if got := roundUp32(tc.in); got != tc.want {
				t.Fatalf("roundUp32(%d) = %d, want %d", tc.in, got, tc.want)
			}
		})
	}
}
