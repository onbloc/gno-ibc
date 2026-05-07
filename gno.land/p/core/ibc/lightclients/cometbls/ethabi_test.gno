package cometbls

import (
	"bytes"
	"encoding/hex"
	"testing"
)

const wordSize = 32

func bytesEq(t *testing.T, label string, got, want []byte) {
	t.Helper()
	if !bytes.Equal(got, want) {
		t.Fatalf("%s: got %x want %x", label, got, want)
	}
}

func mustHex(s string) []byte {
	b, err := hex.DecodeString(s)
	if err != nil {
		panic("mustHex: " + err.Error())
	}
	return b
}

func word32(v uint64) string {
	out := make([]byte, 32)
	out[24] = byte(v >> 56)
	out[25] = byte(v >> 48)
	out[26] = byte(v >> 40)
	out[27] = byte(v >> 32)
	out[28] = byte(v >> 24)
	out[29] = byte(v >> 16)
	out[30] = byte(v >> 8)
	out[31] = byte(v)
	return hex.EncodeToString(out)
}

func bytes32hex(b byte) string {
	return hex.EncodeToString(bytes.Repeat([]byte{b}, 32))
}

func chainIDWord32(s string) string {
	out := make([]byte, 32)
	copy(out, []byte(s))
	return hex.EncodeToString(out)
}

// --- EncodeClientState ---

func TestEncodeClientState(t *testing.T) {
	t.Run("basic", func(t *testing.T) {
		cs := ClientState{
			ChainID:        "abc",
			TrustingPeriod: 1000,
			MaxClockDrift:  100,
		}
		want := mustHex(
			chainIDWord32("abc") +
				word32(1000) +
				word32(100) +
				word32(0) +
				word32(0),
		)
		bytesEq(t, "EncodeClientState/basic", EncodeClientState(cs), want)
	})

	t.Run("with_heights", func(t *testing.T) {
		cs := ClientState{
			ChainID:        "chain",
			TrustingPeriod: 100,
			MaxClockDrift:  10,
			FrozenHeight:   1,
			LatestHeight:   999,
		}
		want := mustHex(
			chainIDWord32("chain") +
				word32(100) +
				word32(10) +
				word32(1) +
				word32(999),
		)
		bytesEq(t, "EncodeClientState/with_heights", EncodeClientState(cs), want)
	})

	t.Run("chain_id_32_bytes", func(t *testing.T) {
		id := string(bytes.Repeat([]byte{'x'}, 32))
		cs := ClientState{ChainID: id}
		got := EncodeClientState(cs)
		if len(got) != 5*wordSize {
			t.Fatalf("want %d bytes got %d", 5*wordSize, len(got))
		}
		if string(got[:32]) != id {
			t.Fatalf("chain_id mismatch")
		}
	})
}

// --- EncodeConsensusState ---

func TestEncodeConsensusState(t *testing.T) {
	t.Run("basic", func(t *testing.T) {
		cs := ConsensusState{
			Timestamp:          500,
			Root:               MerkleRoot{Hash: bytes.Repeat([]byte{0xAB}, 32)},
			NextValidatorsHash: bytes.Repeat([]byte{0xCD}, 32),
		}
		want := mustHex(word32(500) + bytes32hex(0xAB) + bytes32hex(0xCD))
		got, err := EncodeConsensusState(cs)
		if err != nil {
			t.Fatalf("unexpected error: %v", err)
		}
		bytesEq(t, "EncodeConsensusState/basic", got, want)
	})

	t.Run("invalid_root_hash", func(t *testing.T) {
		cs := ConsensusState{
			Timestamp:          1,
			Root:               MerkleRoot{Hash: []byte{0x01}},
			NextValidatorsHash: bytes.Repeat([]byte{0xFF}, 32),
		}
		_, err := EncodeConsensusState(cs)
		if err == nil {
			t.Fatal("expected error for non-32-byte root hash")
		}
	})

	t.Run("invalid_nvh", func(t *testing.T) {
		cs := ConsensusState{
			Timestamp:          1,
			Root:               MerkleRoot{Hash: bytes.Repeat([]byte{0xFF}, 32)},
			NextValidatorsHash: []byte{0x01},
		}
		_, err := EncodeConsensusState(cs)
		if err == nil {
			t.Fatal("expected error for non-32-byte next validators hash")
		}
	})
}

