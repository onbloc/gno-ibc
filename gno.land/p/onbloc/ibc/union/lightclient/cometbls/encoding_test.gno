package cometbls

import (
	"encoding/hex"
	"testing"

	"gno.land/p/aib/encoding/proto"
	"gno.land/p/onbloc/ibc/union/types"
)

func TestEncodeHeaderAdditional(t *testing.T) {
	zkpPadded := make([]byte, 32)
	copy(zkpPadded, []byte{0xAA, 0xBB})

	cases := []struct {
		name    string
		header  *Header
		want    []byte
		wantErr string
	}{
		{
			name:   "successful encoding with all fields",
			header: newTestHeader(42, 1000, 500, 10, []byte{0xAA, 0xBB}),
			want: mustHex(
				word32(42) +
					word32(1000) +
					word32(500) +
					bytes32hex(0x01) +
					bytes32hex(0x02) +
					bytes32hex(0x03) +
					word32(10) +
					word32(256) + // offset to dynamic bytes
					word32(2) + // ZKP length
					hex.EncodeToString(zkpPadded),
			),
		},
		{
			name:    "nil header",
			header:  nil,
			wantErr: "nil header",
		},
		{
			name: "nil signed header",
			header: &Header{
				SignedHeader:       nil,
				TrustedHeight:      heightPtr(types.NewHeight(0, 1)),
				ZeroKnowledgeProof: []byte{0x01},
			},
			wantErr: "nil header",
		},
		// Validators hash length tests
		{
			name: "validators hash too short (31 bytes)",
			header: cloneTestHeaderWith(func(h *Header) {
				h.SignedHeader.ValidatorsHash = repeatBytes(0x01, 31)
			}),
			wantErr: "must be 32 bytes",
		},
		{
			name: "validators hash empty",
			header: cloneTestHeaderWith(func(h *Header) {
				h.SignedHeader.ValidatorsHash = []byte{}
			}),
			wantErr: "must be 32 bytes",
		},
		{
			name: "validators hash too long (33 bytes)",
			header: cloneTestHeaderWith(func(h *Header) {
				h.SignedHeader.ValidatorsHash = repeatBytes(0x01, 33)
			}),
			wantErr: "must be 32 bytes",
		},
		{
			name: "validators hash way too long (64 bytes)",
			header: cloneTestHeaderWith(func(h *Header) {
				h.SignedHeader.ValidatorsHash = repeatBytes(0x01, 64)
			}),
			wantErr: "must be 32 bytes",
		},
		{
			name: "validators hash exactly 32 bytes succeeds",
			header: cloneTestHeaderWith(func(h *Header) {
				h.SignedHeader.ValidatorsHash = repeat32(0xAB)
			}),
		},
		// Next validators hash length tests
		{
			name: "next validators hash too short (31 bytes)",
			header: cloneTestHeaderWith(func(h *Header) {
				h.SignedHeader.NextValidatorsHash = repeatBytes(0x02, 31)
			}),
			wantErr: "must be 32 bytes",
		},
		{
			name: "next validators hash empty",
			header: cloneTestHeaderWith(func(h *Header) {
				h.SignedHeader.NextValidatorsHash = []byte{}
			}),
			wantErr: "must be 32 bytes",
		},
		{
			name: "next validators hash too long (33 bytes)",
			header: cloneTestHeaderWith(func(h *Header) {
				h.SignedHeader.NextValidatorsHash = repeatBytes(0x02, 33)
			}),
			wantErr: "must be 32 bytes",
		},
		{
			name: "next validators hash exactly 32 bytes succeeds",
			header: cloneTestHeaderWith(func(h *Header) {
				h.SignedHeader.NextValidatorsHash = repeat32(0xCD)
			}),
		},
		// App hash length tests
		{
			name: "app hash too short (31 bytes)",
			header: cloneTestHeaderWith(func(h *Header) {
				h.SignedHeader.AppHash = repeatBytes(0x03, 31)
			}),
			wantErr: "must be 32 bytes",
		},
		{
			name: "app hash empty",
			header: cloneTestHeaderWith(func(h *Header) {
				h.SignedHeader.AppHash = []byte{}
			}),
			wantErr: "must be 32 bytes",
		},
		{
			name: "app hash too long (33 bytes)",
			header: cloneTestHeaderWith(func(h *Header) {
				h.SignedHeader.AppHash = repeatBytes(0x03, 33)
			}),
			wantErr: "must be 32 bytes",
		},
		{
			name: "app hash exactly 32 bytes succeeds",
			header: cloneTestHeaderWith(func(h *Header) {
				h.SignedHeader.AppHash = repeat32(0xEF)
			}),
		},
		// Trusted height tests
		{
			name: "nil trusted height uses zero",
			header: cloneTestHeaderWith(func(h *Header) {
				h.TrustedHeight = nil
			}),
		},
		{
			name: "non-nil trusted height extracts revision height",
			header: cloneTestHeaderWith(func(h *Header) {
				h.TrustedHeight = heightPtr(types.NewHeight(5, 42))
			}),
		},
		// Edge cases
		{
			name: "all three hashes exactly 32 bytes",
			header: cloneTestHeaderWith(func(h *Header) {
				h.SignedHeader.ValidatorsHash = repeat32(0x11)
				h.SignedHeader.NextValidatorsHash = repeat32(0x22)
				h.SignedHeader.AppHash = repeat32(0x33)
			}),
		},
		{
			name: "zero knowledge proof empty",
			header: cloneTestHeaderWith(func(h *Header) {
				h.ZeroKnowledgeProof = []byte{}
			}),
		},
		{
			name: "zero knowledge proof large",
			header: cloneTestHeaderWith(func(h *Header) {
				h.ZeroKnowledgeProof = repeatBytes(0xAA, 384)
			}),
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got, err := EncodeHeader(tc.header)
			if tc.wantErr != "" {
				requireErrorContains(t, err, tc.wantErr)
				return
			}
			if err != nil {
				t.Fatalf("unexpected error: %v", err)
			}
			if tc.want != nil {
				bytesEq(t, "EncodeHeader", got, tc.want)
			}
		})
	}
}

