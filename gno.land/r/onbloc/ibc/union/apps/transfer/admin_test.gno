package transfer

import (
	"testing"

	"gno.land/p/nt/testutils/v0"
	"gno.land/p/nt/uassert/v0"
)

// SetHook takes a TransferHook interface and cannot be called via maketx, so
// callers must route through an ephemeral realm. These tests call it without
// crossing so Previous() is the user realm configured by testing.SetRealm.
//
// transferAdminForTest returns the empty address in unit tests because app init
// captures OriginCaller, which is unset at import time.

func transferAdminForTest() address {
	return address("")
}

func TestSetHookAllowedForAdmin(cur realm, t *testing.T) {
	hook = nil
	hookCaller = address("")

	hookAddr := address(testutils.TestAddress("hook-owner"))
	h := &dummyHook{addr: hookAddr}

	testing.SetRealm(testing.NewUserRealm(transferAdminForTest()))
	SetHook(cur, h)

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

	testing.SetRealm(testing.NewUserRealm(transferAdminForTest()))
	SetHook(cur, nil)

	if hook != nil {
		t.Fatal("SetHook(nil) must clear the hook")
	}
	if hookCaller != (address("")) {
		t.Fatal("SetHook(nil) must clear hookCaller")
	}
}

func TestSetHookInvalidAddressIsRejected(cur realm, t *testing.T) {
	hook = nil
	hookCaller = address("")

	testing.SetRealm(testing.NewUserRealm(transferAdminForTest()))

	uassert.AbortsContains(t, cur, "transfer: hook address is invalid", func(_ realm) {
		SetHook(cur, &dummyHook{addr: address("")})
	})

	if hook != nil || hookCaller != (address("")) {
		t.Fatal("rejected SetHook must not mutate state")
	}
}

func TestSetHookDeniedForNonAdmin(cur realm, t *testing.T) {
	hook = nil
	hookCaller = address("")

	testing.SetRealm(testing.NewUserRealm(address("g1notadmin0000000000000000000000000000000")))

	uassert.AbortsContains(t, cur, "AccessManagerUnauthorizedCall", func(cur realm) {
		SetHook(cur, nil)
	})

	if hook != nil || hookCaller != (address("")) {
		t.Fatal("denied SetHook must not mutate state")
	}
}
