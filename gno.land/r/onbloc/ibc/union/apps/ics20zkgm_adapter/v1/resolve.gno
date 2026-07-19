package ics20zkgm_adapter

import (
	adapter "gno.land/r/onbloc/ibc/union/apps/ics20zkgm_adapter"
	zkgm "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm"
)

// ResolveForward implements adapter.IImpl. See adapter.gno's ResolveForward
// (the public, permissionless entry point) and store.go's PendingForward doc
// comment for the full picture.
func (i *Impl) ResolveForward(_ int, rlm realm, packetHash string) error {
	info, found := i.store.GetPendingForward(packetHash)
	if !found {
		return makeError(errPendingForwardNotFound)
	}

	successful, _, resolved, found := zkgm.GetSendResult(packetHash)
	if !found {
		return makeError(errPendingForwardNotFound)
	}
	if !resolved {
		return makeError(errForwardNotYetResolved)
	}

	resolver := adapter.MustGetTransferAckResolver()
	if err := resolver.WriteHookAck(cross(rlm), info.SourceClient, info.Sequence, successful); err != nil {
		return makeError(errWriteHookAckFailed, err.Error())
	}

	i.store.RemovePendingForward(0, rlm, packetHash)
	zkgm.ClearSendResult(cross(rlm), packetHash)

	return nil
}
