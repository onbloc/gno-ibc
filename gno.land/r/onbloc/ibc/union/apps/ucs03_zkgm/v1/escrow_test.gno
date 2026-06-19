package impl

// escrow_test.gno covers escrow.gno's sendNative validation. The actual banker
// release (drawing from the proxy escrow account) requires funded realm balances
// and is integration-tested in the e2e suite; here we assert the pre-banker
// guard that rejects an amount that does not fit int64.

import (
	"testing"

	u256 "gno.land/p/gnoswap/uint256"
	"gno.land/p/nt/uassert/v0"
)

func TestSendNativeRejectsOverflowAmount(cur realm, t *testing.T) {
	v := newTestImpl()
	wide := new(u256.Uint).Lsh(u256.NewUint(1), 64) // > int64, > uint64

	err := v.sendNative(0, cur, "ugnot", testAddress("escrow-overflow-rx"), wide)

	uassert.Error(t, err)
}