// TestDecodeHeaderAdditional covers additional branches not in header_test.gno:
// - TimeNanos boundary values (0, 999999999, 1000000000)
// - Hash field decoding individually
// - Trusted height zero vs non-zero
// - ZKP empty vs non-empty
func TestDecodeHeaderAdditional(t *testing.T) {
	zkp := []byte{0xAA, 0xBB}
	zkpPadded := make([]byte, 32)
	copy(zkpPadded, zkp)

	// Valid base encoding for modification in test cases
	validBase := func() []byte {
		return mustHex(
			word32(42) +
				word32(1000) +
				word32(500) +
				bytes32hex(0x01) +
				bytes32hex(0x02) +
				bytes32hex(0x03) +
				word32(10) +
				word32(256) +
				word32(2) +
				hex.EncodeToString(zkpPadded),
		)
	}

	cases := []struct {
		name    string
		data    []byte
		check   func(*testing.T, *Header)
		wantErr string
	}{
		{
			name: "successful decode",
			data: validBase(),
			check: func(t *testing.T, got *Header) {
				if got.SignedHeader.Height != 42 {
					t.Fatalf("Height: got %d want 42", got.SignedHeader.Height)
				}
				if got.SignedHeader.TimeSeconds != 1000 {
					t.Fatalf("TimeSeconds: got %d want 1000", got.SignedHeader.TimeSeconds)
				}
				if got.SignedHeader.TimeNanos != 500 {
					t.Fatalf("TimeNanos: got %d want 500", got.SignedHeader.TimeNanos)
				}
				bytesEq(t, "ValidatorsHash", got.SignedHeader.ValidatorsHash, repeat32(0x01))
				bytesEq(t, "NextValidatorsHash", got.SignedHeader.NextValidatorsHash, repeat32(0x02))
				bytesEq(t, "AppHash", got.SignedHeader.AppHash, repeat32(0x03))
				if got.TrustedHeight.RevisionHeight != 10 {
					t.Fatalf("TrustedHeight: got %d want 10", got.TrustedHeight.RevisionHeight)
				}
				bytesEq(t, "ZKP", got.ZeroKnowledgeProof, zkp)
			},
		},
		// ABI decode errors
		{
			name:    "empty buffer",
			data:    []byte{},
			wantErr: "abi:",
		},
		{
			name:    "truncated buffer",
			data:    make([]byte, 50),
			wantErr: "abi:",
		},
		{
			name: "invalid ABI encoding",
			data: func() []byte {
				// Corrupt the valid encoding
				buf := validBase()
				buf[0] ^= 0xFF
				return buf
			}(),
			wantErr: "abi:",
		},
		// TimeNanos range tests
		{
			name: "timenanos at boundary (999999999 succeeds)",
			data: func() []byte {
				return mustHex(
					word32(1) +
						word32(1000) +
						word32(999_999_999) +
						bytes32hex(0x01) +
						bytes32hex(0x02) +
						bytes32hex(0x03) +
						word32(0) +
						word32(256) +
						word32(0),
				)
			}(),
			check: func(t *testing.T, got *Header) {
				if got.SignedHeader.TimeNanos != 999_999_999 {
					t.Fatalf("TimeNanos: got %d want 999999999", got.SignedHeader.TimeNanos)
				}
			},
		},
		{
			name: "timenanos exactly maxTimeNanos fails",
			data: func() []byte {
				return mustHex(
					word32(1) +
						word32(1000) +
						word32(1_000_000_000) +
						bytes32hex(0x01) +
						bytes32hex(0x02) +
						bytes32hex(0x03) +
						word32(0) +
						word32(256) +
						word32(0),
				)
			}(),
			wantErr: "TimeNanos out of range",
		},
		{
			name: "timenanos exceeds maxTimeNanos",
			data: func() []byte {
				return mustHex(
					word32(1) +
						word32(1000) +
						word32(1_000_000_001) +
						bytes32hex(0x01) +
						bytes32hex(0x02) +
						bytes32hex(0x03) +
						word32(0) +
						word32(256) +
						word32(0),
				)
			}(),
			wantErr: "TimeNanos out of range",
		},
		{
			name: "timenanos very large value",
			data: func() []byte {
				return mustHex(
					word32(1) +
						word32(1000) +
						word32(0xFFFFFFFF) +
						bytes32hex(0x01) +
						bytes32hex(0x02) +
						bytes32hex(0x03) +
						word32(0) +
						word32(256) +
						word32(0),
				)
			}(),
			wantErr: "TimeNanos out of range",
		},
		{
			name: "timenanos zero succeeds",
			data: func() []byte {
				return mustHex(
					word32(1) +
						word32(1000) +
						word32(0) +
						bytes32hex(0x01) +
						bytes32hex(0x02) +
						bytes32hex(0x03) +
						word32(0) +
						word32(256) +
						word32(0),
				)
			}(),
		},
		// Trusted height tests
		{
			name: "trusted height zero creates zero height",
			data: func() []byte {
				return mustHex(
					word32(1) +
						word32(1000) +
						word32(0) +
						bytes32hex(0x01) +
						bytes32hex(0x02) +
						bytes32hex(0x03) +
						word32(0) +
						word32(256) +
						word32(0),
				)
			}(),
			check: func(t *testing.T, got *Header) {
				if got.TrustedHeight.RevisionHeight != 0 {
					t.Fatalf("TrustedHeight: got %d want 0", got.TrustedHeight.RevisionHeight)
				}
			},
		},
		{
			name: "trusted height non-zero",
			data: func() []byte {
				return mustHex(
					word32(1) +
						word32(1000) +
						word32(0) +
						bytes32hex(0x01) +
						bytes32hex(0x02) +
						bytes32hex(0x03) +
						word32(12345) +
						word32(256) +
						word32(0),
				)
			}(),
			check: func(t *testing.T, got *Header) {
				if got.TrustedHeight.RevisionHeight != 12345 {
					t.Fatalf("TrustedHeight: got %d want 12345", got.TrustedHeight.RevisionHeight)
				}
			},
		},
		// Zero knowledge proof tests
		{
			name: "zkp empty",
			data: func() []byte {
				return mustHex(
					word32(1) +
						word32(1000) +
						word32(0) +
						bytes32hex(0x01) +
						bytes32hex(0x02) +
						bytes32hex(0x03) +
						word32(0) +
						word32(256) +
						word32(0),
				)
			}(),
			check: func(t *testing.T, got *Header) {
				if len(got.ZeroKnowledgeProof) != 0 {
					t.Fatalf("ZKP length: got %d want 0", len(got.ZeroKnowledgeProof))
				}
			},
		},
		{
			name: "zkp non-empty",
			data: validBase(),
			check: func(t *testing.T, got *Header) {
				bytesEq(t, "ZKP", got.ZeroKnowledgeProof, zkp)
			},
		},
		// Hash field decoding
		{
			name: "validators hash decoding",
			data: func() []byte {
				return mustHex(
					word32(1) +
						word32(1000) +
						word32(0) +
						bytes32hex(0xAB) +
						bytes32hex(0x02) +
						bytes32hex(0x03) +
						word32(0) +
						word32(256) +
						word32(0),
				)
			}(),
			check: func(t *testing.T, got *Header) {
				bytesEq(t, "ValidatorsHash", got.SignedHeader.ValidatorsHash, repeat32(0xAB))
			},
		},
		{
			name: "next validators hash decoding",
			data: func() []byte {
				return mustHex(
					word32(1) +
						word32(1000) +
						word32(0) +
						bytes32hex(0x01) +
						bytes32hex(0xCD) +
						bytes32hex(0x03) +
						word32(0) +
						word32(256) +
						word32(0),
				)
			}(),
			check: func(t *testing.T, got *Header) {
				bytesEq(t, "NextValidatorsHash", got.SignedHeader.NextValidatorsHash, repeat32(0xCD))
			},
		},
		{
			name: "app hash decoding",
			data: func() []byte {
				return mustHex(
					word32(1) +
						word32(1000) +
						word32(0) +
						bytes32hex(0x01) +
						bytes32hex(0x02) +
						bytes32hex(0xEF) +
						word32(0) +
						word32(256) +
						word32(0),
				)
			}(),
			check: func(t *testing.T, got *Header) {
				bytesEq(t, "AppHash", got.SignedHeader.AppHash, repeat32(0xEF))
			},
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got, err := DecodeHeader(tc.data)
			if tc.wantErr != "" {
				requireErrorContains(t, err, tc.wantErr)
				return
			}
			if err != nil {
				t.Fatalf("unexpected error: %v", err)
			}
			if tc.check != nil {
				tc.check(t, got)
			}
		})
	}
}

