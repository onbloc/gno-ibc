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
			wantErr: ErrInvalidHeaderTimestamp.Error(),
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
			wantErr: ErrMathOverflow.Error(),
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
	c.clientState.MaxClockDrift = 10_000_000_000
	now := time.Unix(int64(testNow/1_000_000_000)+3, 0)
	testHeader := func(trustedHeight, signedHeight uint64, timestamp uint64) *Header {
		h := updateStateTestHeader(trustedHeight, signedHeight, timestamp)
		h.SignedHeader.ValidatorsHash = repeat32(0xCD)
		return h
	}

	cases := []struct {
		name         string
		setupHeaders func() (*Header, *Header)
		wantErr      string
	}{
		{
			name: "invalid sequence - headerA height < headerB height",
			setupHeaders: func() (*Header, *Header) {
				return testHeader(100, 101, testNow+1_000_000_000),
					testHeader(100, 102, testNow+2_000_000_000)
			},
			wantErr: ErrInvalidMisbehaviourHeaderSequence.Error(),
		},
		{
			name: "same height identical headers - no misbehaviour",
			setupHeaders: func() (*Header, *Header) {
				h1 := testHeader(100, 101, testNow+1_000_000_000)
				h2 := testHeader(100, 101, testNow+1_000_000_000)
				return h1, h2
			},
			wantErr: "zero-knowledge proof verification failed",
		},
		{
			name: "same height different validators hash - valid misbehaviour",
			setupHeaders: func() (*Header, *Header) {
				h1 := testHeader(100, 101, testNow+1_000_000_000)
				h2 := testHeader(100, 101, testNow+1_000_000_000)
				h2.SignedHeader.ValidatorsHash[0] ^= 0xFF
				return h1, h2
			},
			wantErr: "zero-knowledge proof verification failed",
		},
		{
			name: "same height different app hash - valid misbehaviour",
			setupHeaders: func() (*Header, *Header) {
				h1 := testHeader(100, 101, testNow+1_000_000_000)
				h2 := testHeader(100, 101, testNow+1_000_000_000)
				h2.SignedHeader.AppHash[0] ^= 0xFF
				return h1, h2
			},
			wantErr: "zero-knowledge proof verification failed",
		},
		{
			name: "same height different next validators hash - valid misbehaviour",
			setupHeaders: func() (*Header, *Header) {
				h1 := testHeader(100, 101, testNow+1_000_000_000)
				h2 := testHeader(100, 101, testNow+1_000_000_000)
				h2.SignedHeader.NextValidatorsHash[0] ^= 0xFF
				return h1, h2
			},
			wantErr: "zero-knowledge proof verification failed",
		},
		{
			name: "same height different timestamp - valid misbehaviour",
			setupHeaders: func() (*Header, *Header) {
				h1 := testHeader(100, 101, testNow+1_000_000_000)
				h2 := testHeader(100, 101, testNow+2_000_000_000)
				return h1, h2
			},
			wantErr: "zero-knowledge proof verification failed",
		},
		{
			name: "different height non-increasing time - valid misbehaviour",
			setupHeaders: func() (*Header, *Header) {
				h1 := testHeader(100, 102, testNow+1_000_000_000)
				h2 := testHeader(100, 101, testNow+2_000_000_000)
				return h1, h2
			},
			wantErr: "zero-knowledge proof verification failed",
		},
		{
			name: "different height same time - valid misbehaviour",
			setupHeaders: func() (*Header, *Header) {
				h1 := testHeader(100, 102, testNow+1_000_000_000)
				h2 := testHeader(100, 101, testNow+1_000_000_000)
				return h1, h2
			},
			wantErr: "zero-knowledge proof verification failed",
		},
		{
			name: "different height increasing time - no misbehaviour",
			setupHeaders: func() (*Header, *Header) {
				h1 := testHeader(100, 102, testNow+2_000_000_000)
				h2 := testHeader(100, 101, testNow+1_000_000_000)
				return h1, h2
			},
			wantErr: "zero-knowledge proof verification failed",
		},
		{
			name: "different height much later time - no misbehaviour",
			setupHeaders: func() (*Header, *Header) {
				h1 := testHeader(100, 105, testNow+5_000_000_000)
				h2 := testHeader(100, 101, testNow+1_000_000_000)
				return h1, h2
			},
			wantErr: "zero-knowledge proof verification failed",
		},
		{
			name: "same height different seconds - valid misbehaviour",
			setupHeaders: func() (*Header, *Header) {
				h1 := testHeader(100, 101, testNow+1_000_000_000)
				h2 := testHeader(100, 101, testNow+1_000_000_000+1_000_000_000)
				return h1, h2
			},
			wantErr: "zero-knowledge proof verification failed",
		},
		{
			name: "same height different nanos - valid misbehaviour",
			setupHeaders: func() (*Header, *Header) {
				h1 := testHeader(100, 101, testNow+1_000_000_000)
				h2 := testHeader(100, 101, testNow+1_000_000_000+1_000)
				return h1, h2
			},
			wantErr: "zero-knowledge proof verification failed",
		},
		{
			name: "height 1 apart decreasing time - valid misbehaviour",
			setupHeaders: func() (*Header, *Header) {
				h1 := testHeader(100, 103, testNow+1_000_000_000)
				h2 := testHeader(100, 102, testNow+2_000_000_000)
				return h1, h2
			},
			wantErr: "zero-knowledge proof verification failed",
		},
		{
			name: "height 10 apart reverse time - valid misbehaviour",
			setupHeaders: func() (*Header, *Header) {
				h1 := testHeader(100, 120, testNow+2_000_000_000)
				h2 := testHeader(100, 110, testNow+5_000_000_000)
				return h1, h2
			},
			wantErr: "zero-knowledge proof verification failed",
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			h1, h2 := tc.setupHeaders()
			m := &Misbehaviour{
				Header1: h1,
				Header2: h2,
			}

			err := c.verifyMisbehaviour(m, now)

			if tc.wantErr != "" {
				requireErrorContains(t, err, tc.wantErr)
			} else if err != nil {
				t.Fatalf("unexpected error: %v", err)
			}
		})
	}
}

