package zkgm

import (
	"chain"
	"chain/banker"
	"testing"

	types "gno.land/p/onbloc/ibc/union/types"

	u256 "gno.land/p/gnoswap/uint256"
	"gno.land/p/nt/uassert/v0"
	tb "gno.land/p/onbloc/ibc/union/zkgm/tokenbucket"
	core "gno.land/r/onbloc/ibc/union/core"
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
		{"v1 impl", ProxyPkgPath() + "/v1", true},
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
	testing.SetRealm(testing.NewCodeRealm(ProxyPkgPath()))

	uassert.NotAborts(t, cur, func(cur realm) {
		UpdateImpl(cross(cur), NewUpdateRequest(cross(cur), d, []string{ProxyPkgPath()}))
	})
	if impl != d || ImplPath() != ProxyPkgPath() {
		t.Fatal("registered impl caller must be able to update impl")
	}
	if !Bootstrapped() {
		t.Fatal("UpdateImpl must mark the proxy as bootstrapped when it installs an impl")
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
	packet := core.NewPacket(cross(cur), 1, 2, []byte("data"), 20)
	key := NewInFlightKey(cross(cur), types.MustCommit(types.CommitPacket(packet)))
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
		WriteForwardAck(cur, core.NewPacket(cross(cur), 1, 2, nil, 0), []byte{0x01})
	})
}