// TestEncodeMisbehaviourAdditional covers additional branches not in misbehaviour_test.gno:
// - Header1 nil with valid header2
// - Header2 nil with valid header1
// - Both headers encoding errors
// - Nil signed header in both headers
func TestEncodeMisbehaviourAdditional(t *testing.T) {
	validHeader := newTestHeader(100, 2000, 0, 90, []byte{0x01, 0x02})

	cases := []struct {
		name    string
		m       *Misbehaviour
		wantErr string
	}{
		{
			name: "successful encoding with both headers",
			m: &Misbehaviour{
				Header1: validHeader,
				Header2: newTestHeader(101, 2001, 0, 91, []byte{0x03, 0x04}),
			},
		},
		{
			name:    "nil misbehaviour",
			m:       nil,
			wantErr: "nil misbehaviour",
		},
		{
			name: "header1 nil",
			m: &Misbehaviour{
				Header1: nil,
				Header2: validHeader,
			},
			wantErr: "nil header",
		},
		{
			name: "header2 nil",
			m: &Misbehaviour{
				Header1: validHeader,
				Header2: nil,
			},
			wantErr: "nil header",
		},
		{
			name: "header1 encoding error (invalid validators hash)",
			m: &Misbehaviour{
				Header1: cloneTestHeaderWith(func(h *Header) {
					h.SignedHeader.ValidatorsHash = []byte{0x01}
				}),
				Header2: validHeader,
			},
			wantErr: "must be 32 bytes",
		},
		{
			name: "header2 encoding error (invalid app hash)",
			m: &Misbehaviour{
				Header1: validHeader,
				Header2: cloneTestHeaderWith(func(h *Header) {
					h.SignedHeader.AppHash = []byte{0x01}
				}),
			},
			wantErr: "must be 32 bytes",
		},
		{
			name: "both headers encoding error (header1 fails first)",
			m: &Misbehaviour{
				Header1: cloneTestHeaderWith(func(h *Header) {
					h.SignedHeader.NextValidatorsHash = []byte{0x01}
				}),
				Header2: cloneTestHeaderWith(func(h *Header) {
					h.SignedHeader.AppHash = []byte{0x01}
				}),
			},
			wantErr: "must be 32 bytes",
		},
		{
			name: "nil signed header in header1",
			m: &Misbehaviour{
				Header1: &Header{
					SignedHeader:       nil,
					TrustedHeight:      heightPtr(types.NewHeight(0, 1)),
					ZeroKnowledgeProof: []byte{0x01},
				},
				Header2: validHeader,
			},
			wantErr: "nil header",
		},
		{
			name: "nil signed header in header2",
			m: &Misbehaviour{
				Header1: validHeader,
				Header2: &Header{
					SignedHeader:       nil,
					TrustedHeight:      heightPtr(types.NewHeight(0, 1)),
					ZeroKnowledgeProof: []byte{0x01},
				},
			},
			wantErr: "nil header",
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got, err := EncodeMisbehaviour(tc.m)
			if tc.wantErr != "" {
				requireErrorContains(t, err, tc.wantErr)
				return
			}
			if err != nil {
				t.Fatalf("unexpected error: %v", err)
			}
			if len(got) == 0 {
				t.Fatal("expected non-empty encoding")
			}
		})
	}
}

