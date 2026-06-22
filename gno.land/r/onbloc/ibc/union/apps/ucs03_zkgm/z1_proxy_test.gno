package zkgm

import (
	"testing"

	"gno.land/p/nt/uassert/v0"
	core "gno.land/r/onbloc/ibc/union/core"
)

// z1_proxy_test covers upgrade.gno's swap model. An impl realm registers its
// constructor under its own package path via RegisterImpl; the admin later
// activates a registered path via UpdateImpl, which injects the proxy store and
// builds the active impl. The model rejects non-admin callers and unregistered
// paths.

const (
	testImplPathA = "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/v1"
	testImplPathB = "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/v2"
)

func TestUpdateImplRejectsNonAdmin(cur realm, t *testing.T) {
	resetZkgmForTest(cur)
	implConstructors[testImplPathA] = func(store IStore) IApp { return &dummyImpl{} }

	uassert.AbortsContains(t, cur, "caller not authorized to update_impl", func(cur realm) {
		UpdateImpl(cross(cur), testImplPathA)
	})
	if currentImpl != nil {
		t.Error("rejected UpdateImpl must not install an impl")
	}
}

func TestUpdateImplRejectsUnregisteredPath(cur realm, t *testing.T) {
	resetZkgmForTest(cur)

	// Call with the outer (admin) cur, not the closure's crossing param, so the
	// admin gate passes and the unregistered-path validation is what aborts.
	testing.SetRealm(testing.NewUserRealm(zkgmAdminForTest()))
	uassert.AbortsContains(t, cur, "impl constructor not found", func(_ realm) {
		UpdateImpl(cur, testImplPathA)
	})
}

func TestUpdateImplByAdminInstallsImpl(cur realm, t *testing.T) {
	resetZkgmForTest(cur)
	implConstructors[testImplPathA] = func(store IStore) IApp { return &dummyImpl{} }

	testing.SetRealm(testing.NewUserRealm(zkgmAdminForTest()))
	UpdateImpl(cur, testImplPathA)

	if currentImpl == nil {
		t.Fatal("UpdateImpl by admin must install the impl")
	}
	if currentImplPath != testImplPathA {
		t.Fatalf("currentImplPath = %q, want %q", currentImplPath, testImplPathA)
	}
}

func TestUpdateImplSwapsToLatestTarget(cur realm, t *testing.T) {
	resetZkgmForTest(cur)
	first := &dummyImpl{}
	second := &dummyImpl{}
	implConstructors[testImplPathA] = func(store IStore) IApp { return first }
	implConstructors[testImplPathB] = func(store IStore) IApp { return second }
	packet := core.NewPacket(1, 2, []byte("d"), 0)

	testing.SetRealm(testing.NewUserRealm(zkgmAdminForTest()))
	UpdateImpl(cur, testImplPathA)
	UpdateImpl(cur, testImplPathB)

	// Drive a packet through the proxy; only the latest impl must receive it.
	testing.SetRealm(testing.NewCodeRealm(coreRealmPath))
	AsIBCApp().OnRecvPacket(cross(cur), packet, address("g1relayer"), nil)

	if first.recvCalled {
		t.Fatal("displaced impl must not receive packets")
	}
	if !second.recvCalled {
		t.Fatal("latest impl must be the active swap target")
	}
}

func TestProxyAddressIsCaptured(cur realm, t *testing.T) {
	// proxyAddress is captured in upgrade.gno's init; it must be a real address.
	if ProxyAddress() == "" {
		t.Fatal("ProxyAddress must return the captured proxy realm address")
	}
}
