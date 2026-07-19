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
	// ResolveForward is permissionless: anyone (typically a relayer, after
	// observing the outbound ZKGM packet's ack/timeout) can call it once
	// zkgm.GetSendResult reports the packet resolved, to push the confirmed
	// success/failure onto the original AtomOne packet's deferred
	// acknowledgement. See store.go's PendingForward doc comment.
	ResolveForward(_ int, rlm realm, packetHash string) error
}

// IStore is the narrowed surface of Store injected into the impl constructor
// (see RegisterImpl in upgrade.gno and NewImpl in v1/impl.gno), mirroring
// apps/ucs03_zkgm/types.gno's IStore.
type IStore interface {
	SetDenomConfig(_ int, rlm realm, baseDenom string, cfg DenomConfig)
	RemoveDenomConfig(_ int, rlm realm, baseDenom string)
	GetDenomConfig(baseDenom string) (DenomConfig, bool)
	HasDenomConfig(baseDenom string) bool

	SetPendingForward(_ int, rlm realm, packetHash string, info PendingForward)
	RemovePendingForward(_ int, rlm realm, packetHash string)
	GetPendingForward(packetHash string) (PendingForward, bool)
}

// TransferAckResolver is the seam ResolveForward calls once a ZKGM-sent
// forward packet's result (ack success/failure or timeout) is known, to
// resolve the original ICS20 packet's deferred acknowledgement. This stands
// in for apps/transfer's not-yet-shipped async hook API — see
// async-ack-design-ko.md; production wiring plugs in the real
// transfer.WriteHookAck once that lands. sourceClient/sequence identify the
// original AtomOne packet the same way they identify it to OnTransferRecv.
type TransferAckResolver interface {
	WriteHookAck(cur realm, sourceClient string, sequence uint64, success bool) error
}