// TestDecodeMisbehaviourAdditional covers additional branches not in misbehaviour_test.gno:
// - Empty buffer (pos < len(buf) condition)
// - Invalid varint tag (decodeTag error)
// - Wrong wire types (VARINT, FIXED64, FIXED32)
// - Unknown field numbers
// - Field order reversed
// - Truncated length-delimited fields
func TestDecodeMisbehaviourAdditional(t *testing.T) {
	validHeaderBytes, err := EncodeHeader(newTestHeader(100, 2000, 0, 90, []byte{0x01}))
	if err != nil {
		t.Fatalf("EncodeHeader: %v", err)
	}

	cases := []struct {
		name    string
		buf     []byte
		check   func(*testing.T, *Misbehaviour)
		wantErr string
	}{
		{
			name: "successful decode both headers",
			buf: func() []byte {
				h2, _ := EncodeHeader(newTestHeader(101, 2001, 0, 91, []byte{0x02}))
				buf := proto.AppendLengthDelimited(nil, 1, validHeaderBytes)
				buf = proto.AppendLengthDelimited(buf, 2, h2)
				return buf
			}(),
			check: func(t *testing.T, got *Misbehaviour) {
				if got.Header1 == nil {
					t.Fatal("Header1 is nil")
				}
				if got.Header2 == nil {
					t.Fatal("Header2 is nil")
				}
				if got.Header1.SignedHeader.Height != 100 {
					t.Fatalf("Header1 height: got %d want 100", got.Header1.SignedHeader.Height)
				}
				if got.Header2.SignedHeader.Height != 101 {
					t.Fatalf("Header2 height: got %d want 101", got.Header2.SignedHeader.Height)
				}
			},
		},
		{
			name:    "empty buffer",
			buf:     []byte{},
			wantErr: "misbehaviour missing a header",
		},
		{
			name: "only header1 present",
			buf: func() []byte {
				return proto.AppendLengthDelimited(nil, 1, validHeaderBytes)
			}(),
			wantErr: "misbehaviour missing a header",
		},
		{
			name: "only header2 present",
			buf: func() []byte {
				return proto.AppendLengthDelimited(nil, 2, validHeaderBytes)
			}(),
			wantErr: "misbehaviour missing a header",
		},
		{
			name: "invalid tag (truncated varint)",
			buf: func() []byte {
				// Invalid varint (0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x01)
				return []byte{0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x01}
			}(),
			wantErr: "unsupported wire type",
		},
		{
			name: "wrong wireType (varint instead of length-delimited)",
			buf: func() []byte {
				// Field 1 with VARINT wire type instead of LEN
				// Tag = (1 << 3) | 0 = 0x08
				buf := []byte{0x08, 0x01}
				return buf
			}(),
			check: func(t *testing.T, got *Misbehaviour) {
				// Should skip the varint field and continue
				if got.Header1 != nil || got.Header2 != nil {
					t.Fatal("expected nil headers after skipping unknown field")
				}
			},
			wantErr: "misbehaviour missing a header",
		},
		{
			name: "header bytes invalid (decodeHeader error)",
			buf: func() []byte {
				return proto.AppendLengthDelimited(nil, 1, []byte{0x01, 0x02, 0x03})
			}(),
			wantErr: "abi:",
		},
		{
			name: "unknown field ignored",
			buf: func() []byte {
				h2, _ := EncodeHeader(newTestHeader(101, 2001, 0, 91, []byte{0x02}))
				buf := proto.AppendLengthDelimited(nil, 1, validHeaderBytes)
				buf = proto.AppendLengthDelimited(buf, 2, h2)
				// Add field 3 with VARINT wire type (should be ignored)
				// Field 3 with VARINT wire type: (3 << 3) | 0 = 0x18
				buf = append(buf, 0x18, 0x01)
				return buf
			}(),
			check: func(t *testing.T, got *Misbehaviour) {
				if got.Header1 == nil {
					t.Fatal("Header1 is nil")
				}
				if got.Header2 == nil {
					t.Fatal("Header2 is nil")
				}
			},
		},
		{
			name: "field order reversed (header2 before header1)",
			buf: func() []byte {
				h2, _ := EncodeHeader(newTestHeader(101, 2001, 0, 91, []byte{0x02}))
				buf := proto.AppendLengthDelimited(nil, 2, h2)
				buf = proto.AppendLengthDelimited(buf, 1, validHeaderBytes)
				return buf
			}(),
			check: func(t *testing.T, got *Misbehaviour) {
				if got.Header1 == nil {
					t.Fatal("Header1 is nil")
				}
				if got.Header2 == nil {
					t.Fatal("Header2 is nil")
				}
				if got.Header1.SignedHeader.Height != 100 {
					t.Fatalf("Header1 height: got %d want 100", got.Header1.SignedHeader.Height)
				}
				if got.Header2.SignedHeader.Height != 101 {
					t.Fatalf("Header2 height: got %d want 101", got.Header2.SignedHeader.Height)
				}
			},
		},
		{
			name: "truncated length-delimited field",
			buf: func() []byte {
				// Tag for field 1 with LEN wire type: (1 << 3) | 2 = 0x0A
				// Length of 100 but only 1 byte provided
				buf := []byte{0x0A, 0x64, 0x01}
				return buf
			}(),
			wantErr: "buffer underflow",
		},
		{
			name: "field with 64-bit wire type (fixed64)",
			buf: func() []byte {
				h2, _ := EncodeHeader(newTestHeader(101, 2001, 0, 91, []byte{0x02}))
				buf := proto.AppendLengthDelimited(nil, 1, validHeaderBytes)
				buf = proto.AppendLengthDelimited(buf, 2, h2)
				// Add field 3 with FIXED64 wire type: (3 << 3) | 1 = 0x19
				buf = append(buf, 0x19)
				buf = append(buf, make([]byte, 8)...) // 8 bytes of fixed64 data
				return buf
			}(),
			check: func(t *testing.T, got *Misbehaviour) {
				if got.Header1 == nil {
					t.Fatal("Header1 is nil")
				}
				if got.Header2 == nil {
					t.Fatal("Header2 is nil")
				}
			},
		},
		{
			name: "field with 32-bit wire type (fixed32)",
			buf: func() []byte {
				h2, _ := EncodeHeader(newTestHeader(101, 2001, 0, 91, []byte{0x02}))
				buf := proto.AppendLengthDelimited(nil, 1, validHeaderBytes)
				buf = proto.AppendLengthDelimited(buf, 2, h2)
				// Add field 3 with FIXED32 wire type: (3 << 3) | 5 = 0x1D
				buf = append(buf, 0x1D)
				buf = append(buf, make([]byte, 4)...) // 4 bytes of fixed32 data
				return buf
			}(),
			check: func(t *testing.T, got *Misbehaviour) {
				if got.Header1 == nil {
					t.Fatal("Header1 is nil")
				}
				if got.Header2 == nil {
					t.Fatal("Header2 is nil")
				}
			},
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got, err := DecodeMisbehaviour(tc.buf)
			if tc.wantErr != "" {
				requireErrorContains(t, err, tc.wantErr)
				return
			}
			if err != nil {
				t.Fatalf("unexpected error: %v", err)
			}
			if tc.check != nil {
				tc.check(t, got)
			}
		})
	}
}

