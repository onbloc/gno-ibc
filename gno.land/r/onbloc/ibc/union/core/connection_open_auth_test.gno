package core

import (
	"testing"

	"gno.land/p/nt/uassert/v0"
	"gno.land/p/onbloc/ibc/union/types"
)

func TestForceConnectionOpenAckPanicsWhenCallerIsNotAdmin(cur realm, t *testing.T) {
	resetStore(cur)
	cleanup := setNonAdminForTest(cur)
	defer cleanup()

	uassert.AbortsContains(t, cur, "unauthorized", func(cur realm) {
		ForceConnectionOpenAck(cur, types.NewMsgConnectionOpenAck(
			types.ConnectionId(1),
			types.ConnectionId(77),
			nil,
			10,
		))
	})
}

func TestForceConnectionOpenConfirmPanicsWhenCallerIsNotAdmin(cur realm, t *testing.T) {
	resetStore(cur)
	cleanup := setNonAdminForTest(cur)
	defer cleanup()

	uassert.AbortsContains(t, cur, "unauthorized", func(cur realm) {
		ForceConnectionOpenConfirm(cur, types.NewMsgConnectionOpenConfirm(types.ConnectionId(1), nil, 10))
	})
}
