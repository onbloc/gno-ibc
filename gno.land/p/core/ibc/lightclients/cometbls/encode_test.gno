package cometbls

import "testing"

// Exact-bytes tests: each test mirrors its decode_test.gno counterpart —
// same struct values and proto bytes, direction reversed.

func TestEncodeHeight(t *testing.T) {
	tests := []struct {
		name string
		h    Height
		want []byte
	}{
		{
			name: "zero height encodes to empty",
			h:    Height{},
			want: []byte{},
		},
		{
			// field 1 (revision_number=1): tag=0x08, varint(1)=0x01
			// field 2 (revision_height=100): tag=0x10, varint(100)=0x64
			name: "revision_number=1 revision_height=100",
			h:    Height{RevisionNumber: 1, RevisionHeight: 100},
			want: []byte{0x08, 0x01, 0x10, 0x64},
		},
		{
			// field 1 (revision_number=0): omitted by proto3
			// field 2 (revision_height=300): tag=0x10, varint(300)=[0xAC,0x02]
			name: "revision_height=300 only",
			h:    Height{RevisionNumber: 0, RevisionHeight: 300},
			want: []byte{0x10, 0xAC, 0x02},
		},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			got := EncodeHeight(tc.h)
			if len(got) != len(tc.want) {
				t.Fatalf("got %v want %v", got, tc.want)
			}
			for i := range got {
				if got[i] != tc.want[i] {
					t.Fatalf("got %v want %v", got, tc.want)
				}
			}
		})
	}
}

func TestEncodeMerkleRoot(t *testing.T) {
	// field 1 (hash): tag=0x0A, len=4, [0xDE,0xAD,0xBE,0xEF]
	got := EncodeMerkleRoot(MerkleRoot{Hash: []byte{0xDE, 0xAD, 0xBE, 0xEF}})
	want := []byte{0x0A, 0x04, 0xDE, 0xAD, 0xBE, 0xEF}
	bytesEq(t, "EncodeMerkleRoot", got, want)
}

func TestEncodeClientState(t *testing.T) {
	// ClientState{ChainID:"abc", TrustingPeriod:1000, MaxClockDrift:100, LatestHeight:{1,50}}
	// FrozenHeight is zero — omitted by proto3 (no 2a00 in output).
	cs := ClientState{
		ChainID:        "abc",
		TrustingPeriod: 1000,
		MaxClockDrift:  100,
		LatestHeight:   Height{RevisionNumber: 1, RevisionHeight: 50},
	}
	want := []byte{
		0x0A, 0x03, 0x61, 0x62, 0x63, // field 1: "abc"
		0x10, 0xE8, 0x07, // field 2: 1000
		0x20, 0x64, // field 4: 100
		0x32, 0x04, 0x08, 0x01, 0x10, 0x32, // field 6: Height{1,50}
	}
	bytesEq(t, "EncodeClientState", EncodeClientState(cs), want)
}

func TestEncodeConsensusState(t *testing.T) {
	// ConsensusState{Timestamp:500, Root:{[0xAB]}, NextValidatorsHash:[0xCD,0xEF]}
	cs := ConsensusState{
		Timestamp:          500,
		Root:               MerkleRoot{Hash: []byte{0xAB}},
		NextValidatorsHash: []byte{0xCD, 0xEF},
	}
	want := []byte{
		0x08, 0xF4, 0x03, // field 1: timestamp=500
		0x12, 0x03, 0x0A, 0x01, 0xAB, // field 2: root (MerkleRoot{[0xAB]})
		0x1A, 0x02, 0xCD, 0xEF, // field 3: next_validators_hash
	}
	bytesEq(t, "EncodeConsensusState", EncodeConsensusState(cs), want)
}

