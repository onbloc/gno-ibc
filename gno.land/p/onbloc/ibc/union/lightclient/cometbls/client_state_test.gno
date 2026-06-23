package cometbls

import (
	"strings"
	"testing"

	"gno.land/p/onbloc/ibc/union/types"
)

// validClientState returns a ClientState that passes Validate.
func validClientState() ClientState {
	return ClientState{
		ChainID:         "test-chain",
		TrustingPeriod:  1000,
		UnbondingPeriod: 2000,
		MaxClockDrift:   100,
		FrozenHeight:    types.NewHeight(0),
		LatestHeight:    types.NewHeight(100),
	}
}

func TestClientState_Validate(t *testing.T) {
	cases := []struct {
		name    string
		setup   func(*ClientState)
		wantErr string
	}{
		{"valid", func(*ClientState) {}, ""},
		{"empty chain id", func(cs *ClientState) { cs.ChainID = "   " }, "chain"},
		{"chain id too long", func(cs *ClientState) { cs.ChainID = strings.Repeat("x", MaxChainIDLen+1) }, "chain-id"},
		{"chain id max length", func(cs *ClientState) { cs.ChainID = strings.Repeat("x", MaxChainIDLen) }, ""},
		{"zero trusting period", func(cs *ClientState) { cs.TrustingPeriod = 0 }, "trusting period"},
		{"zero unbonding period", func(cs *ClientState) { cs.UnbondingPeriod = 0 }, "unbonding period"},
		{"zero max clock drift", func(cs *ClientState) { cs.MaxClockDrift = 0 }, "max clock drift"},
		{"zero latest height", func(cs *ClientState) { cs.LatestHeight = types.NewHeight(0) }, "latest height"},
		{"trusting period not less than unbonding", func(cs *ClientState) { cs.TrustingPeriod = cs.UnbondingPeriod }, "trusting period"},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			cs := validClientState()
			tc.setup(&cs)
			err := cs.Validate()
			if tc.wantErr == "" {
				if err != nil {
					t.Fatalf("unexpected error: %v", err)
				}
				return
			}
			requireErrorContains(t, err, tc.wantErr)
		})
	}
}

func TestClientState_IsExpired(t *testing.T) {
	cs := validClientState() // TrustingPeriod = 1000

	cases := []struct {
		name            string
		latestTimestamp uint64
		want            bool
	}{
		{"expires exactly at now is active", testNow - 1000, false},
		{"expires after now is active", testNow - 999, false},
		{"expired before now", testNow - 1001, true},
		{"trusting period overflow expires", ^uint64(0) - 999, true},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			if got := cs.IsExpired(tc.latestTimestamp, testNow); got != tc.want {
				t.Fatalf("IsExpired: got %v want %v", got, tc.want)
			}
		})
	}
}

