package zkgm

import (
	"testing"

	"gno.land/p/nt/uassert/v0"
)

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
		resetZkgmForTest(cur)
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
		resetZkgmForTest(cur)
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
