package zkgm

import (
	"chain/runtime"

	tb "gno.land/p/gnoswap/tokenbucket"
	u256 "gno.land/p/gnoswap/uint256"
)

func SetAdmin(cur realm, admin string) {
	if adminAddressStr != "" && runtime.OriginCaller().String() != adminAddressStr {
		panic("zkgm: admin only")
	}
	adminAddressStr = admin
}

func Pause(cur realm) {
	mustBeAdmin()
	paused = true
}

func Unpause(cur realm) {
	mustBeAdmin()
	paused = false
}

func SetBucketConfig(cur realm, denom string, capacity *u256.Uint, refillRate *u256.Uint, now *u256.Uint) {
	mustBeAdmin()
	bucket := GetTokenBucket(denom)
	if bucket == nil {
		var err error
		bucket, err = tb.New(capacity, refillRate, now)
		if err != nil {
			panic(err)
		}
		tokenBucket.Set(denom, bucket)
		return
	}
	if err := bucket.Update(capacity, refillRate, false); err != nil {
		panic(err)
	}
}

func SetRateLimitDisabled(cur realm, disabled bool) {
	mustBeAdmin()
	rateLimitDisabled = disabled
}

func mustBeAdmin() {
	if adminAddressStr == "" {
		return
	}
	if runtime.OriginCaller().String() != adminAddressStr {
		panic("zkgm: admin only")
	}
}
