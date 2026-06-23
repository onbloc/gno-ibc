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

func TestClientStateValidate(t *testing.T) {
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

func TestClientStateIsExpired(t *testing.T) {
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

func TestClientStateGetters(t *testing.T) {
	cs := validClientState()
	if cs.GetChainID() != "test-chain" {
		t.Errorf("GetChainID: got %q want test-chain", cs.GetChainID())
	}
	if cs.GetLatestHeight().RevisionHeight != 100 {
		t.Errorf("GetLatestHeight: got %d want 100", cs.GetLatestHeight().RevisionHeight)
	}
	if cs.ClientType() != ClientType {
		t.Errorf("ClientType: got %q want %q", cs.ClientType(), ClientType)
	}
}

func TestClientStateZeroCustomFields(t *testing.T) {
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
