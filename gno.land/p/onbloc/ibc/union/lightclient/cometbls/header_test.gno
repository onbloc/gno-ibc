package cometbls

import (
	"encoding/hex"
	"strings"
	"testing"
	"time"

	"gno.land/p/nt/uassert/v0"

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
	t.Run("basic_zkp_2bytes", func(t *testing.T) {
		h := newTestHeader(42, 1000, 500, 10, []byte{0xAA, 0xBB})

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
				word32(256) + // offset to the dynamic bytes field
				word32(2) + // ZKP length
				hex.EncodeToString(zkpPadded),
		)
		got, err := EncodeHeader(h)
		if err != nil {
			t.Fatalf("unexpected error: %v", err)
		}
		bytesEq(t, "EncodeHeader/basic", got, want)
	})

	t.Run("nil_header", func(t *testing.T) {
		if _, err := EncodeHeader(nil); err == nil {
			t.Fatal("expected error for nil header")
		}
	})

	t.Run("short_hash_rejected", func(t *testing.T) {
		h := newTestHeader(1, 100, 0, 0, repeat32(0xFF))
		h.SignedHeader.ValidatorsHash = []byte{0x01} // not 32 bytes
		if _, err := EncodeHeader(h); err == nil {
			t.Fatal("expected error for non-32-byte validators hash")
		}
	})
}

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
		bytesEq(t, "ValidatorsHash", got.SignedHeader.ValidatorsHash, repeat32(0x01))
		bytesEq(t, "NextValidatorsHash", got.SignedHeader.NextValidatorsHash, repeat32(0x02))
		bytesEq(t, "AppHash", got.SignedHeader.AppHash, repeat32(0x03))
		if got.TrustedHeight.RevisionHeight != 10 {
			t.Fatalf("TrustedHeight: got %d want 10", got.TrustedHeight.RevisionHeight)
		}
		bytesEq(t, "ZKP", got.ZeroKnowledgeProof, zkp)
	})

	t.Run("too_short", func(t *testing.T) {
		_, err := DecodeHeader(make([]byte, 255))
		if err == nil {
			t.Fatal("expected error for short buffer")
		}
	})

	t.Run("timenanos_out_of_range", func(t *testing.T) {
		zkpPadded := make([]byte, 32)
		buf := mustHex(
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
		)
		_, err := DecodeHeader(buf)
		if err == nil {
			t.Fatal("expected error for TimeNanos >= 1e9")
		}
		want := "cometbls: TimeNanos out of range"
		if err.Error() != want {
			t.Fatalf("error: got %q want %q", err.Error(), want)
		}
	})
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
}

func TestHeaderValidateBasic(t *testing.T) {
	// Union reference: verify_header rejects stale heights and invalid header
	// timing before proof verification,
	// https://github.com/unionlabs/union/blob/1bb07590230e/cosmwasm/lightclient/cometbls/src/client.rs#L189.
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
				uassert.NoError(t, err)
				return
			}
			uassert.ErrorContains(t, err, tc.wantErr)
		})
	}
}

func TestHeaderGetHeightPreservesTrustedRevision(t *testing.T) {
	// Union reference: update_state rebuilds the untrusted height with the
	// trusted height revision,
	// https://github.com/unionlabs/union/blob/1bb07590230e/cosmwasm/lightclient/cometbls/src/client.rs#L288.
	h := newTestHeader(42, 1000, 500, 10, []byte{0xAA})
	h.TrustedHeight = heightPtr(types.NewHeightWithRevision(7, 10))

	got := h.GetHeight()
	uassert.Equal(t, got.RevisionNumber, uint64(7))
	uassert.Equal(t, got.RevisionHeight, uint64(42))
}

func verifyHeaderTestHeader(trustedHeight, signedHeight uint64, timestamp uint64) *Header {
	h := newTestHeader(
		int64(signedHeight),
		int64(timestamp/1_000_000_000),
		int32(timestamp%1_000_000_000),
		trustedHeight,
		[]byte{0x01},
	)
	return h
}

func heightPtr(height types.Height) *types.Height {
	return &height
}

func assertVerifyHeaderErrContains(t *testing.T, err error, want string) {
	t.Helper()
	if err == nil {
		t.Fatalf("expected error containing %q", want)
	}
	if !strings.Contains(err.Error(), want) {
		t.Fatalf("error: got %q want substring %q", err.Error(), want)
	}
}

