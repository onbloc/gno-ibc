package ics20zkgm_adapter

import (
	z "gno.land/p/onbloc/ibc/union/zkgm"
	"gno.land/r/aib/ibc/apps/transfer"
)

// Adapter is the proxy's receiver surface: the stable identity that
// transfer.SetHook and zkgm.RegisterReceiver see. It never carries business
// logic itself; every method delegates to the installed impl (see
// upgrade.gno). See README.md for the forward/reverse call flow.
type Adapter struct{}

var (
	_ transfer.TransferHook = (*Adapter)(nil)
	_ z.Zkgmable            = (*Adapter)(nil)
)

// Address implements transfer.TransferHook. It returns the proxy's own
// address, which stays stable across impl upgrades.
func (a *Adapter) Address() address {
	return proxyAddress
}

// OnTransferRecv implements transfer.TransferHook. Forward direction:
// AtomOne -> EVM. Fires after an ICS20 mint (see apps/transfer/app.gno).
func (a *Adapter) OnTransferRecv(cur realm, sourceClient string, sequence uint64, data transfer.FungibleTokenPacketData, denom transfer.Denom) error {
	return mustGetImpl().OnTransferRecv(0, cur, sourceClient, sequence, data, denom)
}

// OnZkgm implements z.Zkgmable. Reverse direction: EVM -> AtomOne. Fires on a
// ZKGM OP_CALL batch child addressed to this realm.
func (a *Adapter) OnZkgm(cur realm, env z.CallEnv) error {
	return mustGetImpl().OnZkgm(0, cur, env)
}

// OnIntentZkgm implements z.Zkgmable.
func (a *Adapter) OnIntentZkgm(cur realm, env z.IntentCallEnv) error {
	return mustGetImpl().OnIntentZkgm(0, cur, env)
}
