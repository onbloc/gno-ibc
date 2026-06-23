package cometbls

import (
	"encoding/hex"
	"testing"
	"time"

	"gno.land/p/onbloc/ibc/union/types"
)

// newTestHeader builds a *Header against the current model (pointer
// SignedHeader = *cometblszk.LightHeader with TimeSeconds/TimeNanos,
// *types.Height, []byte hashes).
func newTestHeader(height, sec int64, nanos int32, trusted uint64, zkp []byte) *Header {
	th := types.NewHeight(trusted)
	return &Header{
		SignedHeader: &LightHeader{
			Height:             height,
			TimeSeconds:        sec,
			TimeNanos:          nanos,
			ValidatorsHash:     repeat32(0x01),
			NextValidatorsHash: repeat32(0x02),
			AppHash:            repeat32(0x03),
		},
		TrustedHeight:      &th,
		ZeroKnowledgeProof: zkp,
	}
}

func TestEncodeHeader(t *testing.T) {
	zkpPadded := make([]byte, 32)
	copy(zkpPadded, []byte{0xAA, 0xBB})

	cases := []struct {
		name    string
		header  *Header
		want    []byte
		wantErr string
	}{
		{
			name:   "basic zkp 2 bytes",
			header: newTestHeader(42, 1000, 500, 10, []byte{0xAA, 0xBB}),
			want: mustHex(
				word32(42) +
					word32(1000) +
					word32(500) +
					bytes32hex(0x01) +
					bytes32hex(0x02) +
					bytes32hex(0x03) +
					word32(10) +
					word32(256) + // offset to the dynamic bytes field
					word32(2) + // ZKP length
					hex.EncodeToString(zkpPadded),
			),
		},
		{name: "nil header", header: nil, wantErr: "nil header"},
		{
			name: "nil signed header",
			header: &Header{
				SignedHeader:       nil,
				TrustedHeight:      heightPtr(types.NewHeight(1)),
				ZeroKnowledgeProof: []byte{0x01},
			},
			wantErr: "nil header",
		},
		{
			name: "short validators hash",
			header: cloneTestHeaderWith(func(h *Header) {
				h.SignedHeader.ValidatorsHash = []byte{0x01}
			}),
			wantErr: "validators hash must be 32 bytes",
		},
		{
			name: "short next validators hash",
			header: cloneTestHeaderWith(func(h *Header) {
				h.SignedHeader.NextValidatorsHash = []byte{0x01}
			}),
			wantErr: "next validators hash must be 32 bytes",
		},
		{
			name: "short app hash",
			header: cloneTestHeaderWith(func(h *Header) {
				h.SignedHeader.AppHash = []byte{0x01}
			}),
			wantErr: "app hash must be 32 bytes",
		},
		{
			name: "long validators hash",
			header: cloneTestHeaderWith(func(h *Header) {
				h.SignedHeader.ValidatorsHash = repeatBytes(0x01, 33)
			}),
			wantErr: "validators hash must be 32 bytes",
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
			bytesEq(t, "EncodeHeader", got, tc.want)
		})
	}
}

