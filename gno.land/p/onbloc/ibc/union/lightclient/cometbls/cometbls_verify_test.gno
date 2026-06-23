package cometbls

import (
	"testing"
	"time"

	"gno.land/p/onbloc/ibc/union/types"
)

func TestVerifyHeader(t *testing.T) {
	testCases := []struct {
		name     string
		malleate func(*CometblsLightClient, *ConsensusState, *Header) time.Time
		wantErr  string
	}{
		{
			name: "height checked before expiry",
			malleate: func(c *CometblsLightClient, _ *ConsensusState, h *Header) time.Time {
				h.SignedHeader.Height = 100
				return time.Unix(0, int64(testNow+c.clientState.TrustingPeriod+1))
			},
			wantErr: "header height <= consensus state height",
		},
		{
			name: "timestamp checked before expiry",
			malleate: func(c *CometblsLightClient, _ *ConsensusState, h *Header) time.Time {
				return time.Unix(0, int64(testNow+c.clientState.TrustingPeriod+1))
			},
			wantErr: ErrInvalidHeaderTimestamp,
		},
		{
			name: "expiry boundary proceeds to adjacent validator hash check",
			malleate: func(c *CometblsLightClient, _ *ConsensusState, h *Header) time.Time {
				h.SignedHeader.TimeSeconds = int64((testNow + 1) / 1_000_000_000)
				h.SignedHeader.TimeNanos = int32((testNow + 1) % 1_000_000_000)
				return time.Unix(0, int64(testNow+c.clientState.TrustingPeriod))
			},
			wantErr: "the validators hash",
		},
		{
			name: "invalid zkp",
			malleate: func(_ *CometblsLightClient, trustedConsensusState *ConsensusState, h *Header) time.Time {
				h.SignedHeader.TimeSeconds = int64((testNow + 1) / 1_000_000_000)
				h.SignedHeader.TimeNanos = int32((testNow + 1) % 1_000_000_000)
				h.SignedHeader.ValidatorsHash = trustedConsensusState.NextValidatorsHash
				return time.Unix(0, int64(testNow))
			},
			wantErr: "zero-knowledge proof verification failed",
		},
		{
			name: "max clock drift overflow",
			malleate: func(c *CometblsLightClient, _ *ConsensusState, h *Header) time.Time {
				c.clientState.MaxClockDrift = ^uint64(0) - testNow + 1
				h.SignedHeader.TimeSeconds = int64((testNow + 1) / 1_000_000_000)
				h.SignedHeader.TimeNanos = int32((testNow + 1) % 1_000_000_000)
				return time.Unix(0, int64(testNow))
			},
			wantErr: ErrMathOverflow,
		},
	}
	for _, tc := range testCases {
		t.Run(tc.name, func(t *testing.T) {
			c := newTestClient(t)
			trustedConsensusState, found := c.getConsensusState(types.NewHeight(100))
			if !found {
				t.Fatal("trusted consensus state missing")
			}
			h := updateStateTestHeader(100, 101, testNow)

			now := tc.malleate(c, trustedConsensusState, h)
			err := c.verifyHeader(c.clientState, trustedConsensusState, h, now)

			requireErrorContains(t, err, tc.wantErr)
		})
	}
}

func TestIsClientExpiredAt(t *testing.T) {
	testCases := []struct {
		name      string
		timestamp uint64
		period    uint64
		now       uint64
		want      bool
	}{
		{"before boundary", testNow - 999, 1000, testNow, false},
		{"at boundary", testNow - 1000, 1000, testNow, false},
		{"after boundary", testNow - 1001, 1000, testNow, true},
		{"overflow", ^uint64(0) - 999, 1000, testNow, true},
	}
	for _, tc := range testCases {
		t.Run(tc.name, func(t *testing.T) {
			if got := isClientExpiredAt(tc.timestamp, tc.period, tc.now); got != tc.want {
				t.Fatalf("isClientExpiredAt: got %v want %v", got, tc.want)
			}
		})
	}
}

func TestCheckedAddUint64(t *testing.T) {
	testCases := []struct {
		name         string
		a            uint64
		b            uint64
		want         uint64
		wantOverflow bool
	}{
		{"zero", 0, 0, 0, false},
		{"no overflow", 41, 1, 42, false},
		{"max without overflow", ^uint64(0) - 1, 1, ^uint64(0), false},
		{"overflow", ^uint64(0), 1, 0, true},
	}
	for _, tc := range testCases {
		t.Run(tc.name, func(t *testing.T) {
			got, overflow := checkedAddUint64(tc.a, tc.b)
			if got != tc.want {
				t.Fatalf("sum: got %d want %d", got, tc.want)
			}
			if overflow != tc.wantOverflow {
				t.Fatalf("overflow: got %v want %v", overflow, tc.wantOverflow)
			}
		})
	}
}

