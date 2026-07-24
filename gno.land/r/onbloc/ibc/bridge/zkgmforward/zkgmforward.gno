// Package zkgmforward is the ZKGM adapter for the ICS20 transfer app's forward
// hook. It implements:
//
//   - transfer.ForwardHandler — invoked by the transfer app when an inbound voucher
//     recv is addressed to this realm; it escrows the minted voucher into ZKGM
//     and sends it onward.
//   - zkgm.SendCallback — invoked when that onward ZKGM leg settles (ack or
//     timeout); it resolves the original packet's deferred ack.
//
// All ZKGM-specific detail (memo schema, TokenOrderV2 encoding, the escrow/send
// call) lives here, so the transfer app itself imports no ZKGM. The dependency
// direction is zkgmforward -> {transfer, zkgm}, never the reverse.
package zkgmforward

import (
	"gno.land/p/nt/bptree/v0"
	unionTypes "gno.land/p/onbloc/ibc/union/types"
	"gno.land/r/aib/ibc/apps/transfer"
	"gno.land/r/demo/defi/grc20reg"
	zkgm "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm"
)

type handler struct{}

var (
	instance = &handler{}

	// sendCorr maps a ZKGM send corrID -> the original aib packet whose deferred
	// ack it must resolve. corrID is unique per (sourceClient, sequence).
	sendCorr *bptree.BPTree
)

// pendingSend records the aib packet a forwarded ZKGM send resolves.
type pendingSend struct {
	ClientID string // aib destinationClient — the local client the ack is written on
	Sequence uint64
}

func init(cur realm) {
	sendCorr = bptree.NewBPTree32()
	// Register as the transfer app's forward handler (admin-gated — this realm
	// must be deployed by the transfer forward admin) and as ZKGM's send callback.
	transfer.RegisterForwardHandler(cross(cur), instance)
	zkgm.RegisterSendCallback(cross(cur), instance)
}

// Prepare validates the forward memo before the transfer app takes custody.
// A non-nil error rejects the recv (error ack / refund) with nothing minted;
// the parse error carries the specific reason.
// Implements transfer.ForwardHandler.
func (h *handler) Prepare(cur realm, req transfer.Request) error {
	_, err := parseForwardMemo(req.Memo)
	return err
}

// Execute escrows the voucher (already minted to this realm by the transfer app)
// into ZKGM and sends it onward, recording the corrID so OnZkgmSendResult can
// later resolve the deferred ack. It panics on any failure so the whole recv
// reverts (mint included) rather than acking over stranded funds.
// Implements transfer.ForwardHandler.
func (h *handler) Execute(cur realm, req transfer.Request) {
	fwd, err := parseForwardMemo(req.Memo)
	if err != nil {
		// Prepare already validated the memo; reaching here means the recv path
		// is inconsistent, so revert.
		panic("zkgmforward: invalid forward memo at execute: " + err.Error())
	}

	token := grc20reg.Get(req.BaseTokenKey)
	if token == nil {
		panic("zkgmforward: voucher token not found in grc20reg: " + req.BaseTokenKey)
	}
	// ZKGM's escrow pulls via TransferFrom, so approve it to spend the voucher
	// the transfer app minted to this realm.
	teller := token.RealmTeller(0, cur)
	if err := teller.Approve(0, cur, zkgm.ProxyAddress(), req.Amount); err != nil {
		panic("zkgmforward: approve error: " + err.Error())
	}

	instruction := buildTokenOrder(cur.Address().String(), req.BaseTokenKey, req.Amount, fwd)
	corrID := forwardCorrID(req.SourceClient, req.Sequence)
	salt := deriveForwardSalt(req.SourceClient, req.Sequence)
	timeout := forwardTimeoutTimestamp(fwd.TimeoutTimestamp)

	zkgm.SendWithCallback(cross(cur), unionTypes.ChannelId(fwd.Channel), timeout, salt, instruction, corrID)

	sendCorr.Set(corrID, pendingSend{ClientID: req.DestinationClient, Sequence: req.Sequence})
}

// OnZkgmSendResult resolves the original aib packet's deferred ack once the ZKGM
// leg settles. Implements zkgm.SendCallback.
func (h *handler) OnZkgmSendResult(cur realm, corrID string, success bool, ack []byte) error {
	v := sendCorr.Get(corrID)
	if v == nil {
		return nil
	}
	p := v.(pendingSend)
	sendCorr.Remove(corrID)
	transfer.CompleteForwardAck(cross(cur), p.ClientID, p.Sequence, success)
	return nil
}
