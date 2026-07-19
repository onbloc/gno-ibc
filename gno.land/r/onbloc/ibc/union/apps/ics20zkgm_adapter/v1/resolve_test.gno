package ics20zkgm_adapter

import (
	"testing"

	"gno.land/p/nt/uassert/v0"
	adapter "gno.land/r/onbloc/ibc/union/apps/ics20zkgm_adapter"
)

func TestResolveForwardUnknownPacketHashIsRejected(cur realm, t *testing.T) {
	testStore = newMockStore()
	impl := newTestImpl()

	err := impl.ResolveForward(0, cur, "deadbeef")
	uassert.ErrorContains(t, err, errPendingForwardNotFound)
}

// TestResolveForwardHappyPathReachesZkgmGetSendResult verifies that, once a
// pending forward record exists, ResolveForward gets past the lookup and
// calls zkgm.GetSendResult. There's no registered zkgm impl in this
// unit-test realm, so GetSendResult panics on mustGetImpl() -- proving we
// reached it, the same way OnTransferRecv's happy-path test proves it
// reached zkgm.Send.
func TestResolveForwardHappyPathReachesZkgmGetSendResult(cur realm, t *testing.T) {
	const packetHash = "aabbccdd"

	testStore = newMockStore()
	impl := newTestImpl()
	testStore.SetPendingForward(0, cur, packetHash, adapter.NewPendingForward(fwdSourceClient, 42))

	uassert.AbortsWithMessage(t, cur, "implementation not installed", func(cur realm) {
		impl.ResolveForward(0, cur, packetHash)
	})
}
