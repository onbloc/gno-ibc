package ics20zkgm_adapter

import "gno.land/r/onbloc/ibc/union/access"

// RegisterDenom registers (or replaces) the forward-path (AtomOne -> EVM)
// config for an ICS20 base denom. See DenomConfig in store.gno for what each
// field means and how it must be computed off-chain. Admin-only.
func RegisterDenom(cur realm, baseDenom string, cfg DenomConfig) {
	access.AssertCanCall(0, cur, SelectorRegisterDenom)

	if baseDenom == "" {
		panic("ics20zkgm_adapter: base denom cannot be empty")
	}
	if len(cfg.QuoteToken) == 0 {
		panic("ics20zkgm_adapter: quote token cannot be empty")
	}
	if len(cfg.Metadata) == 0 {
		panic("ics20zkgm_adapter: metadata cannot be empty")
	}

	store.SetDenomConfig(0, cur, baseDenom, cfg)
	emitAdapterDenomRegisteredEvent(cur.Previous().Address(), baseDenom, uint32(cfg.ZkgmChannelId))
}

// UnregisterDenom clears the forward-path config for an ICS20 base denom.
// Admin-only.
func UnregisterDenom(cur realm, baseDenom string) {
	access.AssertCanCall(0, cur, SelectorUnregisterDenom)

	store.RemoveDenomConfig(0, cur, baseDenom)
	emitAdapterDenomUnregisteredEvent(cur.Previous().Address(), baseDenom)
}

// GetDenomConfig is the public read-only lookup for a base denom's
// forward-path config.
func GetDenomConfig(baseDenom string) (DenomConfig, bool) {
	return store.GetDenomConfig(baseDenom)
}
