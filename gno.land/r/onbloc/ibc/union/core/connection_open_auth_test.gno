package core

import (
	"testing"

	"gno.land/p/nt/uassert/v0"
	"gno.land/p/onbloc/ibc/union/types"
)

func TestForceConnectionOpenAckPanicsWhenCallerIsNotAdmin(cur realm, t *testing.T) {
	resetStore(cur)
	previousRole := denySelectorForTest(cur, SelectorForceConnectionAck)

	uassert.AbortsContains(t, cur, "unauthorized", func(cur realm) {
		ForceConnectionOpenAck(cross(cur), types.NewMsgConnectionOpenAck(
			types.ConnectionId(1),
			types.ConnectionId(77),
			nil,
			10,
		))
	})
	restoreSelectorForTest(cur, SelectorForceConnectionAck, previousRole)
}

func TestForceConnectionOpenConfirmPanicsWhenCallerIsNotAdmin(cur realm, t *testing.T) {
	resetStore(cur)
	previousRole := denySelectorForTest(cur, SelectorForceConnectionConfirm)

	uassert.AbortsContains(t, cur, "unauthorized", func(cur realm) {
		ForceConnectionOpenConfirm(cross(cur), types.NewMsgConnectionOpenConfirm(types.ConnectionId(1), nil, 10))
	})
	restoreSelectorForTest(cur, SelectorForceConnectionConfirm, previousRole)
}