func TestEncodeLightHeader(t *testing.T) {
	t.Run("zero_nanos", func(t *testing.T) {
		lh := LightHeader{
			Height:             42,
			TimeSeconds:        1000,
			TimeNanos:          0,
			ValidatorsHash:     []byte{0x01, 0x02},
			NextValidatorsHash: []byte{0x03, 0x04},
			AppHash:            []byte{0x05},
		}
		want := []byte{
			0x08, 0x2A, // field 1: height=42
			0x12, 0x03, 0x08, 0xE8, 0x07, // field 2: time (seconds=1000, nanos=0 omitted)
			0x1A, 0x02, 0x01, 0x02, // field 3: validators_hash
			0x22, 0x02, 0x03, 0x04, // field 4: next_validators_hash
			0x2A, 0x01, 0x05, // field 5: app_hash
		}
		bytesEq(t, "EncodeLightHeader zero_nanos", EncodeLightHeader(lh), want)
	})

	t.Run("nonzero_nanos", func(t *testing.T) {
		lh := LightHeader{
			Height:             42,
			TimeSeconds:        1000,
			TimeNanos:          500,
			ValidatorsHash:     []byte{0x01, 0x02},
			NextValidatorsHash: []byte{0x03, 0x04},
			AppHash:            []byte{0x05},
		}
		want := []byte{
			0x08, 0x2A, // field 1: height=42
			0x12, 0x06, 0x08, 0xE8, 0x07, 0x10, 0xF4, 0x03, // field 2: time (s=1000,ns=500)
			0x1A, 0x02, 0x01, 0x02, // field 3
			0x22, 0x02, 0x03, 0x04, // field 4
			0x2A, 0x01, 0x05, // field 5
		}
		bytesEq(t, "EncodeLightHeader nonzero_nanos", EncodeLightHeader(lh), want)
	})
}

func TestEncodeHeader(t *testing.T) {
	h := Header{
		SignedHeader:       LightHeader{Height: 7},
		TrustedHeight:      Height{RevisionNumber: 1, RevisionHeight: 10},
		ZeroKnowledgeProof: []byte{0xAA, 0xBB},
	}
	want := []byte{
		0x0A, 0x02, 0x08, 0x07, // field 1: signed_header (LightHeader{Height:7})
		0x12, 0x04, 0x08, 0x01, 0x10, 0x0A, // field 2: trusted_height {1,10}
		0x1A, 0x02, 0xAA, 0xBB, // field 3: zero_knowledge_proof
	}
	bytesEq(t, "EncodeHeader", EncodeHeader(h), want)
}

func TestEncodeMisbehaviour(t *testing.T) {
	m := Misbehaviour{
		HeaderA: Header{SignedHeader: LightHeader{Height: 1}},
		HeaderB: Header{SignedHeader: LightHeader{Height: 2}},
	}
	want := []byte{
		0x0A, 0x04, 0x0A, 0x02, 0x08, 0x01, // field 1: header_a
		0x12, 0x04, 0x0A, 0x02, 0x08, 0x02, // field 2: header_b
	}
	bytesEq(t, "EncodeMisbehaviour", EncodeMisbehaviour(m), want)
}

// --- Round-trip + fixture cross-validation ---

// TestEncodeDecodeClientStateFixture encodes the Union ClientState fixture values,
// decodes the result, and verifies struct equality. (Byte-exact match is not
// required here because our encoder omits the empty frozen_height field, whereas
// the Union fixture includes an explicit 2a00 sentinel for it.)
func TestEncodeDecodeClientStateFixture(t *testing.T) {
	original := ClientState{
		ChainID:        "oogabooga",
		TrustingPeriod: 12345,
		MaxClockDrift:  67890,
		LatestHeight:   Height{RevisionNumber: 0, RevisionHeight: 1337},
	}
	got, err := DecodeClientState(EncodeClientState(original))
	if err != nil {
		t.Fatalf("DecodeClientState: %v", err)
	}
	if got.ChainID != original.ChainID {
		t.Fatalf("ChainID: got %q want %q", got.ChainID, original.ChainID)
	}
	if got.TrustingPeriod != original.TrustingPeriod {
		t.Fatalf("TrustingPeriod: got %d want %d", got.TrustingPeriod, original.TrustingPeriod)
	}
	if got.MaxClockDrift != original.MaxClockDrift {
		t.Fatalf("MaxClockDrift: got %d want %d", got.MaxClockDrift, original.MaxClockDrift)
	}
	if got.IsFrozen() {
		t.Fatalf("FrozenHeight should be zero, got %+v", got.FrozenHeight)
	}
	if got.LatestHeight != original.LatestHeight {
		t.Fatalf("LatestHeight: got %+v want %+v", got.LatestHeight, original.LatestHeight)
	}
}

