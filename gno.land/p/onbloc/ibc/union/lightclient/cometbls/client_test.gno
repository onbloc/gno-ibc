package cometbls

import (
	"testing"

	"gno.land/p/onbloc/ibc/union/lightclient"
	"gno.land/p/onbloc/ibc/union/types"
)

// newTestClient builds a CometblsLightClient with a single consensus state at
// height 100 and a zero owner address.
func newTestClient(t *testing.T) *CometblsLightClient {
	t.Helper()
	cs := validClientState()
	consensus := &ConsensusState{
		Timestamp:          testNow,
		Root:               MerkleRoot{Hash: repeat32(0xAB)},
		NextValidatorsHash: repeat32(0xCD),
	}
	c, err := NewCometblsLightClient(&cs, consensus)
	if err != nil {
		t.Fatalf("NewCometblsLightClient: %v", err)
	}
	return c
}

func TestClientAccessors(t *testing.T) {
	c := newTestClient(t)

	if c.GetLatestHeight() != 100 {
		t.Errorf("GetLatestHeight: got %d want 100", c.GetLatestHeight())
	}
	if c.GetCounterpartyChainID() != "test-chain" {
		t.Errorf("GetCounterpartyChainID: got %q want test-chain", c.GetCounterpartyChainID())
	}
	if c.GetTimestamp() != types.Timestamp(testNow) {
		t.Errorf("GetTimestamp: got %d want %d", c.GetTimestamp(), testNow)
	}
}

func TestVerifyCreationEmpty(t *testing.T) {
	// Union reference: cometbls verify_creation returns ClientCreationResult::new().
	c := newTestClient(t)
	var caller, relayer address
	res, err := c.VerifyCreation(caller, relayer)
	if err != nil {
		t.Fatalf("VerifyCreation: %v", err)
	}
	if len(res.ClientStateBytes) != 0 {
		t.Fatal("VerifyCreation must not return client state bytes")
	}
}

// twoExistProof returns a MerkleProof wire buffer containing two existence
// commitment proofs (matching GetSDKProofSpecs length of 2).
func twoExistProof() []byte {
	ep1 := encodeExistenceProof([]byte("k1"), []byte("v1"), nil, nil)
	ep2 := encodeExistenceProof([]byte("k2"), []byte("v2"), nil, nil)
	return encodeMerkleProof(encodeCommitmentExist(ep1), encodeCommitmentExist(ep2))
}

func TestGetTimestamp(t *testing.T) {
	testCases := []struct {
		name     string
		malleate func(*CometblsLightClient)
		want     types.Timestamp
	}{
		{
			name: "latest consensus state",
			want: types.Timestamp(testNow),
		},
		{
			name: "missing latest consensus state",
			malleate: func(c *CometblsLightClient) {
				c.clientState.LatestHeight = types.NewHeight(999)
			},
			want: 0,
		},
	}
	for _, tc := range testCases {
		t.Run(tc.name, func(t *testing.T) {
			c := newTestClient(t)
			if tc.malleate != nil {
				tc.malleate(c)
			}

			if got := c.GetTimestamp(); got != tc.want {
				t.Fatalf("GetTimestamp: got %d want %d", got, tc.want)
			}
		})
	}
}

func TestGetTimestampAtHeight(t *testing.T) {
	c := newTestClient(t)

	got, err := c.GetTimestampAtHeight(100)
	if err != nil {
		t.Fatalf("GetTimestampAtHeight: %v", err)
	}
	if got != types.Timestamp(testNow) {
		t.Fatalf("GetTimestampAtHeight: got %d want %d", got, testNow)
	}

	_, err = c.GetTimestampAtHeight(999)
	requireErrorContains(t, err, "no consensus state at height")
}

