package zkgm

import "testing"

func TestProxyAddressIsCaptured(cur realm, t *testing.T) {
	// proxyAddress is captured in upgrade.gno's init; it must be a real address.
	if ProxyAddress() == "" {
		t.Fatal("ProxyAddress must return the captured proxy realm address")
	}
}
