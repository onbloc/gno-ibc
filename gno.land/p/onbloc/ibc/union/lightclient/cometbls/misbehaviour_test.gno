package cometbls

import (
	"testing"
	"time"

	"gno.land/p/aib/encoding/proto"
)

func TestEncodeDecodeMisbehaviourRoundTrip(t *testing.T) {
	m := &Misbehaviour{
		Header1: newTestHeader(100, 2000, 0, 90, []byte{0x01, 0x02}),
		Header2: newTestHeader(101, 2001, 0, 91, []byte{0x03, 0x04}),
	}

	enc, err := EncodeMisbehaviour(m)
	if err != nil {
		t.Fatalf("EncodeMisbehaviour: %v", err)
	}

	got, err := DecodeMisbehaviour(enc)
	if err != nil {
		t.Fatalf("DecodeMisbehaviour: %v", err)
	}
	if got.Header1 == nil || got.Header2 == nil {
		t.Fatal("expected both headers to be present")
	}
	if got.Header1.SignedHeader.Height != 100 {
		t.Errorf("Header1 height: got %d want 100", got.Header1.SignedHeader.Height)
	}
	if got.Header2.SignedHeader.Height != 101 {
		t.Errorf("Header2 height: got %d want 101", got.Header2.SignedHeader.Height)
	}
	if got.Header1.TrustedHeight.RevisionHeight != 90 {
		t.Errorf("Header1 trusted height: got %d want 90", got.Header1.TrustedHeight.RevisionHeight)
	}
	bytesEq(t, "Header2 ZKP", got.Header2.ZeroKnowledgeProof, []byte{0x03, 0x04})

	// Re-encoding the decoded value must reproduce the wire bytes exactly.
	reenc, err := EncodeMisbehaviour(got)
	if err != nil {
		t.Fatalf("re-EncodeMisbehaviour: %v", err)
	}
	bytesEq(t, "Misbehaviour round-trip", reenc, enc)
}

func TestEncodeMisbehaviourNil(t *testing.T) {
	if _, err := EncodeMisbehaviour(nil); err == nil {
		t.Fatal("expected error for nil misbehaviour")
	}
}

func TestDecodeMisbehaviourMissingHeader(t *testing.T) {
	// Only field 1 (Header1) present; Header2 missing must be rejected.
	h1, err := EncodeHeader(newTestHeader(100, 2000, 0, 90, []byte{0x01}))
	if err != nil {
		t.Fatalf("EncodeHeader: %v", err)
	}
	var buf []byte
	buf = proto.AppendLengthDelimited(buf, 1, h1)

	if _, err := DecodeMisbehaviour(buf); err == nil {
		t.Fatal("expected error for misbehaviour missing a header")
	}
}

func TestDecodeMisbehaviourBadHeaderBytes(t *testing.T) {
	// Field 1 carries bytes that are too short to be a valid ABI header.
	var buf []byte
	buf = proto.AppendLengthDelimited(buf, 1, []byte{0x01, 0x02, 0x03})

	if _, err := DecodeMisbehaviour(buf); err == nil {
		t.Fatal("expected error for undecodable header bytes")
	}
}

func TestMisbehaviourGetTimeReturnsLatestHeaderTime(t *testing.T) {
	cases := []struct {
		name string
		h1   *Header
		h2   *Header
		want time.Time
	}{
		{
			name: "header1 later",
			h1:   newTestHeader(100, 2001, 0, 90, []byte{0x01}),
			h2:   newTestHeader(99, 2000, 999, 89, []byte{0x02}),
			want: time.Unix(2001, 0).UTC(),
		},
		{
			name: "header2 later",
			h1:   newTestHeader(100, 2000, 0, 90, []byte{0x01}),
			h2:   newTestHeader(99, 2000, 1, 89, []byte{0x02}),
			want: time.Unix(2000, 1).UTC(),
		},
		{
			name: "equal returns header2 time",
			h1:   newTestHeader(100, 2000, 7, 90, []byte{0x01}),
			h2:   newTestHeader(99, 2000, 7, 89, []byte{0x02}),
			want: time.Unix(2000, 7).UTC(),
		},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			m := &Misbehaviour{Header1: tc.h1, Header2: tc.h2}
			if got := m.GetTime(); !got.Equal(tc.want) {
				t.Fatalf("GetTime: got %s want %s", got, tc.want)
			}
		})
	}
}
