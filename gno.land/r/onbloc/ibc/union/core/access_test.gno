package core

import (
	"testing"

	"gno.land/p/nt/testutils/v0"
	"gno.land/p/nt/uassert/v0"
	manager "gno.land/p/onbloc/access/manager"
	"gno.land/p/onbloc/ibc/union/types"
)

func TestAccessDefaultRoleIsAdmin(cur realm, t *testing.T) {
	resetStore(cur)
	other := testutils.TestAddress("not-admin")

	if !CanCall(0, cur, SelectorRegisterClient, cur.Address()) {
		t.Fatal("admin must be authorized for default-admin selectors")
	}
	if CanCall(0, cur, SelectorRegisterClient, other) {
		t.Fatal("non-admin must not be authorized for default-admin selectors")
	}
}

func TestRelayerRoleSupportsMultipleMembers(cur realm, t *testing.T) {
	resetStore(cur)
	relayerA := testutils.TestAddress("relayer-a")
	relayerB := testutils.TestAddress("relayer-b")
	other := testutils.TestAddress("other")

	GrantRole(0, cur, RelayerRole, relayerA)
	GrantRole(0, cur, RelayerRole, relayerB)

	if !CanCall(0, cur, SelectorPacketRecv, relayerA) {
		t.Fatal("first relayer must be authorized")
	}
	if !CanCall(0, cur, SelectorPacketRecv, relayerB) {
		t.Fatal("second relayer must be authorized")
	}
	if CanCall(0, cur, SelectorPacketRecv, other) {
		t.Fatal("non-relayer must not be authorized")
	}
}

func TestRelayerRoleRevocation(cur realm, t *testing.T) {
	resetStore(cur)
	relayer := testutils.TestAddress("relayer")

	GrantRole(0, cur, RelayerRole, relayer)
	if !CanCall(0, cur, SelectorPacketRecv, relayer) {
		t.Fatal("relayer must be authorized before revocation")
	}

	RevokeRole(0, cur, RelayerRole, relayer)
	if CanCall(0, cur, SelectorPacketRecv, relayer) {
		t.Fatal("relayer must be rejected after revocation")
	}
}

func TestAccessGrantRoleRejectsNonRoleAdmin(cur realm, t *testing.T) {
	resetStore(cur)
	relayer := testutils.TestAddress("relayer")
	admin = testutils.TestAddress("authorized-admin")
	resetAccess(cur, admin)
	testing.SetRealm(testing.NewUserRealm(testutils.TestAddress("not-admin")))

	uassert.AbortsContains(t, cur, "caller not authorized to grant_role", func(cur realm) {
		GrantRole(0, cur, RelayerRole, relayer)
	})
	if HasRole(0, cur, RelayerRole, relayer) {
		t.Fatal("rejected grant must not add the relayer")
	}
}

func TestPublicRoleOpensSelector(cur realm, t *testing.T) {
	resetStore(cur)
	other := testutils.TestAddress("public-caller")

	SetFunctionRole(0, cur, SelectorRegisterClient, manager.PublicRole)

	if !CanCall(0, cur, SelectorRegisterClient, other) {
		t.Fatal("public selector must authorize arbitrary caller")
	}
}

func TestAccessSetFunctionRoleRejectsNonManagerAdmin(cur realm, t *testing.T) {
	resetStore(cur)
	admin = testutils.TestAddress("authorized-admin")
	resetAccess(cur, admin)
	testing.SetRealm(testing.NewUserRealm(testutils.TestAddress("not-admin")))

	uassert.AbortsContains(t, cur, "caller not authorized to set_target_function_role", func(cur realm) {
		SetFunctionRole(0, cur, SelectorRegisterClient, manager.PublicRole)
	})
	if GetFunctionRole(0, cur, SelectorRegisterClient) != manager.AdminRole {
		t.Fatal("rejected role update must not change selector role")
	}
}

func TestRelayerEntrypointRejectsRevokedCaller(cur realm, t *testing.T) {
	resetStore(cur)
	RevokeRole(0, cur, RelayerRole, cur.Address())

	uassert.AbortsContains(t, cur, "caller not authorized to packet_recv", func(cur realm) {
		PacketRecv(cross(cur), types.MsgPacketRecv{})
	})
}
