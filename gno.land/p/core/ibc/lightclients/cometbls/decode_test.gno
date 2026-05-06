package cometbls

import (
	"bytes"
	"encoding/hex"
	"testing"
)

// Proto encoding notes for test vectors:
//   tag = (field_number << 3) | wire_type  (0=varint, 2=len-delimited)
//   varint: 7 bits/byte, LSB first, bit7 set when more bytes follow
//   proto3 omits fields whose value is the zero value

func bytesEq(t *testing.T, label string, got, want []byte) {
	t.Helper()
	if !bytes.Equal(got, want) {
		t.Fatalf("%s: got %v want %v", label, got, want)
	}
}

func mustHex(s string) []byte {
	b, err := hex.DecodeString(s)
	if err != nil {
		panic("mustHex: " + err.Error())
	}
	return b
}

// aaHash is 32 bytes of 0xAA, used as validators/app hash in Union's test fixtures.
var aaHash = bytes.Repeat([]byte{0xAA}, 32)

// --- 단위 테스트: 직접 작성한 최소 proto 바이트 ---

func TestDecodeHeight(t *testing.T) {
	tests := []struct {
		name string
		buf  []byte
		want Height
	}{
		{
			name: "empty buf gives zero height",
			buf:  []byte{},
			want: Height{},
		},
		{
			// field 1 (revision_number): tag=0x08, varint(1)=0x01
			// field 2 (revision_height): tag=0x10, varint(100)=0x64
			name: "revision_number=1 revision_height=100",
			buf:  []byte{0x08, 0x01, 0x10, 0x64},
			want: Height{RevisionNumber: 1, RevisionHeight: 100},
		},
		{
			// field 2 only (revision_number=0 omitted by proto3)
			// tag=0x10, varint(300): 300%128=44 → 0xAC (cont), 300>>7=2 → 0x02
			name: "revision_height=300 only",
			buf:  []byte{0x10, 0xAC, 0x02},
			want: Height{RevisionNumber: 0, RevisionHeight: 300},
		},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			got, err := DecodeHeight(tc.buf)
			if err != nil {
				t.Fatalf("unexpected error: %v", err)
			}
			if got != tc.want {
				t.Fatalf("got %+v want %+v", got, tc.want)
			}
		})
	}
}

func TestDecodeMerkleRoot(t *testing.T) {
	// field 1 (hash): tag=(1<<3)|2=0x0A, len=4, bytes=[0xDE,0xAD,0xBE,0xEF]
	buf := []byte{0x0A, 0x04, 0xDE, 0xAD, 0xBE, 0xEF}
	got, err := DecodeMerkleRoot(buf)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	bytesEq(t, "hash", got.Hash, []byte{0xDE, 0xAD, 0xBE, 0xEF})
}

func TestDecodeClientState(t *testing.T) {
	// ClientState{ChainID:"abc", TrustingPeriod:1000, MaxClockDrift:100, LatestHeight:{1,50}}
	//
	// field 1 (chain_id "abc"):    tag=0x0A len=3 [0x61,0x62,0x63]
	// field 2 (trusting_period):   tag=0x10 varint(1000)=[0xE8,0x07]
	// field 4 (max_clock_drift):   tag=0x20 varint(100)=0x64
	// field 5 (frozen_height):     omitted (zero value)
	// field 6 (latest_height):     tag=0x32 len=4 embedded Height{1,50}
	//   Height{1,50}: [0x08,0x01,0x10,0x32]
	buf := []byte{
		0x0A, 0x03, 0x61, 0x62, 0x63, // field 1: "abc"
		0x10, 0xE8, 0x07,              // field 2: 1000
		0x20, 0x64,                    // field 4: 100
		0x32, 0x04, 0x08, 0x01, 0x10, 0x32, // field 6: Height{1,50}
	}
	got, err := DecodeClientState(buf)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if got.ChainID != "abc" {
		t.Fatalf("ChainID: got %q want %q", got.ChainID, "abc")
	}
	if got.TrustingPeriod != 1000 {
		t.Fatalf("TrustingPeriod: got %d want 1000", got.TrustingPeriod)
	}
	if got.MaxClockDrift != 100 {
		t.Fatalf("MaxClockDrift: got %d want 100", got.MaxClockDrift)
	}
	if got.IsFrozen() {
		t.Fatal("FrozenHeight should be zero")
	}
	want := Height{RevisionNumber: 1, RevisionHeight: 50}
	if got.LatestHeight != want {
		t.Fatalf("LatestHeight: got %+v want %+v", got.LatestHeight, want)
	}
}

