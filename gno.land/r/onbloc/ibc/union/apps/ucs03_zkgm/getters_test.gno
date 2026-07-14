package ucs03_zkgm

import (
	"errors"
	"testing"

	u256 "gno.land/p/gnoswap/uint256"
	"gno.land/p/nt/uassert/v0"
	"gno.land/p/onbloc/ibc/union/types"
	tb "gno.land/p/onbloc/ibc/union/zkgm/tokenbucket"
)

var errDummyGetter = errors.New("dummy getter error")

func TestGetTokenBucket_DelegatesToImpl(cur realm, t *testing.T) {
	resetZkgmForTest(cur)

	bucket, err := tb.New(u256.NewUint(100), u256.NewUint(5), u256.NewUint(7))
	uassert.NoError(t, err)
	target := &dummyImpl{tokenBucket: bucket}
	installImplForTest(testImplPathA, target)

	got, err := GetTokenBucket("ugnot-query")
	uassert.NoError(t, err)
	uassert.Equal(t, "100", got.Capacity.ToString())
}

func TestGetTokenBucket_PropagatesImplError(cur realm, t *testing.T) {
	resetZkgmForTest(cur)
	target := &dummyImpl{tokenBucketErr: errDummyGetter}
	installImplForTest(testImplPathA, target)

	got, err := GetTokenBucket("missing-query")
	uassert.ErrorIs(t, err, errDummyGetter)
	if got != nil {
		t.Fatal("missing token bucket must return nil")
	}
}

func TestGetChannelBalanceV2_DelegatesToImpl(cur realm, t *testing.T) {
	resetZkgmForTest(cur)

	path := u256.NewUint(11)
	target := &dummyImpl{channelBalance: u256.NewUint(44)}
	installImplForTest(testImplPathA, target)

	got, err := GetChannelBalanceV2(types.ChannelId(7), path, "ugnot", []byte("quote"))
	uassert.NoError(t, err)
	uassert.Equal(t, "44", got.ToString())
	uassert.Equal(t, uint32(7), uint32(target.lastBalanceChannelId))
	uassert.Equal(t, "11", target.lastBalancePath.ToString())
	uassert.Equal(t, "ugnot", target.lastBalanceBaseToken)
	uassert.Equal(t, "quote", string(target.lastBalanceQuote))
}

func TestGetChannelBalanceV2_PropagatesImplError(cur realm, t *testing.T) {
	resetZkgmForTest(cur)
	target := &dummyImpl{channelBalanceErr: errDummyGetter}
	installImplForTest(testImplPathA, target)

	got, err := GetChannelBalanceV2(types.ChannelId(9), u256.NewUint(1), "ugnot", []byte("quote"))
	uassert.ErrorIs(t, err, errDummyGetter)
	if got != nil {
		t.Fatal("missing channel balance must return nil")
	}
}
