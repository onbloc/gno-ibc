package ucs03_zkgm

import (
	types "gno.land/p/onbloc/ibc/union/types"

	zkgm "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm"
)

// handleSendCallback detects a packet sent via zkgm.SendWithCallback resolving
// on ack/timeout and notifies the registered caller, mirroring
// handleForwardChild's in-flight lookup/pop. Unlike a receiver dispatched from
// executeCall, this packet's own ack is already fixed by the counterparty (or
// by the timeout), so a failure here is not converted into an ack — it panics
// like the rest of this file's decode/lookup errors, which reverts the whole
// ack/timeout tx and lets the relayer resubmit once the underlying issue is
// fixed, rather than silently dropping the notification.
func (v *ucs03ZkgmV1) handleSendCallback(_ int, rlm realm, packet types.Packet, success bool, ack []byte) bool {
	hash := types.MustCommit(types.CommitPacket(packet)).String()

	callerPkgPath, corrID, ok := v.store.GetPendingSendCorr(hash)
	if !ok {
		return false
	}

	v.store.RemovePendingSendCorr(0, rlm, hash)

	cb, ok := v.store.GetSendCallback(callerPkgPath)
	if !ok {
		zkgm.EmitSendResultDelivered(0, rlm, callerPkgPath, corrID, false)
		return true
	}

	if err := cb.OnZkgmSendResult(cross(rlm), corrID, success, ack); err != nil {
		panic(err.Error())
	}

	zkgm.EmitSendResultDelivered(0, rlm, callerPkgPath, corrID, success)

	return true
}
