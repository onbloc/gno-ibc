package ics20zkgm_adapter

import (
	"testing"

	"gno.land/p/nt/uassert/v0"
)

// TestTransferAckResolverReachesTransferWriteHookAck verifies that
// TransferAckResolver.WriteHookAck delegates to the real
// transfer.WriteHookAck, not a stub -- no hook is registered in this
// unit-test realm, so the real function's own "not the registered hook"
// auth error proves we reached it, the same way OnTransferRecv's
// happy-path test proves it reached zkgm.Send.
func TestTransferAckResolverReachesTransferWriteHookAck(cur realm, t *testing.T) {
	resolver := NewTransferAckResolver()

	err := resolver.WriteHookAck(cross(cur), "07-tendermint-0", 999, true)
	uassert.ErrorContains(t, err, "not the registered hook")
}
