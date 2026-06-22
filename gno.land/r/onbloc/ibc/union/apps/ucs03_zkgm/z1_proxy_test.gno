package zkgm

import (
	"testing"

	u256 "gno.land/p/gnoswap/uint256"
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
	resetZkgmForTest()
	implConstructors[testImplPathA] = func(store IStore) IApp { return &dummyImpl{} }

	uassert.AbortsContains(t, cur, "zkgm: admin only", func(cur realm) {
		UpdateImpl(cross(cur), testImplPathA)
	})
	if currentImpl != nil {
		t.Error("rejected UpdateImpl must not install an impl")
	}
}

func TestUpdateImplRejectsUnregisteredPath(cur realm, t *testing.T) {
	resetZkgmForTest()

	// Call with the outer (admin) cur, not the closure's crossing param, so the
	// admin gate passes and the unregistered-path validation is what aborts.
	testing.SetRealm(testing.NewUserRealm(core.GetAdmin()))
	uassert.AbortsContains(t, cur, "impl constructor not found", func(_ realm) {
		UpdateImpl(cur, testImplPathA)
	})
}

func TestUpdateImplByAdminInstallsImpl(cur realm, t *testing.T) {
	resetZkgmForTest()
	implConstructors[testImplPathA] = func(store IStore) IApp { return &dummyImpl{} }

	testing.SetRealm(testing.NewUserRealm(core.GetAdmin()))
	UpdateImpl(cur, testImplPathA)

	if currentImpl == nil {
		t.Fatal("UpdateImpl by admin must install the impl")
	}
	if currentImplPath != testImplPathA {
		t.Fatalf("currentImplPath = %q, want %q", currentImplPath, testImplPathA)
	}
}

func TestUpdateImplSwapsToLatestTarget(cur realm, t *testing.T) {
	resetZkgmForTest()
	first := &dummyImpl{}
	second := &dummyImpl{}
	implConstructors[testImplPathA] = func(store IStore) IApp { return first }
	implConstructors[testImplPathB] = func(store IStore) IApp { return second }
	packet := core.NewPacket(1, 2, []byte("d"), 0)

	testing.SetRealm(testing.NewUserRealm(core.GetAdmin()))
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

func TestUpdateImplPreservesProxyStoreState(cur realm, t *testing.T) {
	resetZkgmForTest()
	first := &dummyImpl{}
	second := &dummyImpl{}
	implConstructors[testImplPathA] = func(store IStore) IApp { return first }
	implConstructors[testImplPathB] = func(store IStore) IApp { return second }

	channelKey := "upgrade-continuity/channel-balance"
	inFlightKey := "upgrade-continuity/in-flight"
	parent := core.NewPacket(10, 11, []byte("parent"), 100)

	testing.SetRealm(testing.NewUserRealm(core.GetAdmin()))
	UpdateImpl(cur, testImplPathA)
	store.SetChannelBalanceV2(0, cur, channelKey, u256.NewUint(40))
	store.SetInFlightPacket(0, cur, inFlightKey, parent)
	UpdateImpl(cur, testImplPathB)

	balance, ok := store.GetChannelBalanceV2(channelKey)
	uassert.True(t, ok)
	uassert.Equal(t, "40", balance.ToString())

	popped, ok := store.GetInFlightPacket(inFlightKey)
	uassert.True(t, ok)
	uassert.Equal(t, "parent", string(popped.Data))
	uassert.True(t, currentImpl == second)
	uassert.True(t, currentImpl != first)
}

func TestProxyAddressIsCaptured(cur realm, t *testing.T) {
	// proxyAddress is captured in upgrade.gno's init; it must be a real address.
	if ProxyAddress() == "" {
		t.Fatal("ProxyAddress must return the captured proxy realm address")
	}
}