func TestVerifyMisbehaviour(t *testing.T) {
	c := newTestClient(t)
	c.clientState.TrustingPeriod = 10_000_000_000
	m := &Misbehaviour{
		Header1: updateStateTestHeader(100, 101, testNow+1_000_000_000),
		Header2: updateStateTestHeader(100, 102, testNow+2_000_000_000),
	}

	err := c.verifyMisbehaviour(m, time.Unix(int64(testNow/1_000_000_000)+3, 0))

	requireErrorContains(t, err, ErrInvalidMisbehaviourHeaderSequence)
}

func TestSignedHeadersEqual(t *testing.T) {
	base := newTestHeader(100, 2000, 7, 90, []byte{0x01}).SignedHeader

	cases := []struct {
		name string
		a    *LightHeader
		b    *LightHeader
		want bool
	}{
		{"both nil", nil, nil, true},
		{"left nil", nil, cloneLightHeader(base), false},
		{"right nil", cloneLightHeader(base), nil, false},
		{"identical", cloneLightHeader(base), cloneLightHeader(base), true},
		{"height differs", cloneLightHeaderWith(base, func(h *LightHeader) { h.Height++ }), cloneLightHeader(base), false},
		{"seconds differ", cloneLightHeaderWith(base, func(h *LightHeader) { h.TimeSeconds++ }), cloneLightHeader(base), false},
		{"nanos differ", cloneLightHeaderWith(base, func(h *LightHeader) { h.TimeNanos++ }), cloneLightHeader(base), false},
		{"validators hash differs", cloneLightHeaderWith(base, func(h *LightHeader) { h.ValidatorsHash[0] ^= 0xff }), cloneLightHeader(base), false},
		{"next validators hash differs", cloneLightHeaderWith(base, func(h *LightHeader) { h.NextValidatorsHash[0] ^= 0xff }), cloneLightHeader(base), false},
		{"app hash differs", cloneLightHeaderWith(base, func(h *LightHeader) { h.AppHash[0] ^= 0xff }), cloneLightHeader(base), false},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			if got := signedHeadersEqual(tc.a, tc.b); got != tc.want {
				t.Fatalf("signedHeadersEqual: got %v want %v", got, tc.want)
			}
		})
	}
}

// TestVerifyChainedMembershipProof covers error branches in verifyChainedMembershipProof.
func TestVerifyChainedMembershipProof(t *testing.T) {
	c := newTestClient(t)

	cases := []struct {
		name    string
		root    []byte
		proofs  []byte
		keys    []byte
		value   []byte
		index   int
		wantErr string
	}{
		{
			name:    "empty proofs with matching root/value succeeds",
			root:    []byte("root"),
			proofs:  []byte{}, // empty proof list
			keys:    []byte{},
			value:   []byte("root"), // value equals root
			index:   0,
			wantErr: "",
		},
		{
			name:    "empty proofs with root mismatch fails",
			root:    []byte("root"),
			proofs:  []byte{},
			keys:    []byte{},
			value:   []byte("different"),
			index:   0,
			wantErr: "proof did not commit to expected root",
		},
		{
			name: "non-existence proof where existence required",
			root: []byte("root"),
			proofs: func() []byte {
				nep := encodeNonExistenceProof([]byte("k"), nil, nil)
				return encodeMerkleProof(encodeCommitmentNonexist(nep))
			}(),
			keys:    []byte{},
			value:   []byte("v"),
			index:   0,
			wantErr: "commitment proof must be existence proof",
		},
		{
			name:    "decode failure propagates",
			root:    []byte("root"),
			proofs:  []byte{0x0a, 0xff}, // truncated
			keys:    []byte{},
			value:   []byte("v"),
			index:   0,
			wantErr: "invalid",
		},
		{
			name: "proof index beyond length skips loop",
			root: []byte("root"),
			proofs: func() []byte {
				ep := encodeExistenceProof([]byte("k"), []byte("v"), nil, nil)
				return encodeMerkleProof(encodeCommitmentExist(ep))
			}(),
			keys:    []byte{},
			value:   []byte("root"), // value equals root, so matching after index skips proof
			index:   5,              // index beyond proofs length
			wantErr: "",
		},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			proofs, err := DecodeProofs(tc.proofs)
			if tc.wantErr == "invalid" {
				// For this case we expect decode failure
			} else if err != nil && tc.wantErr != "" {
				t.Fatalf("unexpected DecodeProofs error: %v", err)
			}

			// Build a minimal merkle path for the test
			var merklePath struct{ KeyPath [][]byte }
			if len(tc.keys) > 0 {
				merklePath.KeyPath = append(merklePath.KeyPath, tc.keys)
			} else {
				merklePath.KeyPath = [][]byte{{'k'}}
			}

			err = c.verifyChainedMembershipProof(tc.root, proofs, merklePath, tc.value, tc.index)

			if tc.wantErr != "" {
				if err == nil || !contains(err.Error(), tc.wantErr) {
					t.Fatalf("expected error containing %q, got %v", tc.wantErr, err)
				}
				return
			}
			if err != nil {
				t.Fatalf("unexpected error: %v", err)
			}
		})
	}
}
