// Package ics20zkgmadapter bridges the ICS20 transfer app and ZKGM in both
// directions. This file implements the AtomOne->Gno->Union leg (see
// forwardics20.gno for the Union->Gno->AtomOne leg):
//
//   - ics20.ForwardHandler — invoked by the transfer app when an inbound voucher
//     recv is addressed to this realm; it escrows the minted voucher into ZKGM
//     and sends it onward.
//   - zkgm.SendCallback — invoked when that onward ZKGM leg settles (ack or
//     timeout); it resolves the original packet's deferred ack.
//
// All ZKGM-specific detail (memo schema, TokenOrderV2 encoding, the escrow/send
// call) lives here, so the transfer app itself imports no ZKGM. The dependency
// direction is ics20zkgmadapter -> {ics20, zkgm}, never the reverse.
package ics20zkgmadapter

import (
	"strconv"

	"gno.land/p/nt/bptree/v0"
	unionTypes "gno.land/p/onbloc/ibc/union/types"
	ics20 "gno.land/r/aib/ibc/apps/transfer"
	"gno.land/r/demo/defi/grc20reg"
	zkgm "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm"
)

// forwardZkgmHandler implements the AtomOne->Gno->Union leg (ics20.ForwardHandler
// + zkgm.SendCallback). See forwardics20.gno's forwardIcs20Handler for the
// mirrored Union->Gno->AtomOne leg.
type forwardZkgmHandler struct{}

var (
	forwardZkgmInstance = &forwardZkgmHandler{}

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
	// must be deployed by the transfer forward admin).
	ics20.RegisterForwardHandler(cross(cur), forwardZkgmInstance)
}

// Prepare validates the forward memo before the transfer app takes custody.
// A non-nil error rejects the recv (error ack / refund) with nothing minted;
// the parse error carries the specific reason.
// Implements ics20.ForwardHandler.
func (h *forwardZkgmHandler) Prepare(cur realm, req ics20.Request) error {
	_, err := parseZkgmMemo(req.Memo)
	return err
}

// Execute escrows the voucher (already minted to this realm by the transfer app)
// into ZKGM and sends it onward, recording the corrID so OnZkgmSendResult can
// later resolve the deferred ack. It panics on any failure so the whole recv
// reverts (mint included) rather than acking over stranded funds.
// Implements ics20.ForwardHandler.
func (h *forwardZkgmHandler) Execute(cur realm, req ics20.Request) {
	fwd, err := parseZkgmMemo(req.Memo)
	if err != nil {
		// Prepare already validated the memo; reaching here means the recv path
		// is inconsistent, so revert.
		panic("ics20zkgmadapter: invalid forward memo at execute: " + err.Error())
	}

	token := grc20reg.Get(req.BaseTokenKey)
	if token == nil {
		panic("ics20zkgmadapter: voucher token not found in grc20reg: " + req.BaseTokenKey)
	}
	// ZKGM's escrow pulls via TransferFrom, so approve it to spend the voucher
	// the transfer app minted to this realm.
	teller := token.RealmTeller(0, cur)
	if err := teller.Approve(0, cur, zkgm.ProxyAddress(), req.Amount); err != nil {
		panic("ics20zkgmadapter: approve error: " + err.Error())
	}

	instruction := buildTokenOrder(cur.Address().String(), req.BaseTokenKey, req.Amount, fwd)
	corrID := forwardCorrID(req.SourceClient, req.Sequence)
	salt := deriveForwardSalt(req.SourceClient, req.Sequence)
	timeout := forwardTimeoutTimestamp(fwd.Timeout)

	// zkgm's channel is numeric; PFM's Channel field is a string.
	channel, err := strconv.ParseUint(fwd.Channel, 10, 32)
	if err != nil {
		panic("ics20zkgmadapter: forward memo channel is not numeric: " + err.Error())
	}

	zkgm.SendWithCallback(cross(cur), unionTypes.ChannelId(channel), timeout, salt, instruction, corrID, forwardZkgmInstance)

	sendCorr.Set(corrID, pendingSend{ClientID: req.DestinationClient, Sequence: req.Sequence})
}

// OnZkgmSendResult resolves the original aib packet's deferred ack once the ZKGM
// leg settles. Implements zkgm.SendCallback.
func (h *forwardZkgmHandler) OnZkgmSendResult(cur realm, corrID string, success bool, ack []byte) error {
	v := sendCorr.Get(corrID)
	if v == nil {
		return nil
	}
	p := v.(pendingSend)
	sendCorr.Remove(corrID)
	ics20.CompleteForwardAck(cross(cur), p.ClientID, p.Sequence, success)
	return nil
}