func TestDecodeConsensusState(t *testing.T) {
	// ConsensusState{Timestamp:500, Root:{[0xAB]}, NextValidatorsHash:[0xCD,0xEF]}
	//
	// field 1 (timestamp): tag=0x08 varint(500)=[0xF4,0x03]
	//   500%128=116→0xF4(cont), 500>>7=3→0x03
	// field 2 (root embedded): tag=0x12 len=3 [0x0A,0x01,0xAB]
	//   inner MerkleRoot: field1 tag=0x0A len=1 [0xAB]
	// field 3 (next_validators_hash): tag=0x1A len=2 [0xCD,0xEF]
	buf := []byte{
		0x08, 0xF4, 0x03,              // field 1: timestamp=500
		0x12, 0x03, 0x0A, 0x01, 0xAB, // field 2: root
		0x1A, 0x02, 0xCD, 0xEF,       // field 3: next_validators_hash
	}
	got, err := DecodeConsensusState(buf)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if got.Timestamp != 500 {
		t.Fatalf("Timestamp: got %d want 500", got.Timestamp)
	}
	bytesEq(t, "Root.Hash", got.Root.Hash, []byte{0xAB})
	bytesEq(t, "NextValidatorsHash", got.NextValidatorsHash, []byte{0xCD, 0xEF})
}

func TestDecodeLightHeader(t *testing.T) {
	t.Run("zero_nanos", func(t *testing.T) {
		// LightHeader{Height:42, TimeSeconds:1000, TimeNanos:0,
		//   ValidatorsHash:[0x01,0x02], NextValidatorsHash:[0x03,0x04], AppHash:[0x05]}
		//
		// field 1 (height):  tag=0x08 varint(42)=0x2A
		// field 2 (time):    tag=0x12 len=3 embedded Timestamp
		//   inner: field1 tag=0x08 varint(1000)=[0xE8,0x07] (nanos=0 omitted)
		// field 3 (validators_hash):      tag=0x1A len=2 [0x01,0x02]
		// field 4 (next_validators_hash): tag=0x22 len=2 [0x03,0x04]
		// field 5 (app_hash):             tag=0x2A len=1 [0x05]
		buf := []byte{
			0x08, 0x2A,                   // field 1: height=42
			0x12, 0x03, 0x08, 0xE8, 0x07, // field 2: time (seconds=1000)
			0x1A, 0x02, 0x01, 0x02,       // field 3: validators_hash
			0x22, 0x02, 0x03, 0x04,       // field 4: next_validators_hash
			0x2A, 0x01, 0x05,             // field 5: app_hash
		}
		got, err := DecodeLightHeader(buf)
		if err != nil {
			t.Fatalf("unexpected error: %v", err)
		}
		if got.Height != 42 {
			t.Fatalf("Height: got %d want 42", got.Height)
		}
		if got.TimeSeconds != 1000 {
			t.Fatalf("TimeSeconds: got %d want 1000", got.TimeSeconds)
		}
		if got.TimeNanos != 0 {
			t.Fatalf("TimeNanos: got %d want 0", got.TimeNanos)
		}
		bytesEq(t, "ValidatorsHash", got.ValidatorsHash, []byte{0x01, 0x02})
		bytesEq(t, "NextValidatorsHash", got.NextValidatorsHash, []byte{0x03, 0x04})
		bytesEq(t, "AppHash", got.AppHash, []byte{0x05})
	})

	t.Run("nonzero_nanos", func(t *testing.T) {
		// Same but TimeNanos=500
		// Timestamp inner: field1=[0x08,0xE8,0x07] field2=tag=0x10 varint(500)=[0xF4,0x03] → 6 bytes
		buf := []byte{
			0x08, 0x2A,                               // field 1: height=42
			0x12, 0x06, 0x08, 0xE8, 0x07, 0x10, 0xF4, 0x03, // field 2: time (s=1000,ns=500)
			0x1A, 0x02, 0x01, 0x02,                   // field 3
			0x22, 0x02, 0x03, 0x04,                   // field 4
			0x2A, 0x01, 0x05,                         // field 5
		}
		got, err := DecodeLightHeader(buf)
		if err != nil {
			t.Fatalf("unexpected error: %v", err)
		}
		if got.TimeSeconds != 1000 {
			t.Fatalf("TimeSeconds: got %d want 1000", got.TimeSeconds)
		}
		if got.TimeNanos != 500 {
			t.Fatalf("TimeNanos: got %d want 500", got.TimeNanos)
		}
	})
}