// TestEncodeConsensusStateFixture verifies byte-exact output against the Union
// proto_iso ConsensusState fixture.
func TestEncodeConsensusStateFixture(t *testing.T) {
	cs := ConsensusState{
		Timestamp:          123456789,
		Root:               MerkleRoot{Hash: aaHash},
		NextValidatorsHash: aaHash,
	}
	want := mustHex(
		"08959aef3a" +
			"12220a20" + "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" +
			"1a20" + "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
	)
	bytesEq(t, "EncodeConsensusStateFixture", EncodeConsensusState(cs), want)
}

// TestEncodeLightHeaderFixture verifies byte-exact output against the Union
// proto_iso LightHeader fixture (as embedded in the Header fixture).
func TestEncodeLightHeaderFixture(t *testing.T) {
	lh := LightHeader{
		Height:             0xDEADC0DE,
		TimeSeconds:        1,
		TimeNanos:          1,
		ValidatorsHash:     aaHash,
		NextValidatorsHash: aaHash,
		AppHash:            aaHash,
	}
	want := mustHex(
		"08de81b7f50d" +
			"1204080110011a20" + "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" +
			"2220" + "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" +
			"2a20" + "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
	)
	bytesEq(t, "EncodeLightHeaderFixture", EncodeLightHeader(lh), want)
}

// TestEncodeHeaderFixture verifies byte-exact output against the Union proto_iso
// Header fixture.
func TestEncodeHeaderFixture(t *testing.T) {
	h := Header{
		SignedHeader: LightHeader{
			Height:             0xDEADC0DE,
			TimeSeconds:        1,
			TimeNanos:          1,
			ValidatorsHash:     aaHash,
			NextValidatorsHash: aaHash,
			AppHash:            aaHash,
		},
		TrustedHeight:      Height{RevisionNumber: 0, RevisionHeight: 100},
		ZeroKnowledgeProof: []byte("zkp"),
	}
	want := mustHex(
		"0a72" +
			"08de81b7f50d" +
			"1204080110011a20" + "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" +
			"2220" + "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" +
			"2a20" + "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" +
			"120210641a037a6b70",
	)
	bytesEq(t, "EncodeHeaderFixture", EncodeHeader(h), want)
}

// TestEncodeMisbehaviourFixture verifies byte-exact output against the Union
// proto_iso Misbehaviour fixture (two identical Header fixtures).
func TestEncodeMisbehaviourFixture(t *testing.T) {
	hdr := Header{
		SignedHeader: LightHeader{
			Height:             0xDEADC0DE,
			TimeSeconds:        1,
			TimeNanos:          1,
			ValidatorsHash:     aaHash,
			NextValidatorsHash: aaHash,
			AppHash:            aaHash,
		},
		TrustedHeight:      Height{RevisionNumber: 0, RevisionHeight: 100},
		ZeroKnowledgeProof: []byte("zkp"),
	}
	hdrHex := "0a72" +
		"08de81b7f50d" +
		"1204080110011a20" + "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" +
		"2220" + "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" +
		"2a20" + "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" +
		"120210641a037a6b70"
	want := mustHex("0a7d" + hdrHex + "127d" + hdrHex)
	bytesEq(t, "EncodeMisbehaviourFixture", EncodeMisbehaviour(Misbehaviour{HeaderA: hdr, HeaderB: hdr}), want)
}
