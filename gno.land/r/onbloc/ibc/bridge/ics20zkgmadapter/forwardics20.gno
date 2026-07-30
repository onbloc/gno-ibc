package ics20zkgmadapter

import (
	"time"

	z "gno.land/p/onbloc/ibc/union/zkgm"
	ics20 "gno.land/r/aib/ibc/apps/transfer"
	"gno.land/r/demo/defi/grc20reg"
	zkgm "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm"

	"chain"
)

const (
	// aib core requires timeoutTimestamp <= current block time + 24h; stay
	// safely under that bound rather than exactly at it.
	defaultForwardIcs20Timeout = 23 * time.Hour
	ics20PkgPath               = "gno.land/r/aib/ibc/apps/transfer"
)

// forwardIcs20Handler implements zkgm.TokenForwardHandler for EVM->Union->Gno->
// AtomOne: an ESCROW TokenOrderV2 addressed to this realm settles here, with
// Metadata carrying where to route it onward via ICS20.
type forwardIcs20Handler struct{}

var forwardIcs20Instance = &forwardIcs20Handler{}

// RegisterReverseHandler registers this realm as ZKGM's forward handler for
// this leg. zkgm.RegisterTokenForwardHandler is admin-gated on this realm's
// own address, which cannot hold that permission before it is deployed, so
// this is a separate post-deploy step rather than part of init: whoever
// holds zkgm's register_forward_handler role calls this once, after granting
// that role to this realm's address.
func RegisterReverseHandler(cur realm) {
	zkgm.RegisterTokenForwardHandler(cross(cur), forwardIcs20Instance)
}

// Implements zkgm.TokenForwardHandler.
func (h *forwardIcs20Handler) Prepare(cur realm, req z.TokenForwardRequest, corrID string) error {
	_, err := parseICS20Memo(string(req.Memo))
	return err
}

// Implements zkgm.TokenForwardHandler. Reuses corrID as the aib-side correlation
// too, so OnTransferSendResult can resolve the ZKGM ack directly.
func (h *forwardIcs20Handler) Execute(cur realm, req z.TokenForwardRequest, corrID string) {
	fwd, err := parseICS20Memo(string(req.Memo))
	if err != nil {
		panic("ics20zkgmadapter: invalid memo at execute: " + err.Error())
	}

	token := grc20reg.Get(req.BaseTokenKey)
	if token == nil {
		panic("ics20zkgmadapter: voucher token not found in grc20reg: " + req.BaseTokenKey)
	}
	// TransferWithCallback's escrow pulls via TransferFrom, so approve it
	// (mirrors forwardzkgm.gno's approve of the zkgm proxy).
	teller := token.RealmTeller(0, cur)
	if err := teller.Approve(0, cur, chain.PackageAddress(ics20PkgPath), req.Amount); err != nil {
		panic("ics20zkgmadapter: approve error: " + err.Error())
	}

	ics20.TransferWithCallback(cross(cur), fwd.Core.Channel, fwd.Core.Receiver, req.BaseTokenKey, req.Amount, forwardIcs20TimeoutTimestamp(fwd.Core.Timeout), fwd.Next, corrID, forwardZkgmInstance)
}

// OnTransferSendResult resolves the ZKGM order's deferred ack once the onward
// ICS20 send settles. Implemented on forwardZkgmHandler since it's the same
// singleton already implementing zkgm.SendCallback.
// Implements ics20.SendCallback.
func (h *forwardZkgmHandler) OnTransferSendResult(cur realm, corrID string, success bool, ack []byte) error {
	zkgm.CompleteTokenForwardAck(cross(cur), corrID, success, ack)
	return nil
}

// aib's MsgSendPacket.TimeoutTimestamp is Unix seconds (see aib core's
// SendPacket); fwd.Timeout is UnixNano (see memo.gno's optionalTimeout).
func forwardIcs20TimeoutTimestamp(memoTimeout uint64) uint64 {
	if memoTimeout != 0 {
		return memoTimeout / uint64(time.Second)
	}
	return uint64(time.Now().Add(defaultForwardIcs20Timeout).Unix())
}
