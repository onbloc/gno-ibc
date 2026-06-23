package core

import (
	"testing"

	"gno.land/p/nt/uassert/v0"
	"gno.land/p/onbloc/ibc/union/types"
)

func TestConnectionOpenInitPanicsWhenCallerIsNotAdmin(cur realm, t *testing.T) {
	resetStore(cur)
	previousRole := denySelectorForTest(cur, SelectorConnectionOpenInit)

	uassert.AbortsContains(t, cur, accessManagerUnauthorizedCallError, func(cur realm) {
		ConnectionOpenInit(cross(cur), types.NewMsgConnectionOpenInit(types.ClientId(1), types.ClientId(99)))
	})
	restoreSelectorForTest(cur, SelectorConnectionOpenInit, previousRole)
}

func TestConnectionOpenTryPanicsWhenCallerIsNotAdmin(cur realm, t *testing.T) {
	resetStore(cur)
	previousRole := denySelectorForTest(cur, SelectorConnectionOpenTry)

	uassert.AbortsContains(t, cur, accessManagerUnauthorizedCallError, func(cur realm) {
		ConnectionOpenTry(cross(cur), types.NewMsgConnectionOpenTry(
			types.ClientId(1),
			types.ClientId(99),
			types.ConnectionId(77),
			nil,
			10,
		))
	})
	restoreSelectorForTest(cur, SelectorConnectionOpenTry, previousRole)
}

func TestConnectionOpenAckPanicsWhenCallerIsNotAdmin(cur realm, t *testing.T) {
	resetStore(cur)
	previousRole := denySelectorForTest(cur, SelectorConnectionOpenAck)

	uassert.AbortsContains(t, cur, accessManagerUnauthorizedCallError, func(cur realm) {
		ConnectionOpenAck(cross(cur), types.NewMsgConnectionOpenAck(
			types.ConnectionId(1),
			types.ConnectionId(77),
			nil,
			10,
		))
	})
	restoreSelectorForTest(cur, SelectorConnectionOpenAck, previousRole)
}

func TestConnectionOpenConfirmPanicsWhenCallerIsNotAdmin(cur realm, t *testing.T) {
	resetStore(cur)
	previousRole := denySelectorForTest(cur, SelectorConnectionOpenConfirm)

	uassert.AbortsContains(t, cur, accessManagerUnauthorizedCallError, func(cur realm) {
		ConnectionOpenConfirm(cross(cur), types.NewMsgConnectionOpenConfirm(types.ConnectionId(1), nil, 10))
	})
	restoreSelectorForTest(cur, SelectorConnectionOpenConfirm, previousRole)
}
