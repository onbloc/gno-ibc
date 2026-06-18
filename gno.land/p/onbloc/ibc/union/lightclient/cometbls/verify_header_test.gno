package cometbls

import (
	"strings"
	"testing"
	"time"

	"gno.land/p/onbloc/ibc/union/types"
)

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
	c := newTestClient(t)
	h := verifyHeaderTestHeader(50, 60, testNow+1_000_000_000)

	update := c.updateState(h)

	if c.clientState.LatestHeight != types.NewHeight(100) {
		t.Fatalf("latest height regressed: got %s want 100", c.clientState.LatestHeight)
	}
	if update.Height != 60 {
		t.Fatalf("update height: got %d want 60", update.Height)
	}
	if _, found := c.getConsensusState(types.NewHeight(60)); !found {
		t.Fatal("older valid consensus state should still be stored")
	}
}

func TestUpdateStateDuplicateHeightDoesNotRewriteStateBytes(t *testing.T) {
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
