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
	t.Run("valid", func(t *testing.T) {
		cs := validClientState()
		if err := cs.Validate(); err != nil {
			t.Fatalf("unexpected error: %v", err)
		}
	})

	t.Run("empty_chain_id", func(t *testing.T) {
		cs := validClientState()
		cs.ChainID = "   "
		if err := cs.Validate(); err == nil {
			t.Fatal("expected error for empty chain id")
		}
	})

	t.Run("chain_id_too_long", func(t *testing.T) {
		cs := validClientState()
		cs.ChainID = strings.Repeat("x", MaxChainIDLen+1)
		if err := cs.Validate(); err == nil {
			t.Fatal("expected error for over-long chain id")
		}
	})

	t.Run("zero_trusting_period", func(t *testing.T) {
		cs := validClientState()
		cs.TrustingPeriod = 0
		if err := cs.Validate(); err == nil {
			t.Fatal("expected error for zero trusting period")
		}
	})

	t.Run("zero_unbonding_period", func(t *testing.T) {
		cs := validClientState()
		cs.UnbondingPeriod = 0
		if err := cs.Validate(); err == nil {
			t.Fatal("expected error for zero unbonding period")
		}
	})

	t.Run("zero_max_clock_drift", func(t *testing.T) {
		cs := validClientState()
		cs.MaxClockDrift = 0
		if err := cs.Validate(); err == nil {
			t.Fatal("expected error for zero max clock drift")
		}
	})

	t.Run("zero_latest_height", func(t *testing.T) {
		cs := validClientState()
		cs.LatestHeight = types.NewHeight(0)
		if err := cs.Validate(); err == nil {
			t.Fatal("expected error for zero latest height")
		}
	})

	t.Run("trusting_period_not_less_than_unbonding", func(t *testing.T) {
		cs := validClientState()
		cs.TrustingPeriod = cs.UnbondingPeriod
		if err := cs.Validate(); err == nil {
			t.Fatal("expected error when trusting period >= unbonding period")
		}
	})
}

func TestClientStateIsExpired(t *testing.T) {
	cs := validClientState() // TrustingPeriod = 1000

	if cs.IsExpired(testNow-1000, testNow) {
		t.Error("expected not expired when latestTimestamp + trustingPeriod == now")
	}
	if cs.IsExpired(testNow-999, testNow) {
		t.Error("expected not expired when latestTimestamp + trustingPeriod > now")
	}
	if !cs.IsExpired(testNow-1001, testNow) {
		t.Error("expected expired when latestTimestamp + trustingPeriod < now")
	}
	if !cs.IsExpired(^uint64(0)-999, testNow) {
		t.Error("expected expired when latestTimestamp + trustingPeriod overflows")
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
