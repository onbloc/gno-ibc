package zkgm

import (
	"chain"
	"chain/banker"
	"testing"

	"gno.land/p/nt/uassert/v0"
	core "gno.land/r/core/ibc/v1/core"
)

func TestProxyConfigAndAddress(cur realm, t *testing.T) {
	resetZkgmForTest()
	cacheRealm(cur)
	if ProxyAddress() == "" {
		t.Fatal("ProxyAddress must expose the proxy realm address")
	}
	if AsIBCApp() == nil {
		t.Fatal("AsIBCApp must return an app")
	}
	cfg := GetConfig()
	if cfg.ImplPath != "" || cfg.Paused {
		t.Fatal("initial config must be empty")
	}
}

func TestProxyUpdateImplAllowedEmpty(cur realm, t *testing.T) {
	resetZkgmForTest()
	d := &dummyImpl{}

	uassert.NotAborts(t, cur, func(cur realm) {
		UpdateImpl(cur, NewUpdateRequest(cur, d, nil))
	})
	if impl == nil || ImplPath() == "" {
		t.Fatal("UpdateImpl must set impl and implPath")
	}
}

func TestProxyUpdateImplDeniedAfterLock(cur realm, t *testing.T) {
	resetZkgmForTest()
	d := &dummyImpl{}
	allowedImpls = []string{"gno.land/r/not-this-realm"}

	uassert.AbortsContains(t, cur, "permission denied", func(cur realm) {
		UpdateImpl(cur, NewUpdateRequest(cur, d, nil))
	})
	if impl != nil {
		t.Fatal("denied UpdateImpl must not change impl")
	}
}

func TestWriteForwardAckRequiresRegisteredImpl(cur realm, t *testing.T) {
	resetZkgmForTest()
	implPath = "gno.land/r/not-this-realm"

	uassert.AbortsContains(t, cur, "only registered impl", func(cur realm) {
		WriteForwardAck(cur, core.NewPacket(cross(cur), 1, 2, nil, 0, 0), []byte{0x01})
	})
}

func TestBatchSendAllowsAllowedImplCaller(cur realm, t *testing.T) {
	resetZkgmForTest()
	implPath = "gno.land/r/not-this-realm"
	allowedImpls = []string{ProxyPkgPath()}

	uassert.AbortsContains(t, cur, "not enough packets", func(cur realm) {
		BatchSend(cur, core.NewMsgBatchSend(cross(cur), nil))
	})
}

func TestReleaseNativeAllowsAuthorizedImplCaller(cur realm, t *testing.T) {
	resetZkgmForTest()
	cacheRealm(cur)
	implPath = "gno.land/r/not-this-realm"
	allowedImpls = []string{ProxyPkgPath()}

	denom := "ureleaseauth"
	recipient := address("g1wymu47drhr0kuq2098m792lytgtj2nyx77yrsm")
	testing.IssueCoins(ProxyAddress(), chain.NewCoins(chain.NewCoin(denom, 7)))

	uassert.NotAborts(t, cur, func(cur realm) {
		ReleaseNative(cur, denom, recipient, 7)
	})

	bk := banker.NewReadonlyBanker()
	uassert.Equal(t, int64(7), bk.GetCoins(recipient).AmountOf(denom))
	uassert.Equal(t, int64(0), bk.GetCoins(ProxyAddress()).AmountOf(denom))
}

func TestReleaseNativeRejectsUnlistedCaller(cur realm, t *testing.T) {
	resetZkgmForTest()
	cacheRealm(cur)
	implPath = "gno.land/r/not-this-realm"
	allowedImpls = []string{"gno.land/r/other-authorized-realm"}

	denom := "ureleasedeny"
	recipient := address("g1wymu47drhr0kuq2098m792lytgtj2nyx77yrsm")
	testing.IssueCoins(ProxyAddress(), chain.NewCoins(chain.NewCoin(denom, 7)))

	uassert.AbortsContains(t, cur, "only registered impl", func(cur realm) {
		ReleaseNative(cur, denom, recipient, 7)
	})

	bk := banker.NewReadonlyBanker()
	uassert.Equal(t, int64(0), bk.GetCoins(recipient).AmountOf(denom))
	uassert.Equal(t, int64(7), bk.GetCoins(ProxyAddress()).AmountOf(denom))
}

func TestReleaseNativeRejectsCallerWhenAllowedListEmpty(cur realm, t *testing.T) {
	resetZkgmForTest()
	cacheRealm(cur)
	implPath = "gno.land/r/not-this-realm"

	denom := "ureleaseempty"
	recipient := address("g1wymu47drhr0kuq2098m792lytgtj2nyx77yrsm")
	testing.IssueCoins(ProxyAddress(), chain.NewCoins(chain.NewCoin(denom, 7)))

	uassert.AbortsContains(t, cur, "only registered impl", func(cur realm) {
		ReleaseNative(cur, denom, recipient, 7)
	})

	bk := banker.NewReadonlyBanker()
	uassert.Equal(t, int64(0), bk.GetCoins(recipient).AmountOf(denom))
	uassert.Equal(t, int64(7), bk.GetCoins(ProxyAddress()).AmountOf(denom))
}
