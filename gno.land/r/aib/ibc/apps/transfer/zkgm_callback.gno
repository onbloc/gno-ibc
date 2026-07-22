package transfer

import (
	"gno.land/p/aib/ibc/types"
	"gno.land/r/aib/ibc/core"
	zkgm "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm"
)

// zkgmSendResult implements zkgm's SendCallback so this realm - the same one
// that deferred the ack in forward.gno - can resolve it itself.
type zkgmSendResult struct{}

var sendResultHandler = zkgmSendResult{}

// RegisterZkgmSendCallback registers this realm as ZKGM's notification
// target. Call once; re-registering just overwrites the entry.
func RegisterZkgmSendCallback(cur realm) {
	zkgm.RegisterSendCallback(cross(cur), sendResultHandler)
}

func (zkgmSendResult) OnZkgmSendResult(cur realm, corrID string, success bool, ack []byte) error {
	pending, found := getPendingForward(corrID)
	if !found {
		return nil
	}
	deletePendingForward(corrID)

	var resolved types.Acknowledgement
	if success {
		result := types.NewResultAppAcknowledgement([]byte{byte(1)})
		resolved = types.Acknowledgement{AppAcknowledgements: [][]byte{result.MarshalJSON()}}
	} else {
		inst := getVoucher(pending.VoucherDenom)
		if inst == nil {
			panic("transfer: forward failed but voucher not found for " + pending.VoucherDenom)
		}
		if err := inst.ledger.Burn(cur.Address(), pending.Amount); err != nil {
			panic("transfer: forward failed and burn failed: " + err.Error())
		}
		resolved = types.Acknowledgement{AppAcknowledgements: [][]byte{types.UniversalErrorAcknowledgement()}}
	}

	core.WriteAcknowledgement(cross(cur), pending.DestinationClient, pending.Sequence, resolved)

	return nil
}
