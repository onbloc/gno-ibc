package zkgm

import (
	"testing"

	"gno.land/p/nt/uassert/v0"
	core "gno.land/r/core/ibc/v1/core"
)

func TestProxyConfigAndAddress(t *testing.T) {
	resetZkgmForTest()
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

func TestProxyUpdateImplAllowedEmpty(t *testing.T) {
	resetZkgmForTest()
	d := &dummyImpl{}

	uassert.NotAborts(t, func(cur realm) {
		UpdateImpl(cur, UpdateRequest{Impl: d})
	})
	if impl == nil || ImplPath() == "" {
		t.Fatal("UpdateImpl must set impl and implPath")
	}
}

func TestProxyUpdateImplDeniedAfterLock(t *testing.T) {
	resetZkgmForTest()
	d := &dummyImpl{}
	allowedImpls = []string{"gno.land/r/not-this-realm"}

	uassert.AbortsContains(t, "permission denied", func(cur realm) {
		UpdateImpl(cur, UpdateRequest{Impl: d})
	})
	if impl != nil {
		t.Fatal("denied UpdateImpl must not change impl")
	}
}

func TestWriteForwardAckRequiresRegisteredImpl(t *testing.T) {
	resetZkgmForTest()
	implPath = "gno.land/r/not-this-realm"

	uassert.AbortsContains(t, "only registered impl", func(cur realm) {
		WriteForwardAck(cur, core.ChannelId(1), core.Sequence(7), core.NewBytes(cross, []byte{0x01}))
	})
}