func TestVerifyMisbehaviourHeader(t *testing.T) {
	cases := []struct {
		name    string
		setup   func(*testing.T) (*CometblsLightClient, *Header, time.Time)
		wantErr []string
	}{
		{
			name: "missing trusted consensus state",
			setup: func(t *testing.T) (*CometblsLightClient, *Header, time.Time) {
				c := newTestClient(t)
				h := updateStateTestHeader(999, 1000, testNow+1_000_000_000)
				now := time.Unix(int64(testNow/1_000_000_000)+2, 0)
				return c, h, now
			},
			wantErr: []string{
				ErrInvalidMisbehaviour.Error(),
				"could not get trusted consensus state",
			},
		},
		{
			name: "wraps verify header error",
			setup: func(t *testing.T) (*CometblsLightClient, *Header, time.Time) {
				c := newTestClient(t)
				c.clientState.TrustingPeriod = 10_000_000_000
				h := updateStateTestHeader(100, 101, testNow+1_000_000_000)
				now := time.Unix(int64(testNow/1_000_000_000)+2, 0)
				return c, h, now
			},
			wantErr: []string{
				ErrInvalidMisbehaviour.Error(),
				"verifying TestHeader in Misbehaviour failed",
				"the validators hash",
			},
		},
		{
			name: "verified header succeeds",
			setup: func(t *testing.T) (*CometblsLightClient, *Header, time.Time) {
				c, h := newDevnetMisbehaviourHeaderClient(t)
				now := time.Unix(devnetTimeSeconds+1, 0)
				return c, h, now
			},
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			c, h, now := tc.setup(t)
			err := c.verifyMisbehaviourHeader("TestHeader", h, now)
			if len(tc.wantErr) == 0 {
				if err != nil {
					t.Fatalf("unexpected error: %v", err)
				}
				return
			}
			for _, want := range tc.wantErr {
				requireErrorContains(t, err, want)
			}
		})
	}
}