func TestStatus(t *testing.T) {
	testCases := []struct {
		name     string
		malleate func(*CometblsLightClient)
		want     lightclient.Status
	}{
		{
			name: "active",
			want: lightclient.Active,
		},
		{
			name: "frozen",
			malleate: func(c *CometblsLightClient) {
				c.clientState.FrozenHeight = FrozenHeight
			},
			want: lightclient.Frozen,
		},
		{
			name: "missing latest consensus state is expired",
			malleate: func(c *CometblsLightClient) {
				c.clientState.LatestHeight = types.NewHeight(999)
			},
			want: lightclient.Expired,
		},
		{
			name: "trusting period elapsed",
			malleate: func(c *CometblsLightClient) {
				c.clientState.TrustingPeriod = 1
				c.setConsensusState(c.clientState.LatestHeight, &ConsensusState{
					Timestamp:          1,
					Root:               MerkleRoot{Hash: repeat32(0xAB)},
					NextValidatorsHash: repeat32(0xCD),
				})
			},
			want: lightclient.Expired,
		},
	}
	for _, tc := range testCases {
		t.Run(tc.name, func(t *testing.T) {
			c := newTestClient(t)
			if tc.malleate != nil {
				tc.malleate(c)
			}

			if got := c.Status(); got != tc.want {
				t.Fatalf("Status: got %q want %q", got, tc.want)
			}
		})
	}
}

func TestPrepareProof(t *testing.T) {
	oneExistProof := func() []byte {
		ep := encodeExistenceProof([]byte("k"), []byte("v"), nil, nil)
		return encodeMerkleProof(encodeCommitmentExist(ep))
	}

	testCases := []struct {
		name       string
		height     uint64
		proof      []byte
		wantProofs int
		wantErr    string
	}{
		{
			name:    "height above latest",
			height:  200,
			proof:   twoExistProof(),
			wantErr: "client state height < proof height",
		},
		{
			name:    "undecodable proof",
			height:  100,
			proof:   []byte{0x0a, 0xff},
			wantErr: "failed to decode proof",
		},
		{
			name:    "proof count mismatch",
			height:  100,
			proof:   oneExistProof(),
			wantErr: "length of specs",
		},
		{
			name:    "consensus state not found",
			height:  50,
			proof:   twoExistProof(),
			wantErr: "proof was constructed against a height that exists",
		},
		{
			name:       "valid shared proof preparation",
			height:     100,
			proof:      twoExistProof(),
			wantProofs: 2,
		},
	}
	for _, tc := range testCases {
		t.Run(tc.name, func(t *testing.T) {
			c := newTestClient(t)

			consensusState, storageProof, merklePath, err := c.prepareProof(c.clientState, tc.height, []byte("key"), tc.proof)
			if tc.wantErr != "" {
				requireErrorContains(t, err, tc.wantErr)
				return
			}
			if err != nil {
				t.Fatalf("prepareProof: %v", err)
			}
			if consensusState == nil {
				t.Fatal("prepareProof returned nil consensus state")
			}
			if len(storageProof) != tc.wantProofs {
				t.Fatalf("storage proof count: got %d want %d", len(storageProof), tc.wantProofs)
			}
			if len(merklePath.KeyPath) != 2 {
				t.Fatalf("merkle path length: got %d want 2", len(merklePath.KeyPath))
			}
			bytesEq(t, "module key", merklePath.KeyPath[0], moduleKey)
		})
	}
}

func TestVerifyNonMembership(t *testing.T) {
	twoProofNonexist := func() []byte {
		nep := encodeNonExistenceProof([]byte("k"), nil, nil)
		ep := encodeExistenceProof([]byte("k"), []byte("v"), nil, nil)
		return encodeMerkleProof(encodeCommitmentNonexist(nep), encodeCommitmentExist(ep))
	}
	oneProofNonexist := func() []byte {
		nep := encodeNonExistenceProof([]byte("k"), nil, nil)
		return encodeMerkleProof(encodeCommitmentNonexist(nep))
	}

	testCases := []struct {
		name    string
		height  uint64
		proof   []byte
		wantErr string
	}{
		{
			name:    "consensus state not found",
			height:  50,
			proof:   twoProofNonexist(),
			wantErr: "proof was constructed against a height that exists",
		},
		{
			name:    "first proof is not non-existence proof",
			height:  100,
			proof:   twoExistProof(),
			wantErr: "must be non-existence proof",
		},
		{
			name:    "proof count mismatch",
			height:  100,
			proof:   oneProofNonexist(),
			wantErr: "length of specs",
		},
	}
	for _, tc := range testCases {
		t.Run(tc.name, func(t *testing.T) {
			c := newTestClient(t)
			err := c.VerifyNonMembership(tc.height, []byte("key"), tc.proof)
			requireErrorContains(t, err, tc.wantErr)
		})
	}
}

