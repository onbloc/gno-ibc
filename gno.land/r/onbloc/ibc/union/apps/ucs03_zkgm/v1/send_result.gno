package ucs03_zkgm

import (
	types "gno.land/p/onbloc/ibc/union/types"
	zkgm "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm"
)

// send_result.gno lets a realm that calls Send directly (not via Forward)
// later discover the result — ack success, ack failure, or timeout — of the
// packet it sent, instead of sending a second packet to find out (which
// could itself fail to be received — see
// ../../ics20zkgm_adapter/async-ack-design-ko.md).

// sendResultKey derives the send-result store key from a packet's commitment
// hash, mirroring forwardInFlightKey.
func sendResultKey(packet types.Packet) string {
	return types.MustCommit(types.CommitPacket(packet)).String()
}

// GetSendResult implements zkgm.IAppGetter.
func (v *ucs03ZkgmV1) GetSendResult(packetHash string) (successful bool, ack []byte, resolved bool, found bool) {
	return v.store.GetSendResult(packetHash)
}

// emitSendResultResolved records packet's final ack/timeout result and emits
// an event only if it was tracked (sent via Send(), not e.g. a Forward child
// sent via core.SendPacket directly).
func (v *ucs03ZkgmV1) emitSendResultResolved(_ int, rlm realm, packet types.Packet, successful bool, ack []byte) {
	trackerPkgPath, found := v.store.SetSendResultResolved(0, rlm, sendResultKey(packet), successful, ack)
	if !found {
		return
	}

	zkgm.EmitSendResultResolved(0, rlm, sendResultKey(packet), trackerPkgPath, successful)
}

// ClearSendResult implements zkgm.IAppTransfer.
func (v *ucs03ZkgmV1) ClearSendResult(_ int, rlm realm, packetHash string) {
	assertIsRlmCurrent(0, rlm)

	v.store.RemoveSendResult(0, rlm, packetHash, rlm.Previous().PkgPath())
}