func TestDecodeHeader(t *testing.T) {
	// Header{SignedHeader:LightHeader{Height:7}, TrustedHeight:{1,10}, ZKP:[0xAA,0xBB]}
	//
	// field 1 (signed_header embedded LightHeader{Height:7}):
	//   inner: [0x08,0x07] → 2 bytes
	//   tag=0x0A len=2
	// field 2 (trusted_height embedded Height{1,10}):
	//   inner: [0x08,0x01,0x10,0x0A] → 4 bytes
	//   tag=0x12 len=4
	// field 3 (zero_knowledge_proof): tag=0x1A len=2 [0xAA,0xBB]
	buf := []byte{
		0x0A, 0x02, 0x08, 0x07,             // field 1: signed_header
		0x12, 0x04, 0x08, 0x01, 0x10, 0x0A, // field 2: trusted_height
		0x1A, 0x02, 0xAA, 0xBB,             // field 3: zkp
	}
	got, err := DecodeHeader(buf)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if got.SignedHeader.Height != 7 {
		t.Fatalf("SignedHeader.Height: got %d want 7", got.SignedHeader.Height)
	}
	wantTH := Height{RevisionNumber: 1, RevisionHeight: 10}
	if got.TrustedHeight != wantTH {
		t.Fatalf("TrustedHeight: got %+v want %+v", got.TrustedHeight, wantTH)
	}
	bytesEq(t, "ZeroKnowledgeProof", got.ZeroKnowledgeProof, []byte{0xAA, 0xBB})
}

func TestDecodeMisbehaviour(t *testing.T) {
	// Misbehaviour{HeaderA:Header{SignedHeader:LightHeader{Height:1}},
	//              HeaderB:Header{SignedHeader:LightHeader{Height:2}}}
	//
	// HeaderA inner bytes: LightHeader{1}=[0x08,0x01] → Header field1 → [0x0A,0x02,0x08,0x01] (4 bytes)
	// field 1 (header_a): tag=0x0A len=4 + inner
	// HeaderB inner bytes: LightHeader{2}=[0x08,0x02] → [0x0A,0x02,0x08,0x02] (4 bytes)
	// field 2 (header_b): tag=0x12 len=4 + inner
	buf := []byte{
		0x0A, 0x04, 0x0A, 0x02, 0x08, 0x01, // field 1: header_a
		0x12, 0x04, 0x0A, 0x02, 0x08, 0x02, // field 2: header_b
	}
	got, err := DecodeMisbehaviour(buf)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if got.HeaderA.SignedHeader.Height != 1 {
		t.Fatalf("HeaderA.Height: got %d want 1", got.HeaderA.SignedHeader.Height)
	}
	if got.HeaderB.SignedHeader.Height != 2 {
		t.Fatalf("HeaderB.Height: got %d want 2", got.HeaderB.SignedHeader.Height)
	}
}