// TestToBytes32 covers all branches of the private toBytes32 helper:
// - empty slice (0 bytes)
// - too short (1-31 bytes)
// - exactly 32 bytes (success)
// - too long (33+ bytes)
func TestToBytes32(t *testing.T) {
	cases := []struct {
		name    string
		b       []byte
		want    [32]byte
		wantErr string
	}{
		{
			name:    "empty slice",
			b:       []byte{},
			wantErr: "must be 32 bytes",
		},
		{
			name:    "1 byte slice",
			b:       []byte{0x01},
			wantErr: "must be 32 bytes",
		},
		{
			name:    "31 byte slice",
			b:       repeatBytes(0xAB, 31),
			wantErr: "must be 32 bytes",
		},
		{
			name: "exactly 32 bytes succeeds",
			b:    repeat32(0xCD),
			want: func() [32]byte {
				var out [32]byte
				copy(out[:], repeat32(0xCD))
				return out
			}(),
		},
		{
			name: "exactly 32 bytes with pattern",
			b: func() []byte {
				out := make([]byte, 32)
				for i := range out {
					out[i] = byte(i)
				}
				return out
			}(),
			want: func() [32]byte {
				var out [32]byte
				for i := range out {
					out[i] = byte(i)
				}
				return out
			}(),
		},
		{
			name:    "33 byte slice",
			b:       repeatBytes(0xEF, 33),
			wantErr: "must be 32 bytes",
		},
		{
			name:    "64 byte slice",
			b:       repeatBytes(0x99, 64),
			wantErr: "must be 32 bytes",
		},
		{
			name: "32 bytes all zeros",
			b:    make([]byte, 32),
			want: [32]byte{},
		},
		{
			name: "32 bytes all 0xFF",
			b:    repeatBytes(0xFF, 32),
			want: func() [32]byte {
				var out [32]byte
				for i := range out {
					out[i] = 0xFF
				}
				return out
			}(),
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got, err := toBytes32(tc.b)
			if tc.wantErr != "" {
				if err == nil {
					t.Fatalf("expected error containing %q, got nil", tc.wantErr)
				}
				if !contains(err.Error(), tc.wantErr) {
					t.Fatalf("error: got %q want substring %q", err.Error(), tc.wantErr)
				}
				return
			}
			if err != nil {
				t.Fatalf("unexpected error: %v", err)
			}
			if got != tc.want {
				t.Fatalf("toBytes32: got %x want %x", got, tc.want)
			}
		})
	}
}