func TestDecodeHeader(t *testing.T) {
	zkp := []byte{0xAA, 0xBB}
	zkpPadded := make([]byte, 32)
	copy(zkpPadded, zkp)
	cases := []struct {
		name    string
		data    []byte
		check   func(*testing.T, *Header)
		wantErr string
	}{
		{
			name: "basic",
			data: mustHex(
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
			),
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
		{name: "too short", data: make([]byte, 255), wantErr: "abi: invalid data"},
		{
			name: "timenanos out of range",
			data: mustHex(
				word32(1) +
					word32(1000) +
					word32(1_000_000_000) +
					bytes32hex(0x01) +
					bytes32hex(0x02) +
					bytes32hex(0x03) +
					word32(0) +
					word32(256) +
					word32(uint64(len(zkpPadded))) +
					hex.EncodeToString(zkpPadded),
			),
			wantErr: "TimeNanos out of range",
		},
		{
			name: "zkp offset unaligned",
			data: mustHex(
				word32(1) +
					word32(1000) +
					word32(0) +
					bytes32hex(0x01) +
					bytes32hex(0x02) +
					bytes32hex(0x03) +
					word32(0) +
					word32(257) +
					word32(0),
			),
			wantErr: "abi: invalid data",
		},
		{
			name: "zkp offset out of range",
			data: mustHex(
				word32(1) +
					word32(1000) +
					word32(0) +
					bytes32hex(0x01) +
					bytes32hex(0x02) +
					bytes32hex(0x03) +
					word32(0) +
					word32(512) +
					word32(0),
			),
			wantErr: "abi: invalid data",
		},
		{
			name: "zkp length exceeds tail",
			data: mustHex(
				word32(1) +
					word32(1000) +
					word32(0) +
					bytes32hex(0x01) +
					bytes32hex(0x02) +
					bytes32hex(0x03) +
					word32(0) +
					word32(256) +
					word32(64) +
					hex.EncodeToString(zkpPadded),
			),
			wantErr: "abi: invalid data",
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
			tc.check(t, got)
		})
	}
}

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
	if h.TrustedHeight.RevisionHeight != 6422742 {
		t.Errorf("TrustedHeight: got %d want 6422742", h.TrustedHeight.RevisionHeight)
	}
	if len(h.ZeroKnowledgeProof) != 384 {
		t.Fatalf("ZKP length: got %d want 384", len(h.ZeroKnowledgeProof))
	}
}

func TestEncodeDecodeHeaderRoundTrip(t *testing.T) {
	t.Run("successful roundtrip", func(t *testing.T) {
		th := types.NewHeight(3405691581)
		original := &Header{
			SignedHeader: &LightHeader{
				Height:             3405691582,
				TimeSeconds:        1732205251,
				TimeNanos:          998131342,
				ValidatorsHash:     repeat32(0xDE),
				NextValidatorsHash: repeat32(0xAD),
				AppHash:            repeat32(0xBE),
			},
			TrustedHeight:      &th,
			ZeroKnowledgeProof: repeatBytes(0xEF, 384),
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
		if got.TrustedHeight.RevisionHeight != original.TrustedHeight.RevisionHeight {
			t.Fatalf("TrustedHeight: got %d want %d", got.TrustedHeight.RevisionHeight, original.TrustedHeight.RevisionHeight)
		}
		bytesEq(t, "ZKP", got.ZeroKnowledgeProof, original.ZeroKnowledgeProof)
	})
}

func TestHeaderValidateBasic(t *testing.T) {
	// Union reference: verify_header rejects stale heights and invalid header
	// timing before proof verification.
	testCases := []struct {
		name    string
		setup   func(*Header)
		wantErr string
	}{
		{
			name:  "valid",
			setup: func(*Header) {},
		},
		{
			name: "nil signed header",
			setup: func(h *Header) {
				h.SignedHeader = nil
			},
			wantErr: "signed header cannot be nil",
		},
		{
			name: "empty zkp",
			setup: func(h *Header) {
				h.ZeroKnowledgeProof = nil
			},
			wantErr: "zero-knowledge proof cannot be empty",
		},
		{
			name: "trusted height equals header height",
			setup: func(h *Header) {
				h.TrustedHeight = heightPtr(types.NewHeight(uint64(h.SignedHeader.Height)))
			},
			wantErr: "must be less than header height",
		},
		{
			name: "trusted height greater than header height",
			setup: func(h *Header) {
				h.TrustedHeight = heightPtr(types.NewHeight(uint64(h.SignedHeader.Height + 1)))
			},
			wantErr: "must be less than header height",
		},
	}

	for _, tc := range testCases {
		t.Run(tc.name, func(t *testing.T) {
			h := newTestHeader(42, 1000, 500, 10, []byte{0xAA})
			tc.setup(h)

			err := h.ValidateBasic()
			if tc.wantErr == "" {
				if err != nil {
					t.Fatalf("ValidateBasic: %v", err)
				}
				return
			}
			requireErrorContains(t, err, tc.wantErr)
		})
	}
}

func TestHeaderGetHeightPreservesTrustedRevision(t *testing.T) {
	// Union reference: update_state rebuilds the untrusted height with the
	// trusted height revision.
	h := newTestHeader(42, 1000, 500, 10, []byte{0xAA})
	h.TrustedHeight = heightPtr(types.NewHeightWithRevision(7, 10))

	got := h.GetHeight()
	if got.RevisionNumber != 7 {
		t.Fatalf("revision number: got %d want 7", got.RevisionNumber)
	}
	if got.RevisionHeight != 42 {
		t.Fatalf("revision height: got %d want 42", got.RevisionHeight)
	}
}

func TestHeaderConsensusState(t *testing.T) {
	h := newTestHeader(42, 1000, 500, 10, []byte{0xAA})
	h.SignedHeader.AppHash = repeat32(0x44)
	h.SignedHeader.NextValidatorsHash = repeat32(0x45)

	got := h.ConsensusState()

	if got.Timestamp != uint64(h.GetTime().UnixNano()) {
		t.Fatalf("timestamp: got %d want %d", got.Timestamp, h.GetTime().UnixNano())
	}
	bytesEq(t, "root hash", got.Root.Hash, h.SignedHeader.AppHash)
	bytesEq(t, "next validators hash", got.NextValidatorsHash, h.SignedHeader.NextValidatorsHash)
}

func TestHeaderGetTimeUsesSecondsAndNanosUTC(t *testing.T) {
	cases := []struct {
		name      string
		seconds   int64
		nanos     int32
		wantUnix  int64
		wantNanos int
	}{
		{"valid timestamp", 1704067200, 123456789, 1704067200, 123456789},
		{"nanos at boundary", 1704067200, 999999999, 1704067200, 999999999},
		{"zero timestamp", 0, 0, 0, 0},
		{"negative seconds", -86400, 0, -86400, 0},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			h := newTestHeader(42, tc.seconds, tc.nanos, 10, []byte{0xAA})

			got := h.GetTime()

			if got.Unix() != tc.wantUnix {
				t.Fatalf("Unix seconds: got %d want %d", got.Unix(), tc.wantUnix)
			}
			if got.Nanosecond() != tc.wantNanos {
				t.Fatalf("nanoseconds: got %d want %d", got.Nanosecond(), tc.wantNanos)
			}
			if got.Location() != time.UTC {
				t.Fatalf("location: got %s want UTC", got.Location())
			}
		})
	}
}