func TestNewClientState(t *testing.T) {
	cases := []struct {
		name            string
		chainID         string
		trustingPeriod  uint64
		unbondingPeriod uint64
		maxClockDrift   uint64
		frozenHeight    types.Height
		latestHeight    types.Height
		contractAddress types.H256
		wantNil         bool
		assert          func(*testing.T, *ClientState)
	}{
		{
			name:            "valid all fields",
			chainID:         "test-chain",
			trustingPeriod:  1000,
			unbondingPeriod: 2000,
			maxClockDrift:   100,
			frozenHeight:    types.NewHeight(0),
			latestHeight:    types.NewHeight(100),
			contractAddress: types.H256{1, 2, 3},
			wantNil:         false,
			assert: func(t *testing.T, cs *ClientState) {
				if cs.ChainID != "test-chain" {
					t.Errorf("ChainID: got %q want test-chain", cs.ChainID)
				}
				if cs.TrustingPeriod != 1000 {
					t.Errorf("TrustingPeriod: got %d want 1000", cs.TrustingPeriod)
				}
				if cs.UnbondingPeriod != 2000 {
					t.Errorf("UnbondingPeriod: got %d want 2000", cs.UnbondingPeriod)
				}
				if cs.MaxClockDrift != 100 {
					t.Errorf("MaxClockDrift: got %d want 100", cs.MaxClockDrift)
				}
				if !cs.FrozenHeight.IsZero() {
					t.Errorf("FrozenHeight: got %v want zero", cs.FrozenHeight)
				}
				if cs.LatestHeight.RevisionHeight != 100 {
					t.Errorf("LatestHeight: got %d want 100", cs.LatestHeight.RevisionHeight)
				}
				if cs.ContractAddress[0] != 1 || cs.ContractAddress[1] != 2 || cs.ContractAddress[2] != 3 {
					t.Errorf("ContractAddress: got %v want [1,2,3,...]", cs.ContractAddress)
				}
			},
		},
		{
			name:            "zero frozen height",
			chainID:         "test-chain",
			trustingPeriod:  1000,
			unbondingPeriod: 2000,
			maxClockDrift:   100,
			frozenHeight:    types.NewHeight(0),
			latestHeight:    types.NewHeight(50),
			contractAddress: types.H256{},
			wantNil:         false,
			assert: func(t *testing.T, cs *ClientState) {
				if !cs.FrozenHeight.IsZero() {
					t.Errorf("FrozenHeight should be zero, got %v", cs.FrozenHeight)
				}
			},
		},
		{
			name:            "non-zero frozen height",
			chainID:         "test-chain",
			trustingPeriod:  1000,
			unbondingPeriod: 2000,
			maxClockDrift:   100,
			frozenHeight:    types.NewHeight(123),
			latestHeight:    types.NewHeight(200),
			contractAddress: types.H256{},
			wantNil:         false,
			assert: func(t *testing.T, cs *ClientState) {
				if cs.FrozenHeight.RevisionHeight != 123 {
					t.Errorf("FrozenHeight: got %d want 123", cs.FrozenHeight.RevisionHeight)
				}
			},
		},
		{
			name:            "empty contract address",
			chainID:         "test-chain",
			trustingPeriod:  1000,
			unbondingPeriod: 2000,
			maxClockDrift:   100,
			frozenHeight:    types.NewHeight(0),
			latestHeight:    types.NewHeight(100),
			contractAddress: types.H256{},
			wantNil:         false,
			assert: func(t *testing.T, cs *ClientState) {
				for i := range cs.ContractAddress {
					if cs.ContractAddress[i] != 0 {
						t.Errorf("ContractAddress[%d]: got %d want 0", i, cs.ContractAddress[i])
					}
				}
			},
		},
		{
			name:            "max uint64 values",
			chainID:         "max-chain",
			trustingPeriod:  1,
			unbondingPeriod: ^uint64(0),
			maxClockDrift:   ^uint64(0),
			frozenHeight:    types.NewHeight(0),
			latestHeight:    types.NewHeight(^uint64(0)),
			contractAddress: types.H256{255, 255, 255},
			wantNil:         false,
			assert: func(t *testing.T, cs *ClientState) {
				if cs.UnbondingPeriod != ^uint64(0) {
					t.Errorf("UnbondingPeriod: got %d want max uint64", cs.UnbondingPeriod)
				}
				if cs.MaxClockDrift != ^uint64(0) {
					t.Errorf("MaxClockDrift: got %d want max uint64", cs.MaxClockDrift)
				}
				if cs.LatestHeight.RevisionHeight != ^uint64(0) {
					t.Errorf("LatestHeight: got %d want max uint64", cs.LatestHeight.RevisionHeight)
				}
			},
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got := NewClientState(
				tc.chainID,
				tc.trustingPeriod,
				tc.unbondingPeriod,
				tc.maxClockDrift,
				tc.frozenHeight,
				tc.latestHeight,
				tc.contractAddress,
			)
			if tc.wantNil {
				if got != nil {
					t.Errorf("NewClientState: got non-nil want nil")
				}
				return
			}
			if got == nil {
				t.Fatalf("NewClientState: got nil want non-nil")
			}
			if tc.assert != nil {
				tc.assert(t, got)
			}
		})
	}
}

func TestClientState_Getters(t *testing.T) {
	cases := []struct {
		name           string
		chainID        string
		latestHeight   types.Height
		wantChainID    string
		wantRevHeight  uint64
		wantClientType string
	}{
		{"valid basic", "test-chain", types.NewHeight(100), "test-chain", 100, ClientType},
		{"empty chain id", "", types.NewHeight(50), "", 50, ClientType},
		{"chain id with spaces", "  test  ", types.NewHeight(200), "  test  ", 200, ClientType},
		{"zero height", "test-chain", types.NewHeight(0), "test-chain", 0, ClientType},
		{"max height", "test-chain", types.NewHeight(^uint64(0)), "test-chain", ^uint64(0), ClientType},
		{"numeric chain id", "12345", types.NewHeight(999), "12345", 999, ClientType},
		{"special chars chain id", "chain_0-test", types.NewHeight(1), "chain_0-test", 1, ClientType},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			cs := NewClientState(
				tc.chainID,
				1000,
				2000,
				100,
				types.NewHeight(0),
				tc.latestHeight,
				types.H256{},
			)

			if got := cs.GetChainID(); got != tc.wantChainID {
				t.Errorf("GetChainID: got %q want %q", got, tc.wantChainID)
			}
			if got := cs.GetLatestHeight().RevisionHeight; got != tc.wantRevHeight {
				t.Errorf("GetLatestHeight: got %d want %d", got, tc.wantRevHeight)
			}
			if got := cs.ClientType(); got != tc.wantClientType {
				t.Errorf("ClientType: got %q want %q", got, tc.wantClientType)
			}
		})
	}
}

func TestClientState_ZeroCustomFields(t *testing.T) {
	cs := validClientState()
	cs.FrozenHeight = FrozenHeight

	z := cs.ZeroCustomFields()
	if z.ChainID != cs.ChainID {
		t.Errorf("ChainID: got %q want %q", z.ChainID, cs.ChainID)
	}
	if z.UnbondingPeriod != cs.UnbondingPeriod {
		t.Errorf("UnbondingPeriod: got %d want %d", z.UnbondingPeriod, cs.UnbondingPeriod)
	}
	if z.LatestHeight.RevisionHeight != cs.LatestHeight.RevisionHeight {
		t.Errorf("LatestHeight: got %d want %d", z.LatestHeight.RevisionHeight, cs.LatestHeight.RevisionHeight)
	}
	if z.TrustingPeriod != 0 || z.MaxClockDrift != 0 {
		t.Error("custom fields TrustingPeriod/MaxClockDrift should be zeroed")
	}
	if !z.FrozenHeight.IsZero() {
		t.Error("FrozenHeight should be zeroed")
	}
}