func TestVerifyHeaderRejectsInvalidHeader(t *testing.T) {
	// Union reference: verify_header branch checks,
	// https://github.com/unionlabs/union/blob/1bb07590230e/cosmwasm/lightclient/cometbls/src/client.rs#L189.
	testCases := []struct {
		name      string
		malleate  func(*CometblsLightClient, *Header) time.Time
		wantParts []string
	}{
		{
			name: "missing trusted consensus state",
			malleate: func(c *CometblsLightClient, h *Header) time.Time {
				h.TrustedHeight = heightPtr(types.NewHeight(99))
				return time.Unix(int64(testNow/1_000_000_000)+2, 0)
			},
			wantParts: []string{"could not get trusted consensus state"},
		},
		{
			name: "expired trusted consensus state",
			malleate: func(c *CometblsLightClient, h *Header) time.Time {
				c.clientState.TrustingPeriod = 1
				return time.Unix(int64(testNow/1_000_000_000)+1, 0)
			},
			wantParts: []string{"trusted consensus state", "has expired"},
		},
		{
			name: "non-increasing timestamp",
			malleate: func(c *CometblsLightClient, h *Header) time.Time {
				c.clientState.TrustingPeriod = 10_000_000_000
				h.SignedHeader.TimeSeconds = int64(testNow / 1_000_000_000)
				h.SignedHeader.TimeNanos = int32(testNow % 1_000_000_000)
				return time.Unix(int64(testNow/1_000_000_000)+1, 0)
			},
			wantParts: []string{"greater than or equal to the new header timestamp"},
		},
		{
			name: "signed height not above trusted height",
			malleate: func(c *CometblsLightClient, h *Header) time.Time {
				c.clientState.TrustingPeriod = 10_000_000_000
				h.SignedHeader.Height = 100
				return time.Unix(int64(testNow/1_000_000_000)+2, 0)
			},
			wantParts: []string{"header height <= consensus state height"},
		},
		{
			name: "header time beyond max clock drift",
			malleate: func(c *CometblsLightClient, h *Header) time.Time {
				c.clientState.TrustingPeriod = 10_000_000_000
				c.clientState.MaxClockDrift = 10
				return time.Unix(0, int64(testNow))
			},
			wantParts: []string{"header time >= max drift"},
		},
		{
			name: "adjacent validator hash mismatch",
			malleate: func(c *CometblsLightClient, h *Header) time.Time {
				c.clientState.TrustingPeriod = 10_000_000_000
				h.SignedHeader.ValidatorsHash = repeat32(0xEE)
				return time.Unix(int64(testNow/1_000_000_000)+2, 0)
			},
			wantParts: []string{"doesn't match the trusted validators hash"},
		},
	}

	for _, tc := range testCases {
		t.Run(tc.name, func(t *testing.T) {
			c := newTestClient(t)
			h := verifyHeaderTestHeader(100, 101, testNow+1_000_000_000)
			now := tc.malleate(c, h)

			err := c.verifyHeader(h, now)

			for _, want := range tc.wantParts {
				assertVerifyHeaderErrContains(t, err, want)
			}
		})
	}
}

func TestUpdateStateStoresConsensusAndAdvancesLatestHeight(t *testing.T) {
	// Union reference: update_state overwrites client state only when the
	// untrusted height advances latest_height,
	// https://github.com/unionlabs/union/blob/1bb07590230e/cosmwasm/lightclient/cometbls/src/client.rs#L283.
	c := newTestClient(t)
	h := verifyHeaderTestHeader(100, 101, testNow+1_000_000_000)
	h.SignedHeader.AppHash = repeat32(0x44)
	h.SignedHeader.NextValidatorsHash = repeat32(0x45)

	update := c.updateState(h)

	if c.clientState.LatestHeight != types.NewHeight(101) {
		t.Fatalf("latest height: got %s want 101", c.clientState.LatestHeight)
	}
	if update.Height != 101 {
		t.Fatalf("update height: got %d want 101", update.Height)
	}
	if len(update.ClientStateBytes) == 0 {
		t.Fatal("update must include client state bytes when latest height advances")
	}
	if len(update.ConsensusStateBytes) == 0 {
		t.Fatal("update must include consensus state bytes for new height")
	}
	got, found := c.getConsensusState(types.NewHeight(101))
	if !found {
		t.Fatal("consensus state for height 101 not stored")
	}
	if got.Timestamp != testNow+1_000_000_000 {
		t.Fatalf("stored timestamp: got %d want %d", got.Timestamp, testNow+1_000_000_000)
	}
	bytesEq(t, "stored app hash", got.Root.Hash, repeat32(0x44))
	bytesEq(t, "stored next validators hash", got.NextValidatorsHash, repeat32(0x45))
}

func TestUpdateStateStoresOlderHeightWithoutRegressingLatestHeight(t *testing.T) {
	// Union reference: update_state returns StateUpdate without
	// overwrite_client_state for older/non-latest headers,
	// https://github.com/unionlabs/union/blob/1bb07590230e/cosmwasm/lightclient/cometbls/src/client.rs#L303.
	c := newTestClient(t)
	h := verifyHeaderTestHeader(50, 60, testNow+1_000_000_000)

	update := c.updateState(h)

	if c.clientState.LatestHeight != types.NewHeight(100) {
		t.Fatalf("latest height regressed: got %s want 100", c.clientState.LatestHeight)
	}
	if update.Height != 60 {
		t.Fatalf("update height: got %d want 60", update.Height)
	}
	if len(update.ClientStateBytes) != 0 {
		t.Fatal("older update must not include client state bytes")
	}
	if len(update.ConsensusStateBytes) == 0 {
		t.Fatal("older update must still include consensus state bytes")
	}
	if _, found := c.getConsensusState(types.NewHeight(60)); !found {
		t.Fatal("older valid consensus state should still be stored")
	}
}

func TestUpdateStateDuplicateHeightDoesNotRewriteStateBytes(t *testing.T) {
	// Union reference: update_state only returns a consensus update when the
	// untrusted height does not advance latest_height,
	// https://github.com/unionlabs/union/blob/1bb07590230e/cosmwasm/lightclient/cometbls/src/client.rs#L303.
	c := newTestClient(t)
	h := verifyHeaderTestHeader(90, 100, testNow+1_000_000_000)

	update := c.updateState(h)

	if update.Height != 100 {
		t.Fatalf("update height: got %d want 100", update.Height)
	}
	if len(update.ClientStateBytes) != 0 {
		t.Fatal("duplicate update must not include client state bytes")
	}
	if len(update.ConsensusStateBytes) != 0 {
		t.Fatal("duplicate update must not include consensus state bytes")
	}
}