// --- EncodeHeader ---

func TestEncodeHeader(t *testing.T) {
	t.Run("basic_zkp_2bytes", func(t *testing.T) {
		h := Header{
			SignedHeader: LightHeader{
				Height:             42,
				TimeSeconds:        1000,
				TimeNanos:          500,
				ValidatorsHash:     bytes.Repeat([]byte{0x01}, 32),
				NextValidatorsHash: bytes.Repeat([]byte{0x02}, 32),
				AppHash:            bytes.Repeat([]byte{0x03}, 32),
			},
			TrustedHeight:      10,
			ZeroKnowledgeProof: []byte{0xAA, 0xBB},
		}
		zkpPadded := make([]byte, 32)
		copy(zkpPadded, []byte{0xAA, 0xBB})
		want := mustHex(
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
		got, err := EncodeHeader(h)
		if err != nil {
			t.Fatalf("unexpected error: %v", err)
		}
		bytesEq(t, "EncodeHeader/basic", got, want)
	})

	t.Run("zero_time_nanos", func(t *testing.T) {
		h := Header{
			SignedHeader: LightHeader{
				Height:             1,
				TimeSeconds:        100,
				ValidatorsHash:     bytes.Repeat([]byte{0xAA}, 32),
				NextValidatorsHash: bytes.Repeat([]byte{0xBB}, 32),
				AppHash:            bytes.Repeat([]byte{0xCC}, 32),
			},
			TrustedHeight:      0,
			ZeroKnowledgeProof: bytes.Repeat([]byte{0xFF}, 32),
		}
		got, err := EncodeHeader(h)
		if err != nil {
			t.Fatalf("unexpected error: %v", err)
		}
		if len(got) != 10*wordSize {
			t.Fatalf("want %d bytes got %d", 10*wordSize, len(got))
		}
	})
}

// --- EncodeMisbehaviour ---

func TestEncodeMisbehaviour(t *testing.T) {
	m := Misbehaviour{
		HeaderA: Header{SignedHeader: LightHeader{Height: 1}},
		HeaderB: Header{SignedHeader: LightHeader{Height: 2}},
	}
	want := []byte{
		0x0A, 0x04, 0x0A, 0x02, 0x08, 0x01,
		0x12, 0x04, 0x0A, 0x02, 0x08, 0x02,
	}
	bytesEq(t, "EncodeMisbehaviour", EncodeMisbehaviour(m), want)
}

// --- DecodeClientState ---

func TestDecodeClientState(t *testing.T) {
	t.Run("basic", func(t *testing.T) {
		buf := mustHex(
			chainIDWord32("abc") +
				word32(1000) +
				word32(100) +
				word32(0) +
				word32(50),
		)
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
		if got.LatestHeight != 50 {
			t.Fatalf("LatestHeight: got %d want 50", got.LatestHeight)
		}
	})

	t.Run("frozen", func(t *testing.T) {
		buf := mustHex(
			chainIDWord32("x") +
				word32(100) +
				word32(10) +
				word32(1) +
				word32(99),
		)
		got, err := DecodeClientState(buf)
		if err != nil {
			t.Fatalf("unexpected error: %v", err)
		}
		if !got.IsFrozen() {
			t.Fatal("expected FrozenHeight to be set")
		}
	})

	t.Run("too_short", func(t *testing.T) {
		_, err := DecodeClientState([]byte{0x01})
		if err == nil {
			t.Fatal("expected error for short buffer")
		}
	})
}

// --- DecodeConsensusState ---

func TestDecodeConsensusState(t *testing.T) {
	t.Run("basic", func(t *testing.T) {
		buf := mustHex(word32(500) + bytes32hex(0xAB) + bytes32hex(0xCD))
		got, err := DecodeConsensusState(buf)
		if err != nil {
			t.Fatalf("unexpected error: %v", err)
		}
		if got.Timestamp != 500 {
			t.Fatalf("Timestamp: got %d want 500", got.Timestamp)
		}
		bytesEq(t, "Root.Hash", got.Root.Hash, bytes.Repeat([]byte{0xAB}, 32))
		bytesEq(t, "NextValidatorsHash", got.NextValidatorsHash, bytes.Repeat([]byte{0xCD}, 32))
	})

	t.Run("too_short", func(t *testing.T) {
		_, err := DecodeConsensusState(make([]byte, 63))
		if err == nil {
			t.Fatal("expected error for short buffer")
		}
	})
}

// --- DecodeHeader ---

func TestDecodeHeader(t *testing.T) {
	t.Run("basic", func(t *testing.T) {
		zkp := []byte{0xAA, 0xBB}
		zkpPadded := make([]byte, 32)
		copy(zkpPadded, zkp)
		buf := mustHex(
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
		got, err := DecodeHeader(buf)
		if err != nil {
			t.Fatalf("unexpected error: %v", err)
		}
		if got.SignedHeader.Height != 42 {
			t.Fatalf("Height: got %d want 42", got.SignedHeader.Height)
		}
		if got.SignedHeader.TimeSeconds != 1000 {
			t.Fatalf("TimeSeconds: got %d want 1000", got.SignedHeader.TimeSeconds)
		}
		if got.SignedHeader.TimeNanos != 500 {
			t.Fatalf("TimeNanos: got %d want 500", got.SignedHeader.TimeNanos)
		}
		bytesEq(t, "ValidatorsHash", got.SignedHeader.ValidatorsHash, bytes.Repeat([]byte{0x01}, 32))
		bytesEq(t, "NextValidatorsHash", got.SignedHeader.NextValidatorsHash, bytes.Repeat([]byte{0x02}, 32))
		bytesEq(t, "AppHash", got.SignedHeader.AppHash, bytes.Repeat([]byte{0x03}, 32))
		if got.TrustedHeight != 10 {
			t.Fatalf("TrustedHeight: got %d want 10", got.TrustedHeight)
		}
		bytesEq(t, "ZKP", got.ZeroKnowledgeProof, zkp)
	})

	t.Run("too_short", func(t *testing.T) {
		_, err := DecodeHeader(make([]byte, 255))
		if err == nil {
			t.Fatal("expected error for short buffer")
		}
	})
}

// --- DecodeMisbehaviour ---

func TestDecodeMisbehaviour(t *testing.T) {
	buf := []byte{
		0x0A, 0x04, 0x0A, 0x02, 0x08, 0x01,
		0x12, 0x04, 0x0A, 0x02, 0x08, 0x02,
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

// --- Union devnet fixture ---

// TestDecodeHeaderUnionFixture decodes a real ABI-encoded Header produced by
// Union and verifies every field against the known JSON output.
//
// Source: union-devnet chain, block 6433728 (2026-05-06T15:14:03.986205568Z)
func TestDecodeHeaderUnionFixture(t *testing.T) {
	const fixtureHex = "0000000000000000000000000000000000000000000000000000000000622bc0" +
		"0000000000000000000000000000000000000000000000000000000069fb5abb" +
		"000000000000000000000000000000000000000000000000000000003ac84d80" +
		"140379043aff431abf326b351ad625c9d817e3f589606b260867f56a9dd52cbc" +
		"140379043aff431abf326b351ad625c9d817e3f589606b260867f56a9dd52cbc" +
		"c75dfe45e0e98d0451c816ced153935ee304b4172272f91222f31fd937f56483" +
		"00000000000000000000000000000000000000000000000000000000006200d6" +
		"0000000000000000000000000000000000000000000000000000000000000100" +
		"0000000000000000000000000000000000000000000000000000000000000180" +
		"2601de608d0eda2df23aa38cc62ca4493fb27239239556f1c620e2546e4c3952" +
		"0acb72499ac759d62de65f7ad5f569170e90c174cd72d278f2179c8128608165" +
		"247a570ae502781ae9b0949ce35935a110c2ac56b95a867387ee5b15776f3f8c" +
		"1fd17830c99a8a9b30405e177dbf959eb9d6908036139729424985d402321fbe" +
		"1d195096e4e2431550d183de6e2366a52116cd56d7327f7af1a7794627e0ea85" +
		"22aaceed54aca8ae9fc823febb9144832d402e733606b6db7b2816abfb31d4c0" +
		"140e16838f1cd00e9ef9777a55db3332cff0e0c43a4118229df65f3c2de114f8" +
		"25eb1a5f40a8c758d6ebc2f6aaf88b6a5f28a1b01524f282793be91aeb8d21fa" +
		"22031e667c3efa1c1f961d364a4c066eb0613ccbb3930b129c9084afea333131" +
		"06bf693e0172a02653593ac3fd7c711e800d2c0566235856d4abeaf765e3b96f" +
		"0a7e3a64fbb778fbb27dbba85a4821a6af61f5815d8e84848b15003a4b3878e0" +
		"229506a72f4a739b23b0ce49fe6d26604807b99aa8d1a13375c0795920b13108"

	h, err := DecodeHeader(mustHex(fixtureHex))
	if err != nil {
		t.Fatalf("DecodeHeader: %v", err)
	}
	if h.SignedHeader.Height != 6433728 {
		t.Errorf("Height: got %d want 6433728", h.SignedHeader.Height)
	}
	if h.SignedHeader.TimeSeconds != 1778080443 {
		t.Errorf("TimeSeconds: got %d want 1778080443", h.SignedHeader.TimeSeconds)
	}
	if h.SignedHeader.TimeNanos != 986205568 {
		t.Errorf("TimeNanos: got %d want 986205568", h.SignedHeader.TimeNanos)
	}
	wantVH := mustHex("140379043aff431abf326b351ad625c9d817e3f589606b260867f56a9dd52cbc")
	bytesEq(t, "ValidatorsHash", h.SignedHeader.ValidatorsHash, wantVH)
	bytesEq(t, "NextValidatorsHash", h.SignedHeader.NextValidatorsHash, wantVH)
	wantAH := mustHex("c75dfe45e0e98d0451c816ced153935ee304b4172272f91222f31fd937f56483")
	bytesEq(t, "AppHash", h.SignedHeader.AppHash, wantAH)
	if h.TrustedHeight != 6422742 {
		t.Errorf("TrustedHeight: got %d want 6422742", h.TrustedHeight)
	}
	if len(h.ZeroKnowledgeProof) != 384 {
		t.Fatalf("ZKP length: got %d want 384", len(h.ZeroKnowledgeProof))
	}
	wantZKP := mustHex(
		"2601de608d0eda2df23aa38cc62ca4493fb27239239556f1c620e2546e4c3952" +
			"0acb72499ac759d62de65f7ad5f569170e90c174cd72d278f2179c8128608165" +
			"247a570ae502781ae9b0949ce35935a110c2ac56b95a867387ee5b15776f3f8c" +
			"1fd17830c99a8a9b30405e177dbf959eb9d6908036139729424985d402321fbe" +
			"1d195096e4e2431550d183de6e2366a52116cd56d7327f7af1a7794627e0ea85" +
			"22aaceed54aca8ae9fc823febb9144832d402e733606b6db7b2816abfb31d4c0" +
			"140e16838f1cd00e9ef9777a55db3332cff0e0c43a4118229df65f3c2de114f8" +
			"25eb1a5f40a8c758d6ebc2f6aaf88b6a5f28a1b01524f282793be91aeb8d21fa" +
			"22031e667c3efa1c1f961d364a4c066eb0613ccbb3930b129c9084afea333131" +
			"06bf693e0172a02653593ac3fd7c711e800d2c0566235856d4abeaf765e3b96f" +
			"0a7e3a64fbb778fbb27dbba85a4821a6af61f5815d8e84848b15003a4b3878e0" +
			"229506a72f4a739b23b0ce49fe6d26604807b99aa8d1a13375c0795920b13108",
	)
	bytesEq(t, "ZKP", h.ZeroKnowledgeProof, wantZKP)
	wantNanos := uint64(1778080443)*1_000_000_000 + uint64(986205568)
	if h.SignedHeader.Nanos() != wantNanos {
		t.Errorf("Nanos: got %d want %d", h.SignedHeader.Nanos(), wantNanos)
	}
}

// --- Round-trip tests ---

func TestEncodeDecodeClientStateRoundTrip(t *testing.T) {
	original := ClientState{
		ChainID:        "union-devnet-1337",
		TrustingPeriod: 14 * 24 * 3600 * 1_000_000_000,
		MaxClockDrift:  10 * 1_000_000_000,
		LatestHeight:   1337,
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
	if got.LatestHeight != original.LatestHeight {
		t.Fatalf("LatestHeight: got %d want %d", got.LatestHeight, original.LatestHeight)
	}
}

func TestEncodeDecodeConsensusStateRoundTrip(t *testing.T) {
	original := ConsensusState{
		Timestamp:          123456789,
		Root:               MerkleRoot{Hash: bytes.Repeat([]byte{0xAA}, 32)},
		NextValidatorsHash: bytes.Repeat([]byte{0xBB}, 32),
	}
	enc, err := EncodeConsensusState(original)
	if err != nil {
		t.Fatalf("EncodeConsensusState: %v", err)
	}
	got, err := DecodeConsensusState(enc)
	if err != nil {
		t.Fatalf("DecodeConsensusState: %v", err)
	}
	if got.Timestamp != original.Timestamp {
		t.Fatalf("Timestamp: got %d want %d", got.Timestamp, original.Timestamp)
	}
	bytesEq(t, "Root.Hash", got.Root.Hash, original.Root.Hash)
	bytesEq(t, "NextValidatorsHash", got.NextValidatorsHash, original.NextValidatorsHash)
}

func TestEncodeDecodeHeaderRoundTrip(t *testing.T) {
	original := Header{
		SignedHeader: LightHeader{
			Height:             3405691582,
			TimeSeconds:        1732205251,
			TimeNanos:          998131342,
			ValidatorsHash:     bytes.Repeat([]byte{0xDE}, 32),
			NextValidatorsHash: bytes.Repeat([]byte{0xAD}, 32),
			AppHash:            bytes.Repeat([]byte{0xBE}, 32),
		},
		TrustedHeight:      3405691581,
		ZeroKnowledgeProof: bytes.Repeat([]byte{0xEF}, 384),
	}
	enc, err := EncodeHeader(original)
	if err != nil {
		t.Fatalf("EncodeHeader: %v", err)
	}
	got, err := DecodeHeader(enc)
	if err != nil {
		t.Fatalf("DecodeHeader: %v", err)
	}
	if got.SignedHeader.Height != original.SignedHeader.Height {
		t.Fatalf("Height: got %d want %d", got.SignedHeader.Height, original.SignedHeader.Height)
	}
	if got.SignedHeader.TimeSeconds != original.SignedHeader.TimeSeconds {
		t.Fatalf("TimeSeconds: got %d want %d", got.SignedHeader.TimeSeconds, original.SignedHeader.TimeSeconds)
	}
	if got.SignedHeader.TimeNanos != original.SignedHeader.TimeNanos {
		t.Fatalf("TimeNanos: got %d want %d", got.SignedHeader.TimeNanos, original.SignedHeader.TimeNanos)
	}
	bytesEq(t, "ValidatorsHash", got.SignedHeader.ValidatorsHash, original.SignedHeader.ValidatorsHash)
	bytesEq(t, "NextValidatorsHash", got.SignedHeader.NextValidatorsHash, original.SignedHeader.NextValidatorsHash)
	bytesEq(t, "AppHash", got.SignedHeader.AppHash, original.SignedHeader.AppHash)
	if got.TrustedHeight != original.TrustedHeight {
		t.Fatalf("TrustedHeight: got %d want %d", got.TrustedHeight, original.TrustedHeight)
	}
	bytesEq(t, "ZKP", got.ZeroKnowledgeProof, original.ZeroKnowledgeProof)
}

func TestEncodeDecodeMisbehaviourRoundTrip(t *testing.T) {
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
	reenc := EncodeMisbehaviour(got)
	bytesEq(t, "Misbehaviour round-trip", reenc, buf)
}