func TestDecodeErrors(t *testing.T) {
	t.Run("truncated_varint", func(t *testing.T) {
		// A tag byte with continuation set but no following byte
		buf := []byte{0x80}
		_, err := DecodeHeight(buf)
		if err == nil {
			t.Fatal("expected error for truncated varint")
		}
	})

	t.Run("truncated_bytes_field", func(t *testing.T) {
		// tag=0x0A (field1, wire2), claims len=5 but only 2 bytes follow
		buf := []byte{0x0A, 0x05, 0xAB, 0xCD}
		_, err := DecodeMerkleRoot(buf)
		if err == nil {
			t.Fatal("expected error for truncated bytes field")
		}
	})
}

// --- Union proto_iso 픽스처: unionlabs/union lib/cometbls-light-client-types ---

// TestDecodeClientStateFixture decodes Union's proto_iso ClientState fixture.
//
// Expected fields:
//
//	chain_id        = "oogabooga"
//	trusting_period = 12345
//	max_clock_drift = 67890
//	frozen_height   = {0, 0}   (encoded as empty embedded message)
//	latest_height   = {0, 1337}
func TestDecodeClientStateFixture(t *testing.T) {
	buf := mustHex("0a096f6f6761626f6f676110b96020b292042a00320310b90a")

	got, err := DecodeClientState(buf)
	if err != nil {
		t.Fatalf("DecodeClientState: %v", err)
	}
	if got.ChainID != "oogabooga" {
		t.Fatalf("ChainID: got %q want %q", got.ChainID, "oogabooga")
	}
	if got.TrustingPeriod != 12345 {
		t.Fatalf("TrustingPeriod: got %d want 12345", got.TrustingPeriod)
	}
	if got.MaxClockDrift != 67890 {
		t.Fatalf("MaxClockDrift: got %d want 67890", got.MaxClockDrift)
	}
	if got.IsFrozen() {
		t.Fatalf("FrozenHeight should be zero, got %+v", got.FrozenHeight)
	}
	wantLatest := Height{RevisionNumber: 0, RevisionHeight: 1337}
	if got.LatestHeight != wantLatest {
		t.Fatalf("LatestHeight: got %+v want %+v", got.LatestHeight, wantLatest)
	}
}

// TestDecodeConsensusStateFixture decodes Union's proto_iso ConsensusState fixture.
//
// Expected fields:
//
//	timestamp            = 123456789
//	root.hash            = [0xAA; 32]
//	next_validators_hash = [0xAA; 32]
func TestDecodeConsensusStateFixture(t *testing.T) {
	buf := mustHex(
		"08959aef3a" +
			"12220a20" + "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" +
			"1a20" + "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
	)

	got, err := DecodeConsensusState(buf)
	if err != nil {
		t.Fatalf("DecodeConsensusState: %v", err)
	}
	if got.Timestamp != 123456789 {
		t.Fatalf("Timestamp: got %d want 123456789", got.Timestamp)
	}
	if !bytes.Equal(got.Root.Hash, aaHash) {
		t.Fatalf("Root.Hash: got %x want %x", got.Root.Hash, aaHash)
	}
	if !bytes.Equal(got.NextValidatorsHash, aaHash) {
		t.Fatalf("NextValidatorsHash: got %x want %x", got.NextValidatorsHash, aaHash)
	}
}

// TestDecodeLightHeaderFixture decodes the LightHeader embedded inside
// Union's proto_iso Header fixture.
//
// Expected fields:
//
//	height              = 0xDEADC0DE (3735929054)
//	time_seconds        = 1, time_nanos = 1
//	validators_hash     = [0xAA; 32]
//	next_validators_hash= [0xAA; 32]
//	app_hash            = [0xAA; 32]
func TestDecodeLightHeaderFixture(t *testing.T) {
	buf := mustHex(
		"08de81b7f50d" +
			"1204080110011a20" + "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" +
			"2220" + "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" +
			"2a20" + "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
	)

	got, err := DecodeLightHeader(buf)
	if err != nil {
		t.Fatalf("DecodeLightHeader: %v", err)
	}
	if got.Height != 0xDEADC0DE {
		t.Fatalf("Height: got %d want %d", got.Height, int64(0xDEADC0DE))
	}
	if got.TimeSeconds != 1 {
		t.Fatalf("TimeSeconds: got %d want 1", got.TimeSeconds)
	}
	if got.TimeNanos != 1 {
		t.Fatalf("TimeNanos: got %d want 1", got.TimeNanos)
	}
	if !bytes.Equal(got.ValidatorsHash, aaHash) {
		t.Fatalf("ValidatorsHash: got %x want %x", got.ValidatorsHash, aaHash)
	}
	if !bytes.Equal(got.NextValidatorsHash, aaHash) {
		t.Fatalf("NextValidatorsHash mismatch")
	}
	if !bytes.Equal(got.AppHash, aaHash) {
		t.Fatalf("AppHash mismatch")
	}
}

