package core

import (
	"testing"

	"gno.land/p/nt/uassert/v0"
	"gno.land/p/onbloc/ibc/union/types"
)

// The Force* proof-bypass behavior is covered by the v1 implementation tests
// (core/v1/connection_test.gno). The proxy only keeps the admin gate.
func TestForceConnectionOpenTryPanicsWhenCallerIsNotAdmin(cur realm, t *testing.T) {
	resetStore(cur)
	previousRole := denySelectorForTest(cur, SelectorForceConnectionTry)
	defer restoreSelectorForTest(cur, SelectorForceConnectionTry, previousRole)

	uassert.AbortsContains(t, cur, "unauthorized", func(cur realm) {
		ForceConnectionOpenTry(cross(cur), types.NewMsgConnectionOpenTry(
			types.ClientId(1),
			types.ClientId(99),
			types.ConnectionId(77),
			nil,
			10,
		))
	})
}