func TestVerifyHeaderWrapperRejectsMalformedHeader(t *testing.T) {
	// Union reference: VerifyHeader decodes the client message before entering
	// the typed verify_header implementation.
	c := newTestClient(t)
	var caller, relayer address

	_, err := c.VerifyHeader(caller, []byte{0x00}, relayer)

	requireErrorContains(t, err, "failed to decode header")
}

func TestVerifyHeaderDuplicateHeightShortCircuitsBeforeZKP(t *testing.T) {
	c := newTestClient(t)
	h := updateStateTestHeader(100, 100, testNow)
	h.ZeroKnowledgeProof = nil

	headerBytes, err := EncodeHeader(h)
	if err != nil {
		t.Fatalf("EncodeHeader: %v", err)
	}
	update, err := c.VerifyHeader("", headerBytes, "")
	if err != nil {
		t.Fatalf("VerifyHeader duplicate: %v", err)
	}

	if update.Height != 100 {
		t.Fatalf("update height: got %d want 100", update.Height)
	}
	if len(update.ClientStateBytes) != 0 {
		t.Fatal("duplicate VerifyHeader must not include client state bytes")
	}
	if len(update.ConsensusStateBytes) == 0 {
		t.Fatal("duplicate VerifyHeader must include existing consensus state bytes")
	}
}

