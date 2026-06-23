package zkgm

import (
	"testing"

	"gno.land/p/nt/uassert/v0"
	core "gno.land/r/onbloc/ibc/union/core"
)

func TestAssertIsAdmin(cur realm, t *testing.T) {
	cases := []struct {
		name      string
		caller    address
		wantAbort string
	}{
		{"admin caller", core.GetAdmin(), ""},
		{"non-admin caller", address("g1notadmin"), "zkgm: admin only"},
	}

	for _, tc := range cases {
		resetZkgmForTest()
		testing.SetRealm(testing.NewUserRealm(tc.caller))

		if tc.wantAbort != "" {
			uassert.AbortsContains(t, cur, tc.wantAbort, func(cur realm) {
				assertIsAdmin(cross(cur))
			})
			continue
		}

		assertIsAdmin(cross(cur))
	}
}

func TestAssertIsIBCHost(cur realm, t *testing.T) {
	cases := []struct {
		name      string
		caller    string
		wantAbort string
	}{
		{"core caller", coreRealmPath, ""},
		{"non-core caller", "gno.land/r/onbloc/ibc/notcore", "zkgm: ibc host only"},
	}

	for _, tc := range cases {
		resetZkgmForTest()
		testing.SetRealm(testing.NewCodeRealm(tc.caller))

		if tc.wantAbort != "" {
			uassert.AbortsContains(t, cur, tc.wantAbort, func(cur realm) {
				assertIsIBCHost(cross(cur))
			})
			continue
		}

		assertIsIBCHost(cross(cur))
	}
}

func TestAssertNotPaused(cur realm, t *testing.T) {
	cases := []struct {
		name      string
		paused    bool
		wantAbort string
	}{
		{"unpaused", false, ""},
		{"paused", true, "zkgm: paused"},
	}

	for _, tc := range cases {
		resetZkgmForTest()
		paused = tc.paused

		if tc.wantAbort != "" {
			uassert.AbortsContains(t, cur, tc.wantAbort, func(cur realm) {
				assertNotPaused()
			})
			continue
		}

		assertNotPaused()
	}
}
