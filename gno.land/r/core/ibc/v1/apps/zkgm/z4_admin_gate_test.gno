package zkgm

import (
	"testing"

	u256 "gno.land/p/gnoswap/uint256"
	"gno.land/p/nt/uassert/v0"
	core "gno.land/r/onbloc/unionibc/v1/core"
)

func TestPauseRejectsNonAdmin(cur realm, t *testing.T) {
	resetZkgmForTest()

	uassert.AbortsContains(t, cur, "zkgm: admin only", func(cur realm) {
		Pause(cross(cur))
	})
	if paused {
		t.Error("rejected Pause must not set paused=true")
	}
}

func TestPauseSucceedsByAdmin(cur realm, t *testing.T) {
	resetZkgmForTest()

	testing.SetRealm(testing.NewUserRealm(core.GetAdmin()))
	Pause(cur)

	if !paused {
		t.Error("Pause by admin must set paused=true")
	}
}

func TestUnpauseRejectsNonAdmin(cur realm, t *testing.T) {
	resetZkgmForTest()
	paused = true

	uassert.AbortsContains(t, cur, "zkgm: admin only", func(cur realm) {
		Unpause(cross(cur))
	})
	if !paused {
		t.Error("rejected Unpause must not set paused=false")
	}
}

func TestUnpauseSucceedsByAdmin(cur realm, t *testing.T) {
	resetZkgmForTest()
	paused = true

	testing.SetRealm(testing.NewUserRealm(core.GetAdmin()))
	Unpause(cur)

	if paused {
		t.Error("Unpause by admin must set paused=false")
	}
}

func TestSetBucketConfigRejectsNonAdmin(cur realm, t *testing.T) {
	resetZkgmForTest()

	uassert.AbortsContains(t, cur, "zkgm: admin only", func(cur realm) {
		SetBucketConfig(cross(cur), "ugnot", u256.NewUint(100), u256.NewUint(10))
	})
	if GetTokenBucket("ugnot") != nil {
		t.Error("rejected SetBucketConfig must not create a bucket")
	}
}

func TestSetBucketConfigSucceedsByAdmin(cur realm, t *testing.T) {
	resetZkgmForTest()

	testing.SetRealm(testing.NewUserRealm(core.GetAdmin()))
	SetBucketConfig(cur, "ugnot-admin", u256.NewUint(100), u256.NewUint(10))

	if GetTokenBucket("ugnot-admin") == nil {
		t.Error("SetBucketConfig by admin must create a bucket")
	}
}

func TestSetRateLimitDisabledRejectsNonAdmin(cur realm, t *testing.T) {
	resetZkgmForTest()

	uassert.AbortsContains(t, cur, "zkgm: admin only", func(cur realm) {
		SetRateLimitDisabled(cross(cur), true)
	})
	if rateLimitDisabled {
		t.Error("rejected SetRateLimitDisabled must not toggle the kill-switch")
	}
}

func TestSetRateLimitDisabledSucceedsByAdmin(cur realm, t *testing.T) {
	resetZkgmForTest()

	testing.SetRealm(testing.NewUserRealm(core.GetAdmin()))
	SetRateLimitDisabled(cur, true)

	if !rateLimitDisabled {
		t.Error("SetRateLimitDisabled by admin must set rateLimitDisabled=true")
	}
}