func TestBatchSendAllowsAllowedImplCaller(cur realm, t *testing.T) {
	resetZkgmForTest()
	implPath = "gno.land/r/not-this-realm"
	allowedImpls = []string{ProxyPkgPath()}

	uassert.AbortsContains(t, cur, "not enough packets", func(cur realm) {
		BatchSend(cur, types.NewMsgBatchSend(nil))
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

func TestVoucherMutatorsAllowAuthorizedImplCaller(cur realm, t *testing.T) {
	resetZkgmForTest()
	implPath = "gno.land/r/not-this-realm"
	allowedImpls = []string{ProxyPkgPath()}
	receiver := address("g1wymu47drhr0kuq2098m792lytgtj2nyx77yrsm")

	testing.SetRealm(testing.NewCodeRealm(ProxyPkgPath()))
	uassert.NoError(t, MintVoucher(cross(cur), "ibc/proxy-auth", "ibc/proxy-auth", [32]byte{}, "", "PROXYAUTH", 0, receiver.String(), u256.NewUint(7)))

	uassert.Equal(t, int64(7), VoucherBalanceOf("ibc/proxy-auth", receiver))
}

func TestMintVoucherSanitizesSymbolAtProxyBoundary(cur realm, t *testing.T) {
	resetZkgmForTest()
	implPath = "gno.land/r/not-this-realm"
	allowedImpls = []string{ProxyPkgPath()}
	receiver := address("g1wymu47drhr0kuq2098m792lytgtj2nyx77yrsm")

	testing.SetRealm(testing.NewCodeRealm(ProxyPkgPath()))
	uassert.NoError(t, MintVoucher(cross(cur), "ibc/proxy-raw", "ibc/proxy-raw", [32]byte{}, "", "!!!", 0, receiver.String(), u256.NewUint(7)))

	uassert.Equal(t, int64(7), VoucherBalanceOf("ibc/proxy-raw", receiver))
	uassert.Equal(t, "proxy-raw", VoucherSymbolOf("ibc/proxy-raw"))
}

func TestSanitizeVoucherSymbol(t *testing.T) {
	ibcDenom := ibcDenomPrefix + "abcdef123456"

	tests := []struct {
		name      string
		candidate string
		want      string
	}{
		{
			name:      "valid ascii passes through",
			candidate: "USDC",
			want:      "USDC",
		},
		{
			name:      "truncated to 11 chars",
			candidate: "ABCDEFGHIJKLMNOP",
			want:      "ABCDEFGHIJK",
		},
		{
			name:      "invalid chars stripped",
			candidate: "US@D#C!",
			want:      "USDC",
		},
		{
			name:      "truncation after stripping mixed valid and invalid",
			candidate: "AB@CD#EF$GH%IJ^KL",
			want:      "ABCDEFGHIJK",
		},
		{
			name:      "all invalid chars falls back to ibcDenom suffix",
			candidate: "@#$%^&*()",
			want:      "abcdef12345",
		},
		{
			name:      "empty string falls back to ibcDenom suffix",
			candidate: "",
			want:      "abcdef12345",
		},
		{
			name:      "underscore and dash are valid",
			candidate: "my_token-v2",
			want:      "my_token-v2",
		},
		{
			name:      "unicode multi-byte chars are filtered",
			candidate: "USD€coin",
			want:      "USDcoin",
		},
		{
			name:      "unicode-only input falls back to ibcDenom suffix",
			candidate: "한글심볼",
			want:      "abcdef12345",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := sanitizeVoucherSymbol(tt.candidate, ibcDenom)
			uassert.Equal(t, tt.want, got)
		})
	}
}

func TestVoucherMutatorsRejectUnlistedCaller(cur realm, t *testing.T) {
	resetZkgmForTest()
	implPath = "gno.land/r/not-this-realm"
	allowedImpls = []string{"gno.land/r/other-authorized-realm"}
	receiver := address("g1wymu47drhr0kuq2098m792lytgtj2nyx77yrsm")

	testing.SetRealm(testing.NewCodeRealm(ProxyPkgPath()))
	uassert.AbortsContains(t, cur, "not an authorized impl", func(cur realm) {
		MintVoucher(cross(cur), "ibc/proxy-deny", "ibc/proxy-deny", [32]byte{}, "", "PROXYDENY", 0, receiver.String(), u256.NewUint(7))
	})
}

// Conventions for exercising the admin-gated ForceSetImpl from tests.
//
// core.GetAdmin() is the empty address in unit tests, because core's init
// captures OriginCaller, which is unset at import time. mustBeAdmin compares
// cur.Previous().Address() against core.GetAdmin(), so the caller's Previous()
// must also resolve to the empty address.
//
// To satisfy that, set the realm with SetRealm(NewUserRealm(core.GetAdmin()))
// and call ForceSetImpl without crossing, as ForceSetImpl(cur, ...). A
// non-crossing call keeps Previous() at the empty address, whereas crossing
// with cross(cur) does not propagate the empty realm and falls back to this
// realm's own address, which trips "admin only".
//
// Because the call does not cross a realm boundary, a rejection inside
// ForceSetImpl surfaces as a local panic, so assert it with PanicsContains
// rather than AbortsContains.
//
// Do not call SetRealm(NewCodeRealm(...)) before ForceSetImpl: it rebinds
// cur.Previous() to that realm and a later NewUserRealm SetRealm does not reset
// it. Establish bootstrapped state through the package vars instead.
//
// The non-admin denial path is the exception. A real, non-empty caller address
// propagates across a cross(cur) boundary normally, so that case crosses and
// asserts with AbortsContains; see TestForceSetImplDeniedForNonAdmin.

func TestForceSetImplByAdmin(cur realm, t *testing.T) {
	resetZkgmForTest()
	oldImplPath := "gno.land/r/old-impl"
	newImplPath := "gno.land/r/new-impl"
	implPath = oldImplPath
	allowedImpls = []string{"gno.land/r/not-this-realm"}
	d := &dummyImpl{}

	testing.SetRealm(testing.NewUserRealm(core.GetAdmin()))
	ForceSetImpl(cur, d, []string{newImplPath})

	if impl != d {
		t.Fatal("ForceSetImpl must install the new impl")
	}
	if ImplPath() != "" {
		t.Fatal("ForceSetImpl must clear implPath until the new impl self-registers")
	}
	if isAuthorizedImpl(oldImplPath) {
		t.Fatal("ForceSetImpl must deauthorize the displaced impl path")
	}
	if !isAuthorizedImpl(newImplPath) {
		t.Fatal("ForceSetImpl must authorize the new impl through allowedImpls")
	}
	cfg := GetConfig()
	if cfg.ImplPath != "" {
		t.Fatal("GetConfig must report the cleared implPath")
	}
	if len(cfg.AllowedImpls) != 1 || cfg.AllowedImpls[0] != newImplPath {
		t.Fatal("ForceSetImpl must replace allowedImpls")
	}
}

func TestForceSetImplDeniedForNonAdmin(cur realm, t *testing.T) {
	resetZkgmForTest()
	d := &dummyImpl{}

	testing.SetRealm(testing.NewUserRealm(address("g1wymu47drhr0kuq2098m792lytgtj2nyx77yrsm")))

	uassert.AbortsContains(t, cur, "zkgm: admin only", func(cur realm) {
		ForceSetImpl(cross(cur), d, nil)
	})
}

func TestForceSetImplDeauthorizesOldFundMover(cur realm, t *testing.T) {
	resetZkgmForTest()
	cacheRealm(cur)
	implPath = ProxyPkgPath()
	allowedImpls = []string{ProxyPkgPath()}
	d := &dummyImpl{}

	denom := "uforcesetold"
	recipient := address("g1wymu47drhr0kuq2098m792lytgtj2nyx77yrsm")
	testing.IssueCoins(ProxyAddress(), chain.NewCoins(chain.NewCoin(denom, 7)))

	testing.SetRealm(testing.NewUserRealm(core.GetAdmin()))
	ForceSetImpl(cur, d, []string{"gno.land/r/new-impl"})

	uassert.AbortsContains(t, cur, "not an authorized impl", func(cur realm) {
		ReleaseNative(cross(cur), denom, recipient, 7)
	})

	bk := banker.NewReadonlyBanker()
	uassert.Equal(t, int64(0), bk.GetCoins(recipient).AmountOf(denom))
	uassert.Equal(t, int64(7), bk.GetCoins(ProxyAddress()).AmountOf(denom))
}

func TestForceSetImplAllowsNewImplThroughAllowlist(cur realm, t *testing.T) {
	resetZkgmForTest()
	d := &dummyImpl{}

	testing.SetRealm(testing.NewUserRealm(core.GetAdmin()))
	ForceSetImpl(cur, d, []string{ProxyPkgPath()})

	testing.SetRealm(testing.NewCodeRealm(ProxyPkgPath()))
	uassert.AbortsContains(t, cur, "not enough packets", func(cur realm) {
		BatchSend(cross(cur), types.NewMsgBatchSend(nil))
	})
}

func TestForceSetImplSelfRegisters(cur realm, t *testing.T) {
	resetZkgmForTest()
	d1 := &dummyImpl{}
	d2 := &dummyImpl{}

	testing.SetRealm(testing.NewUserRealm(core.GetAdmin()))
	ForceSetImpl(cur, d1, []string{ProxyPkgPath()})

	testing.SetRealm(testing.NewCodeRealm(ProxyPkgPath()))
	UpdateImpl(cross(cur), NewUpdateRequest(cross(cur), d2, nil))

	if impl != d2 {
		t.Fatal("allowed new impl must be able to self-register")
	}
	if ImplPath() != ProxyPkgPath() {
		t.Fatal("self-registration must bind implPath to the verified caller")
	}
	if !Bootstrapped() {
		t.Fatal("self-registration must preserve bootstrapped state")
	}
}

func TestForceSetImplRejectsNonNilImplWithEmptyAllowlist(cur realm, t *testing.T) {
	resetZkgmForTest()
	oldImpl := &dummyImpl{}
	impl = oldImpl
	implPath = "gno.land/r/old-impl"
	allowedImpls = []string{"gno.land/r/old-impl"}
	d := &dummyImpl{}

	testing.SetRealm(testing.NewUserRealm(core.GetAdmin()))
	uassert.PanicsContains(t, cur, "non-empty allowlist", func() {
		ForceSetImpl(cur, d, nil)
	})
	if impl != oldImpl || ImplPath() != "gno.land/r/old-impl" || len(allowedImpls) != 1 || allowedImpls[0] != "gno.land/r/old-impl" {
		t.Fatal("rejected ForceSetImpl with nil allowlist must not mutate state")
	}

	testing.SetRealm(testing.NewUserRealm(core.GetAdmin()))
	uassert.PanicsContains(t, cur, "non-empty allowlist", func() {
		ForceSetImpl(cur, d, []string{})
	})
	if impl != oldImpl || ImplPath() != "gno.land/r/old-impl" || len(allowedImpls) != 1 || allowedImpls[0] != "gno.land/r/old-impl" {
		t.Fatal("rejected ForceSetImpl with empty allowlist must not mutate state")
	}
}

func TestForceSetImplClearImplIsAllowed(cur realm, t *testing.T) {
	resetZkgmForTest()
	oldImplPath := ProxyPkgPath()
	impl = &dummyImpl{}
	implPath = oldImplPath
	allowedImpls = []string{oldImplPath}

	testing.SetRealm(testing.NewUserRealm(core.GetAdmin()))
	ForceSetImpl(cur, nil, nil)

	if impl != nil {
		t.Fatal("ForceSetImpl nil impl must clear the impl")
	}
	if ImplPath() != "" {
		t.Fatal("ForceSetImpl nil impl must clear implPath")
	}
	if isAuthorizedImpl(oldImplPath) {
		t.Fatal("ForceSetImpl nil impl must deauthorize the old impl path")
	}
}

func TestForceSetImplKeepsBootstrappedLock(cur realm, t *testing.T) {
	resetZkgmForTest()
	d := &dummyImpl{}
	// Stand in for a proxy that has already bootstrapped through UpdateImpl. The
	// realistic bootstrap path is covered by TestForceSetImplSelfRegisters and
	// TestProxyUpdateImplPostBootstrapAllowsRegisteredImpl; here we only need the
	// bootstrapped lock set so we can assert ForceSetImpl preserves it.
	impl = d
	implPath = ProxyPkgPath()
	allowedImpls = []string{ProxyPkgPath()}
	bootstrapped = true
	if !Bootstrapped() {
		t.Fatal("test setup must bootstrap proxy")
	}

	testing.SetRealm(testing.NewUserRealm(core.GetAdmin()))
	ForceSetImpl(cur, d, []string{ProxyPkgPath()})

	if !Bootstrapped() {
		t.Fatal("ForceSetImpl must not reopen the impl singleton bootstrap lock")
	}
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
