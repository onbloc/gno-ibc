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

func TestVerifyMisbehaviourRejectsInvalidHeaderSequenceBeforeProofVerification(t *testing.T) {
	// Union reference: verify_misbehaviour first rejects HeaderA lower than
	// HeaderB before running header/proof verification.
	c := newTestClient(t)
	c.clientState.TrustingPeriod = 10_000_000_000
	m := &Misbehaviour{
		Header1: updateStateTestHeader(100, 101, testNow+1_000_000_000),
		Header2: updateStateTestHeader(100, 102, testNow+2_000_000_000),
	}

	err := c.verifyMisbehaviour(m, time.Unix(int64(testNow/1_000_000_000)+3, 0))

	requireErrorContains(t, err, ErrInvalidMisbehaviourHeaderSequence.Error())
}

func TestIsMisbehaviourPair(t *testing.T) {
	cases := []struct {
		name string
		a    *Header
		b    *Header
		want bool
	}{
		{
			name: "same height identical headers is not misbehaviour",
			a:    updateStateTestHeader(100, 101, testNow+1_000_000_000),
			b:    updateStateTestHeader(100, 101, testNow+1_000_000_000),
			want: false,
		},
		{
			name: "same height conflicting app hash is misbehaviour",
			a:    updateStateTestHeader(100, 101, testNow+1_000_000_000),
			b: func() *Header {
				h := updateStateTestHeader(100, 101, testNow+1_000_000_000)
				h.SignedHeader.AppHash[0] ^= 0xFF
				return h
			}(),
			want: true,
		},
		{
			name: "same height conflicting timestamp is misbehaviour",
			a:    updateStateTestHeader(100, 101, testNow+1_000_000_000),
			b:    updateStateTestHeader(100, 101, testNow+2_000_000_000),
			want: true,
		},
		{
			name: "different height non-increasing time is misbehaviour",
			a:    updateStateTestHeader(100, 102, testNow+1_000_000_000),
			b:    updateStateTestHeader(100, 101, testNow+2_000_000_000),
			want: true,
		},
		{
			name: "different height increasing time is not misbehaviour",
			a:    updateStateTestHeader(100, 102, testNow+2_000_000_000),
			b:    updateStateTestHeader(100, 101, testNow+1_000_000_000),
			want: false,
		},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			if got := isMisbehaviourPair(tc.a, tc.b); got != tc.want {
				t.Fatalf("isMisbehaviourPair: got %v want %v", got, tc.want)
			}
		})
	}
}

// Regression test: resubmitting one already-valid header as both Header1 and
// Header2 used to freeze the client. A genuinely conflicting pair still must.
func TestMisbehaviourRejectsIdenticalHeaderResubmission(t *testing.T) {
	c, h := newDevnetMisbehaviourHeaderClient(t)

	trustedHeight := *h.TrustedHeight
	resubmitted := &Header{
		SignedHeader:       cloneLightHeader(h.SignedHeader),
		TrustedHeight:      &trustedHeight,
		ZeroKnowledgeProof: append([]byte(nil), h.ZeroKnowledgeProof...),
	}

	var caller, relayer address
	encoded, err := EncodeMisbehaviour(&Misbehaviour{Header1: h, Header2: resubmitted})
	if err != nil {
		t.Fatalf("EncodeMisbehaviour: %v", err)
	}

	if _, err := c.Misbehaviour(caller, encoded, relayer); err == nil {
		t.Fatal("expected resubmission of an identical header to be rejected")
	} else {
		requireErrorContains(t, err, ErrMisbehaviourNotFound.Error())
	}

	if !c.clientState.FrozenHeight.IsZero() {
		t.Fatal("client must not be frozen by resubmitting an identical header")
	}

	// A conflicting header at the same height must still count as misbehaviour.
	conflicting := cloneLightHeaderWith(h.SignedHeader, func(lh *LightHeader) { lh.AppHash[0] ^= 0xFF })
	if !isMisbehaviourPair(h, &Header{SignedHeader: conflicting, TrustedHeight: &trustedHeight}) {
		t.Fatal("conflicting headers at the same height must be treated as misbehaviour")
	}
}
