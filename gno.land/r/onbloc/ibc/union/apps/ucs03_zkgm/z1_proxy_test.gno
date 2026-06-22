package zkgm

import (
	"testing"

	"gno.land/p/nt/uassert/v0"
	core "gno.land/r/onbloc/ibc/union/core"
)

// z1_proxy_test covers upgrade.gno's swap model. The model is a single
// admin-gated pointer: UpdateImpl installs/repoints the active impl, rejecting
// non-admin callers and nil targets. (The previous allowlist/bootstrap/
// ForceSetImpl tiers were removed in favour of this simpler admin-only swap.)

func TestUpdateImplRejectsNonAdmin(cur realm, t *testing.T) {
	resetZkgmForTest(cur)

	uassert.AbortsContains(t, cur, "caller not authorized to update_impl", func(cur realm) {
		UpdateImpl(cross(cur), &dummyImpl{})
	})
	if impl != nil {
		t.Error("rejected UpdateImpl must not install an impl")
	}
}

func TestUpdateImplRejectsNilTarget(cur realm, t *testing.T) {
	resetZkgmForTest(cur)

	// Call with the outer (admin) cur, not the closure's crossing param, so the
	// admin gate passes and the nil-target validation is what aborts.
	testing.SetRealm(testing.NewUserRealm(zkgmAdminForTest()))
	uassert.AbortsContains(t, cur, "impl cannot be nil", func(_ realm) {
		UpdateImpl(cur, nil)
	})
}

func TestUpdateImplByAdminInstallsImpl(cur realm, t *testing.T) {
	resetZkgmForTest(cur)

	testing.SetRealm(testing.NewUserRealm(zkgmAdminForTest()))
	UpdateImpl(cur, &dummyImpl{})

	if impl == nil {
		t.Fatal("UpdateImpl by admin must install the impl")
	}
}

func TestUpdateImplSwapsToLatestTarget(cur realm, t *testing.T) {
	resetZkgmForTest(cur)
	first := &dummyImpl{}
	second := &dummyImpl{}
	packet := core.NewPacket(1, 2, []byte("d"), 0)

	testing.SetRealm(testing.NewUserRealm(zkgmAdminForTest()))
	UpdateImpl(cur, first)
	UpdateImpl(cur, second)

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
