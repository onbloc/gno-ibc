package ics20zkgm_adapter

import (
	z "gno.land/p/onbloc/ibc/union/zkgm"
	adapter "gno.land/r/onbloc/ibc/union/apps/ics20zkgm_adapter"
)

// Impl is the v1 business logic behind the ics20zkgm_adapter proxy. See
// ../README.md for the forward/reverse call flow this is meant to implement.
type Impl struct {
	store adapter.IStore
}

var _ adapter.IImpl = &Impl{}

func NewImpl(store adapter.IStore) *Impl {
	return &Impl{store: store}
}

// OnTransferRecv implements adapter.IImpl. Forward direction: AtomOne -> EVM.
// See forward.gno for the implementation.
//
// Always build the outbound TokenOrderV2 with Kind = TOKEN_ORDER_KIND_INITIALIZE,
// never ESCROW, and do not track "already initialized" state per denom. Verified
// against the actual EVM target contract (/Users/aron/git/union-voyager,
// evm/contracts/apps/ucs/03-zkgm/TokenOrder.sol:271-282, _deployWrappedTokenV2):
// deployment is guarded by `if (!ZkgmLib.isDeployed(wrappedToken))`, so resending
// INITIALIZE for an already-deployed wrapped token just skips the CREATE3 deploy
// and falls through to minting — fully idempotent. ESCROW is the unsafe choice
// here: if the wrapped token isn't deployed yet, canDeploy is false and it
// reverts with ErrCannotDeploy. So INITIALIZE is strictly safer with no
// downside other than a bit of extra gas (metadata decode/verify), and it
// removes the need for any ack-based "was this confirmed on EVM" bookkeeping.

// OnZkgm implements adapter.IImpl. Reverse direction: EVM -> AtomOne.
func (i *Impl) OnZkgm(_ int, rlm realm, env z.CallEnv) error {
	panic("ics20zkgm_adapter/v1: OnZkgm not implemented yet")
}

// OnIntentZkgm implements adapter.IImpl.
func (i *Impl) OnIntentZkgm(_ int, rlm realm, env z.IntentCallEnv) error {
	panic("ics20zkgm_adapter/v1: OnIntentZkgm not implemented yet")
}