func TestUpdateState(t *testing.T) {
	testCases := []struct {
		name                 string
		trustedHeight        uint64
		signedHeight         uint64
		wantLatestHeight     types.Height
		wantUpdateHeight     uint64
		wantClientStateBytes bool
	}{
		{
			name:                 "stores consensus and advances latest height",
			trustedHeight:        100,
			signedHeight:         101,
			wantLatestHeight:     types.NewHeight(101),
			wantUpdateHeight:     101,
			wantClientStateBytes: true,
		},
		{
			name:             "stores older height without regressing latest height",
			trustedHeight:    50,
			signedHeight:     60,
			wantLatestHeight: types.NewHeight(100),
			wantUpdateHeight: 60,
		},
	}
	for _, tc := range testCases {
		t.Run(tc.name, func(t *testing.T) {
			c := newTestClient(t)
			trustedConsensusState, found := c.getConsensusState(types.NewHeight(100))
			if !found {
				t.Fatal("trusted consensus state missing")
			}
			h := updateStateTestHeader(tc.trustedHeight, tc.signedHeight, testNow+1_000_000_000)
			h.SignedHeader.AppHash = repeat32(0x44)
			h.SignedHeader.NextValidatorsHash = repeat32(0x45)

			update := c.updateState(c.clientState, trustedConsensusState, h)

			if c.clientState.LatestHeight != tc.wantLatestHeight {
				t.Fatalf("latest height: got %s want %s", c.clientState.LatestHeight, tc.wantLatestHeight)
			}
			if update.Height != tc.wantUpdateHeight {
				t.Fatalf("update height: got %d want %d", update.Height, tc.wantUpdateHeight)
			}
			if (len(update.ClientStateBytes) > 0) != tc.wantClientStateBytes {
				t.Fatalf("client state bytes present: got %v want %v", len(update.ClientStateBytes) > 0, tc.wantClientStateBytes)
			}
			if len(update.ConsensusStateBytes) == 0 {
				t.Fatal("update must include consensus state bytes")
			}
			got, found := c.getConsensusState(types.NewHeight(tc.signedHeight))
			if !found {
				t.Fatalf("consensus state for height %d not stored", tc.signedHeight)
			}
			if got.Timestamp != testNow+1_000_000_000 {
				t.Fatalf("stored timestamp: got %d want %d", got.Timestamp, testNow+1_000_000_000)
			}
			bytesEq(t, "stored app hash", got.Root.Hash, repeat32(0x44))
			bytesEq(t, "stored next validators hash", got.NextValidatorsHash, repeat32(0x45))
		})
	}
}

func TestMakeStateUpdate(t *testing.T) {
	consensusState := &ConsensusState{
		Timestamp:          testNow,
		Root:               MerkleRoot{Hash: repeat32(0xAB)},
		NextValidatorsHash: repeat32(0xCD),
	}

	update := makeStateUpdate(types.NewHeight(123), consensusState)

	if update.Height != 123 {
		t.Fatalf("height: got %d want 123", update.Height)
	}
	if len(update.ClientStateBytes) != 0 {
		t.Fatal("makeStateUpdate must not include client state bytes")
	}
	if len(update.ConsensusStateBytes) == 0 {
		t.Fatal("makeStateUpdate must include consensus state bytes")
	}
}

func TestConsensusStateStorage(t *testing.T) {
	c := newTestClient(t)
	height := types.NewHeight(123)
	consensusState := &ConsensusState{
		Timestamp:          456,
		Root:               MerkleRoot{Hash: repeat32(0x10)},
		NextValidatorsHash: repeat32(0x11),
	}

	if c.hasConsensusState(height) {
		t.Fatal("hasConsensusState: got true before storing consensus state")
	}
	if _, found := c.getConsensusState(height); found {
		t.Fatal("getConsensusState: found consensus state before storing")
	}

	c.setConsensusState(height, consensusState)

	if !c.hasConsensusState(height) {
		t.Fatal("hasConsensusState: got false after storing consensus state")
	}
	got, found := c.getConsensusState(height)
	if !found {
		t.Fatal("getConsensusState: missing stored consensus state")
	}
	if got.Timestamp != consensusState.Timestamp {
		t.Fatalf("timestamp: got %d want %d", got.Timestamp, consensusState.Timestamp)
	}
}
