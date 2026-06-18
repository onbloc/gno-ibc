package core

import (
	"testing"

	"gno.land/p/nt/testutils/v0"
	"gno.land/p/nt/uassert/v0"
	"gno.land/p/onbloc/ibc/union/types"
)

func setNonAdminForTest() func() {
	oldAdmin := admin
	admin = testutils.TestAddress("authorized-admin")
	return func() {
		admin = oldAdmin
	}
}

func TestChannelOpenInitPanicsWhenCallerIsNotAdmin(cur realm, t *testing.T) {
	resetStore()
	cleanup := setNonAdminForTest()
	defer cleanup()

	uassert.AbortsContains(t, cur, "unauthorized", func(cur realm) {
		ChannelOpenInit(cur, types.NewMsgChannelOpenInit(nil, nil, 1, "ics20-1", "g1msgrelayer"))
	})
}

func TestChannelOpenTryPanicsWhenCallerIsNotAdmin(cur realm, t *testing.T) {
	resetStore()
	cleanup := setNonAdminForTest()
	defer cleanup()

	uassert.AbortsContains(t, cur, "unauthorized", func(cur realm) {
		ChannelOpenTry(cur, types.MsgChannelOpenTry{})
	})
}

func TestForceChannelOpenTryPanicsWhenCallerIsNotAdmin(cur realm, t *testing.T) {
	resetStore()
	cleanup := setNonAdminForTest()
	defer cleanup()

	uassert.AbortsContains(t, cur, "unauthorized", func(cur realm) {
		ForceChannelOpenTry(cur, types.MsgChannelOpenTry{})
	})
}

func TestChannelOpenAckPanicsWhenCallerIsNotAdmin(cur realm, t *testing.T) {
	resetStore()
	cleanup := setNonAdminForTest()
	defer cleanup()

	uassert.AbortsContains(t, cur, "unauthorized", func(cur realm) {
		ChannelOpenAck(cur, types.MsgChannelOpenAck{})
	})
}

func TestForceChannelOpenAckPanicsWhenCallerIsNotAdmin(cur realm, t *testing.T) {
	resetStore()
	cleanup := setNonAdminForTest()
	defer cleanup()

	uassert.AbortsContains(t, cur, "unauthorized", func(cur realm) {
		ForceChannelOpenAck(cur, types.MsgChannelOpenAck{})
	})
}

func TestChannelOpenConfirmPanicsWhenCallerIsNotAdmin(cur realm, t *testing.T) {
	resetStore()
	cleanup := setNonAdminForTest()
	defer cleanup()

	uassert.AbortsContains(t, cur, "unauthorized", func(cur realm) {
		ChannelOpenConfirm(cur, types.MsgChannelOpenConfirm{})
	})
}

func TestForceChannelOpenConfirmPanicsWhenCallerIsNotAdmin(cur realm, t *testing.T) {
	resetStore()
	cleanup := setNonAdminForTest()
	defer cleanup()

	uassert.AbortsContains(t, cur, "unauthorized", func(cur realm) {
		ForceChannelOpenConfirm(cur, types.MsgChannelOpenConfirm{})
	})
}

func TestChannelCloseInitPanicsWhenCallerIsNotAdmin(cur realm, t *testing.T) {
	resetStore()
	cleanup := setNonAdminForTest()
	defer cleanup()

	uassert.AbortsContains(t, cur, "unauthorized", func(cur realm) {
		ChannelCloseInit(cur, types.MsgChannelCloseInit{})
	})
}

func TestChannelCloseConfirmPanicsWhenCallerIsNotAdmin(cur realm, t *testing.T) {
	resetStore()
	cleanup := setNonAdminForTest()
	defer cleanup()

	uassert.AbortsContains(t, cur, "unauthorized", func(cur realm) {
		ChannelCloseConfirm(cur, types.MsgChannelCloseConfirm{})
	})
}