func TestNewHeader(t *testing.T) {
	cases := []struct {
		name               string
		signedHeader       *LightHeader
		trustedHeight      *types.Height
		zeroKnowledgeProof []byte
		wantHeight         int64
		wantTimeSeconds    int64
		wantTrustedHeight  uint64
		wantZKPLen         int
	}{
		{
			name:               "valid header with all fields",
			signedHeader:       &LightHeader{Height: 42, TimeSeconds: 1000, TimeNanos: 500},
			trustedHeight:      heightPtr(types.NewHeight(10)),
			zeroKnowledgeProof: []byte{0xAA, 0xBB},
			wantHeight:         42,
			wantTimeSeconds:    1000,
			wantTrustedHeight:  10,
			wantZKPLen:         2,
		},
		{
			name:               "valid header with nil trusted height",
			signedHeader:       &LightHeader{Height: 100, TimeSeconds: 2000, TimeNanos: 0},
			trustedHeight:      nil,
			zeroKnowledgeProof: []byte{0x01},
			wantHeight:         100,
			wantTimeSeconds:    2000,
			wantTrustedHeight:  0,
			wantZKPLen:         1,
		},
		{
			name:               "valid header with empty zkp",
			signedHeader:       &LightHeader{Height: 1, TimeSeconds: 0, TimeNanos: 0},
			trustedHeight:      heightPtr(types.NewHeight(0)),
			zeroKnowledgeProof: []byte{},
			wantHeight:         1,
			wantTimeSeconds:    0,
			wantTrustedHeight:  0,
			wantZKPLen:         0,
		},
		{
			name:               "valid header with nil signed header",
			signedHeader:       nil,
			trustedHeight:      heightPtr(types.NewHeight(5)),
			zeroKnowledgeProof: []byte{0xCC},
			wantHeight:         0,
			wantTimeSeconds:    0,
			wantTrustedHeight:  5,
			wantZKPLen:         1,
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got := NewHeader(tc.signedHeader, tc.trustedHeight, tc.zeroKnowledgeProof)

			if got == nil {
				t.Fatal("NewHeader returned nil")
			}
			if got.SignedHeader != tc.signedHeader {
				if got.SignedHeader == nil && tc.signedHeader == nil {
					// Both nil is OK
				} else if got.SignedHeader == nil || tc.signedHeader == nil {
					t.Fatalf("SignedHeader: got %v want %v", got.SignedHeader, tc.signedHeader)
				} else if got.SignedHeader.Height != tc.wantHeight {
					t.Fatalf("SignedHeader.Height: got %d want %d", got.SignedHeader.Height, tc.wantHeight)
				}
			}
			if tc.signedHeader != nil && got.SignedHeader.Height != tc.wantHeight {
				t.Fatalf("SignedHeader.Height: got %d want %d", got.SignedHeader.Height, tc.wantHeight)
			}
			if tc.signedHeader != nil && got.SignedHeader.TimeSeconds != tc.wantTimeSeconds {
				t.Fatalf("SignedHeader.TimeSeconds: got %d want %d", got.SignedHeader.TimeSeconds, tc.wantTimeSeconds)
			}
			if tc.trustedHeight != nil && got.TrustedHeight != nil {
				if got.TrustedHeight.RevisionHeight != tc.wantTrustedHeight {
					t.Fatalf("TrustedHeight.RevisionHeight: got %d want %d", got.TrustedHeight.RevisionHeight, tc.wantTrustedHeight)
				}
			}
			if tc.trustedHeight == nil && got.TrustedHeight != nil {
				t.Fatalf("TrustedHeight: got %v want nil", got.TrustedHeight)
			}
			if len(got.ZeroKnowledgeProof) != tc.wantZKPLen {
				t.Fatalf("ZeroKnowledgeProof length: got %d want %d", len(got.ZeroKnowledgeProof), tc.wantZKPLen)
			}
		})
	}
}

func TestHeaderClientType(t *testing.T) {
	cases := []struct {
		name   string
		header *Header
		want   string
	}{
		{
			name:   "returns client type constant",
			header: &Header{},
			want:   ClientType,
		},
		{
			name:   "nil header still returns constant",
			header: nil,
			want:   ClientType,
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			var got string
			if tc.header != nil {
				got = tc.header.ClientType()
			} else {
				// For nil header, we need to call it on a valid Header
				// since methods can't be called on nil in Gno
				got = (&Header{}).ClientType()
			}
			if got != tc.want {
				t.Fatalf("ClientType: got %s want %s", got, tc.want)
			}
		})
	}
}

