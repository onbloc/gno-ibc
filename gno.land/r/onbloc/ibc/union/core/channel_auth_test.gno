package core

import (
	"testing"

	"gno.land/p/nt/uassert/v0"
	"gno.land/p/onbloc/access/manager"
	"gno.land/p/onbloc/ibc/union/types"
	"gno.land/r/onbloc/ibc/union/access"
)

const accessManagerUnauthorizedCallError = access.ErrAccessManagerUnauthorizedCall

func denySelectorForTest(cur realm, selector manager.Selector) manager.RoleId {
	previousRole := access.GetFunctionRole(cur.PkgPath(), selector)
	if previousRole == manager.PublicRole {
		panic("test selector must not be public")
	}
	return previousRole
}

func restoreSelectorForTest(cur realm, selector manager.Selector, role manager.RoleId) {
}

func TestChannelOpenInitPanicsWhenCallerIsNotAdmin(cur realm, t *testing.T) {
	resetStore(cur)
	previousRole := denySelectorForTest(cur, SelectorChannelOpenInit)

	uassert.AbortsContains(t, cur, accessManagerUnauthorizedCallError, func(cur realm) {
		ChannelOpenInit(cross(cur), types.NewMsgChannelOpenInit(nil, nil, 1, "ics20-1", "g1msgrelayer"))
	})
	restoreSelectorForTest(cur, SelectorChannelOpenInit, previousRole)
}

func TestChannelOpenTryPanicsWhenCallerIsNotAdmin(cur realm, t *testing.T) {
	resetStore(cur)
	previousRole := denySelectorForTest(cur, SelectorChannelOpenTry)

	uassert.AbortsContains(t, cur, accessManagerUnauthorizedCallError, func(cur realm) {
		ChannelOpenTry(cross(cur), types.MsgChannelOpenTry{})
	})
	restoreSelectorForTest(cur, SelectorChannelOpenTry, previousRole)
}

func TestForceChannelOpenTryPanicsWhenCallerIsNotAdmin(cur realm, t *testing.T) {
	resetStore(cur)
	previousRole := denySelectorForTest(cur, SelectorForceChannelTry)

	uassert.AbortsContains(t, cur, accessManagerUnauthorizedCallError, func(cur realm) {
		ForceChannelOpenTry(cross(cur), types.MsgChannelOpenTry{})
	})
	restoreSelectorForTest(cur, SelectorForceChannelTry, previousRole)
}

func TestChannelOpenAckPanicsWhenCallerIsNotAdmin(cur realm, t *testing.T) {
	resetStore(cur)
	previousRole := denySelectorForTest(cur, SelectorChannelOpenAck)

	uassert.AbortsContains(t, cur, accessManagerUnauthorizedCallError, func(cur realm) {
		ChannelOpenAck(cross(cur), types.MsgChannelOpenAck{})
	})
	restoreSelectorForTest(cur, SelectorChannelOpenAck, previousRole)
}

func TestForceChannelOpenAckPanicsWhenCallerIsNotAdmin(cur realm, t *testing.T) {
	resetStore(cur)
	previousRole := denySelectorForTest(cur, SelectorForceChannelAck)

	uassert.AbortsContains(t, cur, accessManagerUnauthorizedCallError, func(cur realm) {
		ForceChannelOpenAck(cross(cur), types.MsgChannelOpenAck{})
	})
	restoreSelectorForTest(cur, SelectorForceChannelAck, previousRole)
}

func TestChannelOpenConfirmPanicsWhenCallerIsNotAdmin(cur realm, t *testing.T) {
	resetStore(cur)
	previousRole := denySelectorForTest(cur, SelectorChannelOpenConfirm)

	uassert.AbortsContains(t, cur, accessManagerUnauthorizedCallError, func(cur realm) {
		ChannelOpenConfirm(cross(cur), types.MsgChannelOpenConfirm{})
	})
	restoreSelectorForTest(cur, SelectorChannelOpenConfirm, previousRole)
}

func TestForceChannelOpenConfirmPanicsWhenCallerIsNotAdmin(cur realm, t *testing.T) {
	resetStore(cur)
	previousRole := denySelectorForTest(cur, SelectorForceChannelConfirm)

	uassert.AbortsContains(t, cur, accessManagerUnauthorizedCallError, func(cur realm) {
		ForceChannelOpenConfirm(cross(cur), types.MsgChannelOpenConfirm{})
	})
	restoreSelectorForTest(cur, SelectorForceChannelConfirm, previousRole)
}

func TestChannelCloseInitPanicsWhenCallerIsNotAdmin(cur realm, t *testing.T) {
	resetStore(cur)
	previousRole := denySelectorForTest(cur, SelectorChannelCloseInit)

	uassert.AbortsContains(t, cur, accessManagerUnauthorizedCallError, func(cur realm) {
		ChannelCloseInit(cross(cur), types.MsgChannelCloseInit{})
	})
	restoreSelectorForTest(cur, SelectorChannelCloseInit, previousRole)
}

func TestChannelCloseConfirmPanicsWhenCallerIsNotAdmin(cur realm, t *testing.T) {
	resetStore(cur)
	previousRole := denySelectorForTest(cur, SelectorChannelCloseConfirm)

	uassert.AbortsContains(t, cur, accessManagerUnauthorizedCallError, func(cur realm) {
		ChannelCloseConfirm(cross(cur), types.MsgChannelCloseConfirm{})
	})
	restoreSelectorForTest(cur, SelectorChannelCloseConfirm, previousRole)
}