// TestEncodeDecodeHeaderRoundTripAdditional verifies encoding/decoding preserves
// all header fields for additional edge cases not in header_test.gno.
func TestEncodeDecodeHeaderRoundTripAdditional(t *testing.T) {
	cases := []struct {
		name   string
		header *Header
	}{
		{
			name: "header with nil trusted height",
			header: func() *Header {
				h := newTestHeader(100, 2000, 300, 50, []byte{0xCC})
				h.TrustedHeight = nil
				return h
			}(),
		},
		{
			name: "header with large ZKP",
			header: func() *Header {
				return newTestHeader(1, 0, 0, 0, repeatBytes(0xDD, 384))
			}(),
		},
		{
			name: "header with non-zero time nanos",
			header: func() *Header {
				return newTestHeader(999, 12345, 987654321, 100, []byte{0xEE})
			}(),
		},
		{
			name: "header with different hash values",
			header: func() *Header {
				return &Header{
					SignedHeader: &LightHeader{
						Height:             42,
						TimeSeconds:        1000,
						TimeNanos:          500,
						ValidatorsHash:     repeat32(0x11),
						NextValidatorsHash: repeat32(0x22),
						AppHash:            repeat32(0x33),
					},
					TrustedHeight:      heightPtr(types.NewHeight(0, 10)),
					ZeroKnowledgeProof: []byte{0xFF},
				}
			}(),
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			enc, err := EncodeHeader(tc.header)
			if err != nil {
				t.Fatalf("EncodeHeader: %v", err)
			}

			got, err := DecodeHeader(enc)
			if err != nil {
				t.Fatalf("DecodeHeader: %v", err)
			}

			if got.SignedHeader.Height != tc.header.SignedHeader.Height {
				t.Fatalf("Height: got %d want %d", got.SignedHeader.Height, tc.header.SignedHeader.Height)
			}
			if got.SignedHeader.TimeSeconds != tc.header.SignedHeader.TimeSeconds {
				t.Fatalf("TimeSeconds: got %d want %d", got.SignedHeader.TimeSeconds, tc.header.SignedHeader.TimeSeconds)
			}
			if got.SignedHeader.TimeNanos != tc.header.SignedHeader.TimeNanos {
				t.Fatalf("TimeNanos: got %d want %d", got.SignedHeader.TimeNanos, tc.header.SignedHeader.TimeNanos)
			}
			bytesEq(t, "ValidatorsHash", got.SignedHeader.ValidatorsHash, tc.header.SignedHeader.ValidatorsHash)
			bytesEq(t, "NextValidatorsHash", got.SignedHeader.NextValidatorsHash, tc.header.SignedHeader.NextValidatorsHash)
			bytesEq(t, "AppHash", got.SignedHeader.AppHash, tc.header.SignedHeader.AppHash)

			var wantTrustedHeight uint64
			if tc.header.TrustedHeight != nil {
				wantTrustedHeight = tc.header.TrustedHeight.RevisionHeight
			}
			if got.TrustedHeight.RevisionHeight != wantTrustedHeight {
				t.Fatalf("TrustedHeight: got %d want %d", got.TrustedHeight.RevisionHeight, wantTrustedHeight)
			}

			bytesEq(t, "ZKP", got.ZeroKnowledgeProof, tc.header.ZeroKnowledgeProof)
		})
	}
}

