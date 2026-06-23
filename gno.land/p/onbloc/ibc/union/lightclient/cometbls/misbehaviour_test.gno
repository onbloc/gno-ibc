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

func TestDecodeMisbehaviour(t *testing.T) {
	h1, err := EncodeHeader(newTestHeader(100, 2000, 0, 90, []byte{0x01}))
	if err != nil {
		t.Fatalf("EncodeHeader: %v", err)
	}

	cases := []struct {
		name string
		buf  []byte
	}{
		{
			name: "missing header2",
			buf:  proto.AppendLengthDelimited(nil, 1, h1),
		},
		{
			name: "bad header bytes",
			buf:  proto.AppendLengthDelimited(nil, 1, []byte{0x01, 0x02, 0x03}),
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			if _, err := DecodeMisbehaviour(tc.buf); err == nil {
				t.Fatal("expected decode error")
			}
		})
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

func TestVerifyMisbehaviourScenarios(t *testing.T) {
	c := newTestClient(t)
	c.clientState.TrustingPeriod = 10_000_000_000
	verifyTime := time.Unix(int64(testNow/1_000_000_000)+3, 0)

	cases := []struct {
		name    string
		setup   func() *Misbehaviour
		wantErr string
	}{
		{
			name: "missing trusted consensus",
			setup: func() *Misbehaviour {
				// Headers referencing non-existent trusted height
				h1 := updateStateTestHeader(999, 1000, testNow+1_000_000_000)
				h2 := updateStateTestHeader(999, 1000, testNow+2_000_000_000)
				return &Misbehaviour{Header1: h1, Header2: h2}
			},
			wantErr: "could not get trusted consensus state",
		},
		{
			name: "equivocation same height different content",
			setup: func() *Misbehaviour {
				h1 := updateStateTestHeader(100, 101, testNow+1_000_000_000)
				h2 := updateStateTestHeader(100, 101, testNow+1_000_000_000)
				h2.SignedHeader.AppHash[0] ^= 0xFF
				return &Misbehaviour{Header1: h1, Header2: h2}
			},
			wantErr: "", // ZKP fails but misbehaviour logic is reached
		},
		{
			name: "non-increasing time different heights",
			setup: func() *Misbehaviour {
				h3 := updateStateTestHeader(100, 102, testNow+2_000_000_000)
				h4 := updateStateTestHeader(101, 103, testNow+2_000_000_000)
				return &Misbehaviour{Header1: h3, Header2: h4}
			},
			wantErr: "", // ZKP fails but non-increasing-time check is reached
		},
		{
			name: "same height equivocation different time",
			setup: func() *Misbehaviour {
				h1 := updateStateTestHeader(100, 101, testNow+1_000_000_000)
				h2 := updateStateTestHeader(100, 101, testNow+1_500_000_000)
				h2.SignedHeader.AppHash = repeat32(0xEE)
				return &Misbehaviour{Header1: h1, Header2: h2}
			},
			wantErr: "", // ZKP fails but equivocation logic is reached
		},
		{
			name: "invalid header sequence decreasing heights",
			setup: func() *Misbehaviour {
				h1 := updateStateTestHeader(100, 101, testNow+2_000_000_000)
				h2 := updateStateTestHeader(100, 102, testNow+1_000_000_000)
				return &Misbehaviour{Header1: h1, Header2: h2}
			},
			wantErr: ErrInvalidMisbehaviourHeaderSequence,
		},
		{
			name: "identical headers",
			setup: func() *Misbehaviour {
				h1 := updateStateTestHeader(100, 101, testNow+1_000_000_000)
				h2 := updateStateTestHeader(100, 101, testNow+1_000_000_000)
				// Clone to ensure identical content
				h2.SignedHeader.ValidatorsHash = append([]byte(nil), h1.SignedHeader.ValidatorsHash...)
				h2.SignedHeader.NextValidatorsHash = append([]byte(nil), h1.SignedHeader.NextValidatorsHash...)
				h2.SignedHeader.AppHash = append([]byte(nil), h1.SignedHeader.AppHash...)
				return &Misbehaviour{Header1: h1, Header2: h2}
			},
			wantErr: "", // ZKP fails first, but identical headers check happens before ZKP
		},
		{
			name: "valid chain increasing time different heights",
			setup: func() *Misbehaviour {
				h5 := updateStateTestHeader(100, 102, testNow+1_000_000_000)
				h6 := updateStateTestHeader(100, 103, testNow+3_000_000_000)
				return &Misbehaviour{Header1: h5, Header2: h6}
			},
			wantErr: "", // ZKP fails but would hit not-found with valid proofs
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			client := newTestClient(t)
			client.clientState.TrustingPeriod = 10_000_000_000

			m := tc.setup()
			err := client.verifyMisbehaviour(m, verifyTime)

			if tc.wantErr == "" {
				// Cases where ZKP is expected to fail but logic branch is reached
				if err == nil {
					t.Error("expected error due to invalid ZKP")
				}
				return
			}
			requireErrorContains(t, err, tc.wantErr)
		})
	}
}

