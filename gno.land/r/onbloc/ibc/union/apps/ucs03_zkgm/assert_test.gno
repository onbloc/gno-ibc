package zkgm

import (
	"testing"

	"gno.land/p/nt/uassert/v0"
)

func TestAssertIsCoreRealm(cur realm, t *testing.T) {
	cases := []struct {
		name      string
		caller    string
		wantAbort string
	}{
		{"core caller", coreRealmPath, ""},
		{"non-core caller", "gno.land/r/onbloc/ibc/notcore", ErrNotCoreRealm},
	}

	for _, tc := range cases {
		resetZkgmForTest(cur)
		testing.SetRealm(testing.NewCodeRealm(tc.caller))

		if tc.wantAbort != "" {
			uassert.AbortsContains(t, cur, tc.wantAbort, func(cur realm) {
				assertIsCoreRealm(cross(cur))
			})
			continue
		}

		assertIsCoreRealm(cross(cur))
	}
}

func TestAssertNotPaused(cur realm, t *testing.T) {
	cases := []struct {
		name      string
		paused    bool
		wantAbort string
	}{
		{"unpaused", false, ""},
		{"paused", true, "paused"},
	}

	for _, tc := range cases {
		resetZkgmForTest(cur)
		paused = tc.paused

		if tc.wantAbort != "" {
			uassert.AbortsContains(t, cur, tc.wantAbort, func(cur realm) {
				assertIsNotPaused()
			})
			continue
		}

		assertIsNotPaused()
	}
}
