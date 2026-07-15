package v1

import (
	"testing"

	u256 "gno.land/p/gnoswap/uint256"
	"gno.land/p/nt/uassert/v0"
	types "gno.land/p/onbloc/ibc/union/types"
	tb "gno.land/p/onbloc/ibc/union/zkgm/tokenbucket"
	zkgm "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm"
)

func TestGetTokenBucketReturnsSnapshot(cur realm, t *testing.T) {
	v := newTestImpl()

	bucket, err := tb.New(u256.NewUint(100), u256.NewUint(5), u256.NewUint(7))
	uassert.NoError(t, err)
	uassert.NoError(t, bucket.RateLimit(u256.NewUint(20), u256.NewUint(7)))
	testStore.SetTokenBucket(0, cur, "ugnot-query", bucket)

	got, err := v.GetTokenBucket("ugnot-query")
	uassert.NoError(t, err)
	uassert.Equal(t, "100", got.Capacity.ToString())
	uassert.Equal(t, "80", got.Available.ToString())
	uassert.Equal(t, "5", got.RefillRate.ToString())
	uassert.Equal(t, "7", got.LastRefill.ToString())

	got.Available.Set(u256.Zero())
	stored, _ := testStore.GetTokenBucket("ugnot-query")
	uassert.Equal(t, "80", stored.Available.ToString())
}

func TestCloneTokenBucket(t *testing.T) {
	bucket, err := tb.New(u256.NewUint(100), u256.NewUint(5), u256.NewUint(7))
	uassert.NoError(t, err)
	uassert.NoError(t, bucket.RateLimit(u256.NewUint(20), u256.NewUint(7)))

	got := cloneTokenBucket(bucket)
	uassert.Equal(t, "100", got.Capacity.ToString())
	uassert.Equal(t, "80", got.Available.ToString())
	uassert.Equal(t, "5", got.RefillRate.ToString())
	uassert.Equal(t, "7", got.LastRefill.ToString())

	got.Available.Set(u256.Zero())
	uassert.Equal(t, "80", bucket.Available.ToString())
}

func TestGetTokenBucketMissingDenom(cur realm, t *testing.T) {
	v := newTestImpl()

	got, err := v.GetTokenBucket("missing-query")
	uassert.ErrorContains(t, err, zkgm.ErrTokenBucketNotFound)
	if got != nil {
		t.Fatal("missing token bucket must return nil")
	}
}

func TestGetChannelBalanceV2DerivesUnionQueryKey(cur realm, t *testing.T) {
	v := newTestImpl()

	path := u256.NewUint(11)
	key := ChannelBalanceKeyV2(types.ChannelId(7), path, []byte("ugnot"), []byte("quote"))
	testStore.SetChannelBalanceV2(0, cur, key, u256.NewUint(44))

	got, err := v.GetChannelBalanceV2(types.ChannelId(7), path, "ugnot", []byte("quote"))
	uassert.NoError(t, err)
	uassert.Equal(t, "44", got.ToString())

	got.Set(u256.Zero())
	stored, _ := testStore.GetChannelBalanceV2(key)
	uassert.Equal(t, "44", stored.ToString())
}

func TestGetChannelBalanceV2MissingKey(t *testing.T) {
	v := newTestImpl()

	got, err := v.GetChannelBalanceV2(types.ChannelId(9), u256.NewUint(1), "ugnot", []byte("quote"))
	uassert.ErrorContains(t, err, zkgm.ErrChannelBalanceV2NotFound)
	if got != nil {
		t.Fatal("missing channel balance must return nil")
	}
}
