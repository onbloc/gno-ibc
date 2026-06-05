package zkgm

import (
	"chain"
	"chain/banker"
	"testing"

	tb "gno.land/p/onbloc/tokenbucket"
	u256 "gno.land/p/gnoswap/uint256"
	"gno.land/p/nt/uassert/v0"
	core "gno.land/r/onbloc/unionibc/v1/core"
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

func TestInAllowedImplsFailsClosedOnEmpty(t *testing.T) {
	resetZkgmForTest()

	if InAllowedImpls("gno.land/r/anything") {
		t.Fatal("empty allowedImpls must fail closed")
	}
}

func TestIsAuthorizedImplRejectsEmptyCaller(t *testing.T) {
	resetZkgmForTest()

	if isAuthorizedImpl("") {
		t.Fatal("empty caller must not match empty implPath")
	}

	implPath = "gno.land/r/authorized"
	allowedImpls = []string{"gno.land/r/also-authorized"}
	if isAuthorizedImpl("") {
		t.Fatal("empty caller must not match populated authorization state")
	}
}

func TestProxyUpdateImplBootstrapRejectsUnpermittedCaller(cur realm, t *testing.T) {
	resetZkgmForTest()
	d := &dummyImpl{}

	uassert.AbortsContains(t, cur, "bootstrap not permitted", func(cur realm) {
		UpdateImpl(cur, NewUpdateRequest(cur, d, nil))
	})
	if impl != nil || implPath != "" || allowedImpls != nil {
		t.Fatal("denied bootstrap UpdateImpl must not change proxy config")
	}
}

func TestProxyBootstrapCallerUsesProxyNamespacePrefix(t *testing.T) {
	testCases := []struct {
		name   string
		caller string
		want   bool
	}{
		{"proxy realm itself", ProxyPkgPath(), false},
		{"v0 loader", ProxyPkgPath() + "/v0/loader", true},
		{"v0 impl", ProxyPkgPath() + "/v0/impl", true},
		{"testing loader", ProxyPkgPath() + "/testing/loader", true},
		{"similar prefix", ProxyPkgPath() + "2/v0/loader", false},
		{"outside namespace", "gno.land/r/other/zkgm/v0/loader", false},
	}

	for _, tc := range testCases {
		t.Run(tc.name, func(t *testing.T) {
			if got := isBootstrapCaller(tc.caller); got != tc.want {
				t.Fatalf("isBootstrapCaller(%q) = %t, want %t", tc.caller, got, tc.want)
			}
		})
	}
}

func TestProxyUpdateImplPostBootstrapAllowsRegisteredImpl(cur realm, t *testing.T) {
	resetZkgmForTest()
	d := &dummyImpl{}
	implPath = ProxyPkgPath()

	uassert.NotAborts(t, cur, func(cur realm) {
		UpdateImpl(cur, NewUpdateRequest(cur, d, []string{ProxyPkgPath()}))
	})
	if impl != d || ImplPath() != ProxyPkgPath() {
		t.Fatal("registered impl caller must be able to update impl")
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

func TestLedgerWritersFailClosedWhenUnbootstrapped(cur realm, t *testing.T) {
	resetZkgmForTest()
	packet := core.NewPacket(cross(cur), 1, 2, []byte("data"), 0, 20)
	key := NewInFlightKey(cross(cur), core.CommitPacket(packet))
	value := NewInFlightValue(cross(cur), packet)
	bucket, err := tb.New(u256.NewUint(10), u256.NewUint(1), blockNow())
	if err != nil {
		t.Fatal(err)
	}

	testCases := []struct {
		name string
		call func(cur realm)
	}{
		{"SetTokenOrigin", func(cur realm) {
			SetTokenOrigin(cross(cur), "ibc/failclosed", u256.Zero())
		}},
		{"SetMetadataImageOf", func(cur realm) {
			SetMetadataImageOf(cross(cur), "ibc/failclosed", [32]byte{})
		}},
		{"SetChannelBalanceV2", func(cur realm) {
			SetChannelBalanceV2(cross(cur), "balance-key", u256.NewUint(1))
		}},
		{"RemoveChannelBalanceV2", func(cur realm) {
			RemoveChannelBalanceV2(cross(cur), "balance-key")
		}},
		{"SetInFlightPacket", func(cur realm) {
			SetInFlightPacket(cross(cur), key, value)
		}},
		{"PopInFlightPacket", func(cur realm) {
			PopInFlightPacket(cross(cur), key)
		}},
		{"SetTokenBucket", func(cur realm) {
			SetTokenBucket(cross(cur), "ibc/failclosed", bucket)
		}},
		{"RemoveTokenBucket", func(cur realm) {
			RemoveTokenBucket(cross(cur), "ibc/failclosed")
		}},
		{"RateLimit", func(cur realm) {
			RateLimit(cross(cur), "ibc/failclosed", u256.NewUint(1))
		}},
	}

	for _, tc := range testCases {
		t.Run(tc.name, func(t *testing.T) {
			uassert.AbortsContains(t, cur, "not an authorized impl", tc.call)
		})
	}
}

func TestLedgerWriterAllowedFromRegisteredImpl(cur realm, t *testing.T) {
	resetZkgmForTest()
	implPath = ProxyPkgPath()

	uassert.NotAborts(t, cur, func(cur realm) {
		SetTokenOrigin(cross(cur), "ibc/registered", u256.Zero())
	})
	if _, ok := GetTokenOrigin("ibc/registered"); !ok {
		t.Fatal("registered impl caller must be able to write ledger state")
	}
}

func TestWriteForwardAckRequiresRegisteredImpl(cur realm, t *testing.T) {
	resetZkgmForTest()
	implPath = "gno.land/r/not-this-realm"

	uassert.AbortsContains(t, cur, "not an authorized impl", func(cur realm) {
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

	uassert.AbortsContains(t, cur, "not an authorized impl", func(cur realm) {
		ReleaseNative(cur, denom, recipient, 7)
	})

	bk := banker.NewReadonlyBanker()
	uassert.Equal(t, int64(0), bk.GetCoins(recipient).AmountOf(denom))
	uassert.Equal(t, int64(7), bk.GetCoins(ProxyAddress()).AmountOf(denom))
}

func TestForceSetImplByAdmin(cur realm, t *testing.T) {
	resetZkgmForTest()
	oldImplPath := "gno.land/r/old-impl"
	implPath = oldImplPath
	allowedImpls = []string{"gno.land/r/not-this-realm"}
	d := &dummyImpl{}

	ForceSetImpl(cur, d, []string{"gno.land/r/new-impl"})

	if impl == nil {
		t.Fatal("ForceSetImpl must install the new impl")
	}
	if ImplPath() != oldImplPath {
		t.Fatal("ForceSetImpl must not modify implPath; new impl must call UpdateImpl to register")
	}
	cfg := GetConfig()
	if len(cfg.AllowedImpls) != 1 || cfg.AllowedImpls[0] != "gno.land/r/new-impl" {
		t.Fatal("ForceSetImpl must replace allowedImpls")
	}
}

func TestForceSetImplDeniedForNonAdmin(cur realm, t *testing.T) {
	resetZkgmForTest()
	d := &dummyImpl{}

	testing.SetRealm(testing.NewUserRealm(address("g1wymu47drhr0kuq2098m792lytgtj2nyx77yrsm")))

	uassert.AbortsContains(t, cur, "zkgm: admin only", func(cur realm) {
		ForceSetImpl(cur, d, nil)
	})
}

func TestReleaseNativeRejectsCallerWhenAllowedListEmpty(cur realm, t *testing.T) {
	resetZkgmForTest()
	cacheRealm(cur)
	implPath = "gno.land/r/not-this-realm"

	denom := "ureleaseempty"
	recipient := address("g1wymu47drhr0kuq2098m792lytgtj2nyx77yrsm")
	testing.IssueCoins(ProxyAddress(), chain.NewCoins(chain.NewCoin(denom, 7)))

	uassert.AbortsContains(t, cur, "not an authorized impl", func(cur realm) {
		ReleaseNative(cur, denom, recipient, 7)
	})

	bk := banker.NewReadonlyBanker()
	uassert.Equal(t, int64(0), bk.GetCoins(recipient).AmountOf(denom))
	uassert.Equal(t, int64(7), bk.GetCoins(ProxyAddress()).AmountOf(denom))
}
