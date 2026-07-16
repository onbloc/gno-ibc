package ics20zkgm_adapter

import (
	z "gno.land/p/onbloc/ibc/union/zkgm"
	"gno.land/r/aib/ibc/apps/transfer"
)

// IImpl is the impl-facing contract, mirroring transfer.TransferHook and
// z.Zkgmable but with the internal (_ int, rlm realm) convention used
// throughout this codebase (see apps/ucs03_zkgm/types.gno IApp) so the proxy
// can call into a genuinely different-realm impl without cross(cur) and its
// readonly-tainted-return restrictions.
type IImpl interface {
	OnTransferRecv(_ int, rlm realm, sourceClient string, sequence uint64, data transfer.FungibleTokenPacketData, denom transfer.Denom) error
	OnZkgm(_ int, rlm realm, env z.CallEnv) error
	OnIntentZkgm(_ int, rlm realm, env z.IntentCallEnv) error
}

// IStore is the narrowed surface of Store injected into the impl constructor
// (see RegisterImpl in upgrade.gno and NewImpl in v1/impl.gno), mirroring
// apps/ucs03_zkgm/types.gno's IStore.
type IStore interface {
	SetDenomConfig(_ int, rlm realm, baseDenom string, cfg DenomConfig)
	RemoveDenomConfig(_ int, rlm realm, baseDenom string)
	GetDenomConfig(baseDenom string) (DenomConfig, bool)
	HasDenomConfig(baseDenom string) bool
}