// TestDecodeHeaderFixture decodes Union's proto_iso Header fixture.
//
// Expected fields:
//
//	signed_header         = LightHeader{height=0xDEADC0DE, time={1,1}, all hashes [0xAA;32]}
//	trusted_height        = {revision_number=0, revision_height=100}
//	zero_knowledge_proof  = "zkp"
func TestDecodeHeaderFixture(t *testing.T) {
	buf := mustHex(
		"0a72" +
			"08de81b7f50d" +
			"1204080110011a20" + "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" +
			"2220" + "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" +
			"2a20" + "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" +
			"120210641a037a6b70",
	)

	got, err := DecodeHeader(buf)
	if err != nil {
		t.Fatalf("DecodeHeader: %v", err)
	}
	if got.SignedHeader.Height != 0xDEADC0DE {
		t.Fatalf("SignedHeader.Height: got %d want %d", got.SignedHeader.Height, int64(0xDEADC0DE))
	}
	if got.SignedHeader.TimeSeconds != 1 || got.SignedHeader.TimeNanos != 1 {
		t.Fatalf("SignedHeader.Time: got {%d,%d} want {1,1}", got.SignedHeader.TimeSeconds, got.SignedHeader.TimeNanos)
	}
	if !bytes.Equal(got.SignedHeader.AppHash, aaHash) {
		t.Fatalf("SignedHeader.AppHash mismatch")
	}
	wantTH := Height{RevisionNumber: 0, RevisionHeight: 100}
	if got.TrustedHeight != wantTH {
		t.Fatalf("TrustedHeight: got %+v want %+v", got.TrustedHeight, wantTH)
	}
	if !bytes.Equal(got.ZeroKnowledgeProof, []byte("zkp")) {
		t.Fatalf("ZKP: got %x want %x", got.ZeroKnowledgeProof, []byte("zkp"))
	}
}

// TestDecodeMisbehaviourFixture decodes Union's proto_iso Misbehaviour fixture.
//
// Two identical Header messages (both from the Header fixture above).
func TestDecodeMisbehaviourFixture(t *testing.T) {
	hdrHex := "0a72" +
		"08de81b7f50d" +
		"1204080110011a20" + "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" +
		"2220" + "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" +
		"2a20" + "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" +
		"120210641a037a6b70"
	buf := mustHex("0a7d" + hdrHex + "127d" + hdrHex)

	got, err := DecodeMisbehaviour(buf)
	if err != nil {
		t.Fatalf("DecodeMisbehaviour: %v", err)
	}
	if got.HeaderA.SignedHeader.Height != 0xDEADC0DE {
		t.Fatalf("HeaderA.Height: got %d want %d", got.HeaderA.SignedHeader.Height, int64(0xDEADC0DE))
	}
	if got.HeaderB.SignedHeader.Height != 0xDEADC0DE {
		t.Fatalf("HeaderB.Height: got %d want %d", got.HeaderB.SignedHeader.Height, int64(0xDEADC0DE))
	}
	wantTH := Height{RevisionNumber: 0, RevisionHeight: 100}
	if got.HeaderA.TrustedHeight != wantTH || got.HeaderB.TrustedHeight != wantTH {
		t.Fatalf("TrustedHeight mismatch in misbehaviour headers")
	}
}
