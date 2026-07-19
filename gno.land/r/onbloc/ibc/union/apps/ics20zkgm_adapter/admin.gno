package ics20zkgm_adapter

import (
	"gno.land/p/nt/ufmt/v0"
	z "gno.land/p/onbloc/ibc/union/zkgm"
	"gno.land/r/onbloc/ibc/union/access"
)

// requiredMetadataDecimals: apps/transfer always mints vouchers at 0
// decimals, so cfg.Metadata must declare the same. Checked at registration
// instead of leaving it to fail on someone else's first forward.
const requiredMetadataDecimals = 0

// RegisterDenom registers (or replaces) the forward-path (AtomOne -> EVM)
// config for an ICS20 base denom. See DenomConfig in store.gno. Admin-only.
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

	meta, err := z.DecodeTokenMetadata(cfg.Metadata)
	if err != nil {
		panic("ics20zkgm_adapter: invalid metadata: " + err.Error())
	}
	if decimals := z.DecodeTokenInitializerFromMetadata(meta).Decimals; decimals != requiredMetadataDecimals {
		panic(ufmt.Sprintf("ics20zkgm_adapter: metadata decimals must be %d, got %d", requiredMetadataDecimals, decimals))
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

// transferAckResolver is the installed TransferAckResolver (see types.gno).
var transferAckResolver TransferAckResolver

// SetTransferAckResolver installs the resolver ResolveForward calls to settle
// the original ICS20 packet's deferred ack. Admin-only.
func SetTransferAckResolver(cur realm, r TransferAckResolver) {
	access.AssertCanCall(0, cur, SelectorSetTransferAckResolver)

	transferAckResolver = r
}

// MustGetTransferAckResolver panics until SetTransferAckResolver is called.
func MustGetTransferAckResolver() TransferAckResolver {
	if transferAckResolver == nil {
		panic("ics20zkgm_adapter: transfer ack resolver not installed")
	}

	return transferAckResolver
}
