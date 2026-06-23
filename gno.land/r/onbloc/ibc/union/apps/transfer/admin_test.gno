package transfer

import (
	"testing"

	"gno.land/p/nt/testutils/v0"
	"gno.land/p/nt/uassert/v0"
	"gno.land/r/onbloc/ibc/union/access"
)

// SetHook takes a TransferHook interface and cannot be called via maketx, so
// callers must route through an ephemeral realm. These tests cross through the
// test realm so Previous() is the user realm configured by testing.SetRealm.
func TestSetHookAllowedForAdmin(cur realm, t *testing.T) {
	hook = nil
	hookCaller = address("")

	hookAddr := address(testutils.TestAddress("hook-owner"))
	h := &dummyHook{addr: hookAddr}

	testing.SetRealm(testing.NewUserRealm(access.DefaultAdminAddress))
	SetHook(cross(cur), h)

	if hook != h {
		t.Fatal("SetHook must register the provided hook")
	}
	if hookCaller != hookAddr {
		t.Fatal("SetHook must derive hookCaller from h.Address()")
	}
}

func TestSetHookClearsWithNil(cur realm, t *testing.T) {
	hook = &dummyHook{addr: address("g1existing000000000000000000000000000000")}
	hookCaller = address("g1existing000000000000000000000000000000")

	testing.SetRealm(testing.NewUserRealm(access.DefaultAdminAddress))
	SetHook(cross(cur), nil)

	if hook != nil {
		t.Fatal("SetHook(nil) must clear the hook")
	}
	if hookCaller != address("") {
		t.Fatal("SetHook(nil) must clear hookCaller")
	}
}

func TestSetHookInvalidAddressIsRejected(cur realm, t *testing.T) {
	hook = nil
	hookCaller = address("")

	testing.SetRealm(testing.NewUserRealm(access.DefaultAdminAddress))

	uassert.AbortsContains(t, cur, "transfer: hook address is invalid", func() {
		SetHook(cross(cur), &dummyHook{addr: address("")})
	})

	if hook != nil || hookCaller != address("") {
		t.Fatal("rejected SetHook must not mutate state")
	}
}

func TestSetHookDeniedForNonAdmin(cur realm, t *testing.T) {
	hook = nil
	hookCaller = address("")

	testing.SetRealm(testing.NewUserRealm(address("g1notadmin0000000000000000000000000000000")))

	uassert.AbortsContains(t, cur, "access manager unauthorized call", func(cur realm) {
		SetHook(cross(cur), nil)
	})

	if hook != nil || hookCaller != address("") {
		t.Fatal("denied SetHook must not mutate state")
	}
}