const (
	devnetChainID     = "union-devnet-1337"
	devnetHeight      = int64(3405691582)
	devnetTimeSeconds = int64(1732205251)
	devnetTimeNanos   = int32(998131342)
	devnetTrusting    = uint64(100 * 365 * 24 * 3600 * 1_000_000_000)
	devnetMaxDrift    = uint64(100 * 365 * 24 * 3600 * 1_000_000_000)
)

// ref: gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/testing/realcometbls/fixtures.gno
func newDevnetMisbehaviourHeaderClient(t *testing.T) (*CometblsLightClient, *Header) {
	t.Helper()

	validatorsHash := mustHex("20ddfe7a0f75c65d876316091eccd494a54a2bb324c872015f73e528d53cb9c4")
	appHash := mustHex("ee7e3e58f98ac95d63ce93b270981df3ee54ca367f8d521ed1f444717595cd36")
	proof := mustHex(
		"03CF56142A1E03D2445A82100FEAF70C1CD95A731ED85792AFFF5792EC0BDD21" +
			"08991BB56F9043A269F88903DE616A9AB99A3C5AB778E566744B060456C5616C" +
			"06BCE7F1930421768C2CBD79F88D08EC3A52D7C9A867064E973064385E9C945E" +
			"02951190DD7CE1662546733DD540188C96E608CA750FEF36B39E2577833634C7" +
			"0AE6F1A6D00DC6C21446AAF285EF35D944E8782B131300574F9A889C7E708A23" +
			"25E9A78013BBE869D38B19C602DAF69644C77D177E99ED76398BCEE13C61FDBF" +
			"2E178A5BA028A36033E54D1D9A0071E82E04079A5305347EBAC6D66F6EBFA48B" +
			"1DA1BF9DC5A51EFA292E1DC7B85D26F18422EB386C48CA75434039764448BB96" +
			"268DDC2CF683DDCA4BD83DF21C5631CF784375EEBE77EABC2DE77886BF1D4839" +
			"2C9C52E063B4A7131EAB9ABBA12A9F26888BC37366D41AC7D4BAC0BF6755ACB0" +
			"09BF9F36F380B6D0EEAABF066503A1B6E01DCC965D968D7694E01B1755E6BDD2" +
			"1C7A80B41682748F9B7151714BE34AA79AAD48BBB2A84525F6CDF812658C6E4F",
	)
	trustedHeight := types.NewHeight(uint64(devnetHeight - 1))
	clientState := &ClientState{
		ChainID:         devnetChainID,
		TrustingPeriod:  devnetTrusting,
		UnbondingPeriod: devnetTrusting + 1,
		MaxClockDrift:   devnetMaxDrift,
		LatestHeight:    trustedHeight,
	}
	consensusState := &ConsensusState{
		Timestamp:          uint64(devnetTimeSeconds-1000) * 1_000_000_000,
		Root:               MerkleRoot{Hash: appHash},
		NextValidatorsHash: validatorsHash,
	}
	c, err := NewCometblsLightClient(clientState, consensusState)
	if err != nil {
		t.Fatalf("NewCometblsLightClient: %v", err)
	}

	h := &Header{
		SignedHeader: &LightHeader{
			Height:             devnetHeight,
			TimeSeconds:        devnetTimeSeconds,
			TimeNanos:          devnetTimeNanos,
			ValidatorsHash:     validatorsHash,
			NextValidatorsHash: validatorsHash,
			AppHash:            appHash,
		},
		TrustedHeight:      &trustedHeight,
		ZeroKnowledgeProof: proof,
	}

	return c, h
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
