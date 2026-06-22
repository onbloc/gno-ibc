package core

import (
	"testing"

	"gno.land/p/nt/uassert/v0"
	"gno.land/p/onbloc/ibc/union/types"
)

func TestConnectionOpenInitPanicsWhenCallerIsNotAdmin(cur realm, t *testing.T) {
	resetStore(cur)
	cleanup := setNonAdminForTest(cur)
	defer cleanup()

	uassert.AbortsContains(t, cur, "unauthorized", func(cur realm) {
		ConnectionOpenInit(cur, types.NewMsgConnectionOpenInit(types.ClientId(1), types.ClientId(99)))
	})
}

func TestConnectionOpenTryPanicsWhenCallerIsNotAdmin(cur realm, t *testing.T) {
	resetStore(cur)
	cleanup := setNonAdminForTest(cur)
	defer cleanup()

	uassert.AbortsContains(t, cur, "unauthorized", func(cur realm) {
		ConnectionOpenTry(cur, types.NewMsgConnectionOpenTry(
			types.ClientId(1),
			types.ClientId(99),
			types.ConnectionId(77),
			nil,
			10,
		))
	})
}

func TestConnectionOpenAckPanicsWhenCallerIsNotAdmin(cur realm, t *testing.T) {
	resetStore(cur)
	cleanup := setNonAdminForTest(cur)
	defer cleanup()

	uassert.AbortsContains(t, cur, "unauthorized", func(cur realm) {
		ConnectionOpenAck(cur, types.NewMsgConnectionOpenAck(
			types.ConnectionId(1),
			types.ConnectionId(77),
			nil,
			10,
		))
	})
}

func TestConnectionOpenConfirmPanicsWhenCallerIsNotAdmin(cur realm, t *testing.T) {
	resetStore(cur)
	cleanup := setNonAdminForTest(cur)
	defer cleanup()

	uassert.AbortsContains(t, cur, "unauthorized", func(cur realm) {
		ConnectionOpenConfirm(cur, types.NewMsgConnectionOpenConfirm(types.ConnectionId(1), nil, 10))
	})
}