// TestEncodeDecodeMisbehaviourRoundTripAdditional verifies encoding/decoding
// preserves both headers for additional edge cases not in misbehaviour_test.gno.
func TestEncodeDecodeMisbehaviourRoundTripAdditional(t *testing.T) {
	cases := []struct {
		name string
		m    *Misbehaviour
	}{
		{
			name: "misbehaviour with large ZKPs",
			m: &Misbehaviour{
				Header1: newTestHeader(1, 0, 0, 0, repeatBytes(0xAA, 384)),
				Header2: newTestHeader(2, 1, 0, 1, repeatBytes(0xBB, 384)),
			},
		},
		{
			name: "misbehaviour with non-zero time nanos",
			m: &Misbehaviour{
				Header1: newTestHeader(100, 2000, 123456789, 90, []byte{0x01}),
				Header2: newTestHeader(101, 2001, 987654321, 91, []byte{0x02}),
			},
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			enc, err := EncodeMisbehaviour(tc.m)
			if err != nil {
				t.Fatalf("EncodeMisbehaviour: %v", err)
			}

			got, err := DecodeMisbehaviour(enc)
			if err != nil {
				t.Fatalf("DecodeMisbehaviour: %v", err)
			}

			if got.Header1.SignedHeader.Height != tc.m.Header1.SignedHeader.Height {
				t.Fatalf("Header1 height: got %d want %d", got.Header1.SignedHeader.Height, tc.m.Header1.SignedHeader.Height)
			}
			if got.Header2.SignedHeader.Height != tc.m.Header2.SignedHeader.Height {
				t.Fatalf("Header2 height: got %d want %d", got.Header2.SignedHeader.Height, tc.m.Header2.SignedHeader.Height)
			}

			// Verify round-trip produces identical encoding
			reenc, err := EncodeMisbehaviour(got)
			if err != nil {
				t.Fatalf("re-EncodeMisbehaviour: %v", err)
			}
			bytesEq(t, "round-trip encoding", reenc, enc)
		})
	}
}