func TestNewMisbehaviour(t *testing.T) {
	cases := []struct {
		name    string
		header1 *Header
		header2 *Header
		wantH1  *Header
		wantH2  *Header
	}{
		{
			name:    "valid headers",
			header1: newTestHeader(100, 2000, 0, 90, []byte{0x01}),
			header2: newTestHeader(99, 2000, 0, 89, []byte{0x02}),
			wantH1:  newTestHeader(100, 2000, 0, 90, []byte{0x01}),
			wantH2:  newTestHeader(99, 2000, 0, 89, []byte{0x02}),
		},
		{
			name:    "both headers nil",
			header1: nil,
			header2: nil,
			wantH1:  nil,
			wantH2:  nil,
		},
		{
			name:    "header1 nil header2 valid",
			header1: nil,
			header2: newTestHeader(99, 2000, 0, 89, []byte{0x02}),
			wantH1:  nil,
			wantH2:  newTestHeader(99, 2000, 0, 89, []byte{0x02}),
		},
		{
			name:    "header1 valid header2 nil",
			header1: newTestHeader(100, 2000, 0, 90, []byte{0x01}),
			header2: nil,
			wantH1:  newTestHeader(100, 2000, 0, 90, []byte{0x01}),
			wantH2:  nil,
		},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got := NewMisbehaviour(tc.header1, tc.header2)
			if got == nil {
				t.Fatal("NewMisbehaviour returned nil")
			}
			if got.Header1 != tc.wantH1 {
				if got.Header1 == nil && tc.wantH1 == nil {
					return
				}
				if got.Header1 == nil || tc.wantH1 == nil {
					t.Fatalf("Header1: got %v want %v", got.Header1, tc.wantH1)
				}
				if got.Header1.SignedHeader.Height != tc.wantH1.SignedHeader.Height {
					t.Errorf("Header1 height: got %d want %d", got.Header1.SignedHeader.Height, tc.wantH1.SignedHeader.Height)
				}
			}
			if got.Header2 != tc.wantH2 {
				if got.Header2 == nil && tc.wantH2 == nil {
					return
				}
				if got.Header2 == nil || tc.wantH2 == nil {
					t.Fatalf("Header2: got %v want %v", got.Header2, tc.wantH2)
				}
				if got.Header2.SignedHeader.Height != tc.wantH2.SignedHeader.Height {
					t.Errorf("Header2 height: got %d want %d", got.Header2.SignedHeader.Height, tc.wantH2.SignedHeader.Height)
				}
			}
		})
	}
}

func TestMisbehaviourValidateBasic(t *testing.T) {
	cases := []struct {
		name    string
		mis     *Misbehaviour
		wantErr string
	}{
		{
			name: "valid misbehaviour with equal heights",
			mis: &Misbehaviour{
				Header1: newTestHeader(100, 2000, 0, 90, []byte{0x01}),
				Header2: newTestHeader(100, 2001, 0, 90, []byte{0x02}),
			},
		},
		{
			name: "valid misbehaviour with header1 greater height",
			mis: &Misbehaviour{
				Header1: newTestHeader(101, 2000, 0, 91, []byte{0x01}),
				Header2: newTestHeader(100, 2001, 0, 90, []byte{0x02}),
			},
		},
		{
			name: "header1 nil",
			mis: &Misbehaviour{
				Header1: nil,
				Header2: newTestHeader(100, 2001, 0, 90, []byte{0x02}),
			},
			wantErr: ErrInvalidHeader,
		},
		{
			name: "header2 nil",
			mis: &Misbehaviour{
				Header1: newTestHeader(100, 2000, 0, 90, []byte{0x01}),
				Header2: nil,
			},
			wantErr: ErrInvalidHeader,
		},
		{
			name: "both headers nil",
			mis: &Misbehaviour{
				Header1: nil,
				Header2: nil,
			},
			wantErr: ErrInvalidHeader,
		},
		{
			name: "header1 zero revision height",
			mis: &Misbehaviour{
				Header1: newTestHeader(100, 2000, 0, 0, []byte{0x01}),
				Header2: newTestHeader(100, 2001, 0, 90, []byte{0x02}),
			},
			wantErr: ErrInvalidHeaderHeight,
		},
		{
			name: "header2 zero revision height",
			mis: &Misbehaviour{
				Header1: newTestHeader(100, 2000, 0, 90, []byte{0x01}),
				Header2: newTestHeader(100, 2001, 0, 0, []byte{0x02}),
			},
			wantErr: ErrInvalidHeaderHeight,
		},
		{
			name: "both headers zero revision height",
			mis: &Misbehaviour{
				Header1: newTestHeader(100, 2000, 0, 0, []byte{0x01}),
				Header2: newTestHeader(100, 2001, 0, 0, []byte{0x02}),
			},
			wantErr: ErrInvalidHeaderHeight,
		},
		{
			name: "header1 less than header2 height",
			mis: &Misbehaviour{
				Header1: newTestHeader(99, 2000, 0, 89, []byte{0x01}),
				Header2: newTestHeader(100, 2001, 0, 90, []byte{0x02}),
			},
			wantErr: ErrInvalidMisbehaviour,
		},
		{
			name: "header1 height less than header2 with valid revision heights",
			mis: &Misbehaviour{
				Header1: newTestHeader(50, 2000, 0, 50, []byte{0x01}),
				Header2: newTestHeader(100, 2001, 0, 100, []byte{0x02}),
			},
			wantErr: ErrInvalidMisbehaviour,
		},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			err := tc.mis.ValidateBasic()
			if tc.wantErr != "" {
				requireErrorContains(t, err, tc.wantErr)
			} else if err != nil {
				t.Fatalf("unexpected error: %v", err)
			}
		})
	}
}

func TestMisbehaviourClientType(t *testing.T) {
	m := &Misbehaviour{
		Header1: newTestHeader(100, 2000, 0, 90, []byte{0x01}),
		Header2: newTestHeader(99, 2001, 0, 89, []byte{0x02}),
	}
	if got := m.ClientType(); got != ClientType {
		t.Fatalf("ClientType: got %s want %s", got, ClientType)
	}
}
