package ucs03_zkgm

import (
	"testing"

	u256 "gno.land/p/gnoswap/uint256"
	"gno.land/p/nt/uassert/v0"
	"gno.land/r/onbloc/ibc/union/access"

	core "gno.land/r/onbloc/ibc/union/core"
	_ "gno.land/r/onbloc/ibc/union/core/v1"
)

// z1_proxy_test covers upgrade.gno's swap model. An impl realm registers its
// constructor under its own package path via RegisterImpl; the admin later
// activates a registered path via UpdateImpl, which injects the proxy store and
// builds the active impl. The model rejects non-admin callers and unregistered
// paths.

func TestUpdateImpl_RejectsNonAdmin(cur realm, t *testing.T) {
	resetZkgmForTest(cur)
	implConstructors[testImplPathA] = func(store IStore) IApp { return &dummyImpl{} }

	uassert.AbortsContains(t, cur, "access manager unauthorized call", func(cur realm) {
		UpdateImpl(cross(cur), testImplPathA)
	})
	if currentImpl != nil {
		t.Error("rejected UpdateImpl must not install an impl")
	}
}

func TestUpdateImpl_RejectsUnregisteredPath(cur realm, t *testing.T) {
	resetZkgmForTest(cur)

	// Set the admin realm inside the abort closure so the admin gate's
	// cur.Previous() resolves to the admin user realm; the unregistered-path
	// validation is then what aborts.
	uassert.AbortsContains(t, cur, "impl constructor not found", func(cur realm) {
		testing.SetRealm(testing.NewUserRealm(access.DefaultAdminAddress))
		UpdateImpl(cross(cur), testImplPathA)
	})
}

func TestUpdateImpl_ByAdminInstallsImpl(cur realm, t *testing.T) {
	resetZkgmForTest(cur)
	implConstructors[testImplPathA] = func(store IStore) IApp { return &dummyImpl{} }

	testing.SetRealm(testing.NewUserRealm(access.DefaultAdminAddress))
	UpdateImpl(cross(cur), testImplPathA)

	if currentImpl == nil {
		t.Fatal("UpdateImpl by admin must install the impl")
	}
	if currentImplPath != testImplPathA {
		t.Fatalf("currentImplPath = %q, want %q", currentImplPath, testImplPathA)
	}
}

func TestUpdateImpl_SwapsToLatestTarget(cur realm, t *testing.T) {
	resetZkgmForTest(cur)
	first := &dummyImpl{}
	second := &dummyImpl{}
	implConstructors[testImplPathA] = func(store IStore) IApp { return first }
	implConstructors[testImplPathB] = func(store IStore) IApp { return second }
	packet := core.NewPacket(1, 2, []byte("d"), 0)

	testing.SetRealm(testing.NewUserRealm(access.DefaultAdminAddress))
	UpdateImpl(cross(cur), testImplPathA)
	UpdateImpl(cross(cur), testImplPathB)

	// Drive a packet through the proxy; only the latest impl must receive it.
	testing.SetRealm(testing.NewCodeRealm(coreRealmPath))
	(&App{}).OnRecvPacket(cross(cur), packet, address("g1relayer"), nil)

	if first.recvCalled {
		t.Fatal("displaced impl must not receive packets")
	}
	if !second.recvCalled {
		t.Fatal("latest impl must be the active swap target")
	}
}

func TestRegisterCoreApp_RegistersProxyAndRejectsDuplicate(cur realm, t *testing.T) {
	testing.SetRealm(testing.NewUserRealm(access.DefaultAdminAddress))
	core.UpdateImpl(cross(cur), "gno.land/r/onbloc/ibc/union/core/v1")
	RegisterCoreApp(cross(cur))
	if !core.HasApp([]byte(ProxyPkgPath())) {
		t.Fatal("RegisterCoreApp must register the proxy package path")
	}

	testing.SetRealm(testing.NewUserRealm(access.DefaultAdminAddress))
	uassert.AbortsContains(t, cur, "already registered", func(cur realm) {
		RegisterCoreApp(cross(cur))
	})
}

func TestUpdateImpl_PreservesProxyStoreState(cur realm, t *testing.T) {
	resetZkgmForTest(cur)
	first := &dummyImpl{}
	second := &dummyImpl{}
	implConstructors[testImplPathA] = func(store IStore) IApp { return first }
	implConstructors[testImplPathB] = func(store IStore) IApp { return second }

	channelKey := "upgrade-continuity/channel-balance"
	inFlightKey := "upgrade-continuity/in-flight"
	parent := core.NewPacket(10, 11, []byte("parent"), 100)

	testing.SetRealm(testing.NewUserRealm(access.DefaultAdminAddress))
	UpdateImpl(cross(cur), testImplPathA)
	store.SetChannelBalanceV2(0, cur, channelKey, u256.NewUint(40))
	store.SetInFlightPacket(0, cur, inFlightKey, parent)
	UpdateImpl(cross(cur), testImplPathB)

	balance, ok := store.GetChannelBalanceV2(channelKey)
	uassert.True(t, ok)
	uassert.Equal(t, "40", balance.ToString())

	popped, ok := store.GetInFlightPacket(inFlightKey)
	uassert.True(t, ok)
	uassert.Equal(t, "parent", string(popped.Data))
	uassert.True(t, currentImpl == second)
	uassert.True(t, currentImpl != first)
}

func TestProxyAddress_IsCaptured(cur realm, t *testing.T) {
	// proxyAddress is captured in upgrade.gno's init; it must be a real address.
	if ProxyAddress() == "" {
		t.Fatal("ProxyAddress must return the captured proxy realm address")
	}
}