func TestNewLightHeader(t *testing.T) {
	cases := []struct {
		name               string
		height             int64
		timeSeconds        int64
		timeNanos          int32
		validatorsHash     []byte
		nextValidatorsHash []byte
		appHash            []byte
		wantHeight         int64
		wantTimeSeconds    int64
		wantTimeNanos      int32
		wantVHash          []byte
		wantNVHash         []byte
		wantAHash          []byte
	}{
		{
			name:               "valid light header with all fields",
			height:             42,
			timeSeconds:        1000,
			timeNanos:          500,
			validatorsHash:     []byte{0x01, 0x02, 0x03},
			nextValidatorsHash: []byte{0x04, 0x05, 0x06},
			appHash:            []byte{0x07, 0x08, 0x09},
			wantHeight:         42,
			wantTimeSeconds:    1000,
			wantTimeNanos:      500,
			wantVHash:          []byte{0x01, 0x02, 0x03},
			wantNVHash:         []byte{0x04, 0x05, 0x06},
			wantAHash:          []byte{0x07, 0x08, 0x09},
		},
		{
			name:               "light header with zero values",
			height:             0,
			timeSeconds:        0,
			timeNanos:          0,
			validatorsHash:     []byte{},
			nextValidatorsHash: []byte{},
			appHash:            []byte{},
			wantHeight:         0,
			wantTimeSeconds:    0,
			wantTimeNanos:      0,
			wantVHash:          []byte{},
			wantNVHash:         []byte{},
			wantAHash:          []byte{},
		},
		{
			name:               "light header with 32-byte hashes",
			height:             12345,
			timeSeconds:        1704067200,
			timeNanos:          999999999,
			validatorsHash:     repeat32(0xAA),
			nextValidatorsHash: repeat32(0xBB),
			appHash:            repeat32(0xCC),
			wantHeight:         12345,
			wantTimeSeconds:    1704067200,
			wantTimeNanos:      999999999,
			wantVHash:          repeat32(0xAA),
			wantNVHash:         repeat32(0xBB),
			wantAHash:          repeat32(0xCC),
		},
		{
			name:               "light header with negative time seconds",
			height:             1,
			timeSeconds:        -86400,
			timeNanos:          0,
			validatorsHash:     []byte{0xFF},
			nextValidatorsHash: []byte{0xEE},
			appHash:            []byte{0xDD},
			wantHeight:         1,
			wantTimeSeconds:    -86400,
			wantTimeNanos:      0,
			wantVHash:          []byte{0xFF},
			wantNVHash:         []byte{0xEE},
			wantAHash:          []byte{0xDD},
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got := NewLightHeader(
				tc.height,
				tc.timeSeconds,
				tc.timeNanos,
				tc.validatorsHash,
				tc.nextValidatorsHash,
				tc.appHash,
			)

			if got == nil {
				t.Fatal("NewLightHeader returned nil")
			}
			if got.Height != tc.wantHeight {
				t.Fatalf("Height: got %d want %d", got.Height, tc.wantHeight)
			}
			if got.TimeSeconds != tc.wantTimeSeconds {
				t.Fatalf("TimeSeconds: got %d want %d", got.TimeSeconds, tc.wantTimeSeconds)
			}
			if got.TimeNanos != tc.wantTimeNanos {
				t.Fatalf("TimeNanos: got %d want %d", got.TimeNanos, tc.wantTimeNanos)
			}
			bytesEq(t, "ValidatorsHash", got.ValidatorsHash, tc.wantVHash)
			bytesEq(t, "NextValidatorsHash", got.NextValidatorsHash, tc.wantNVHash)
			bytesEq(t, "AppHash", got.AppHash, tc.wantAHash)
		})
	}
}
