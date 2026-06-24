package zkgm

import (
	"testing"

	"gno.land/p/nt/uassert/v0"
	"gno.land/p/onbloc/ibc/union/types"
)

func TestAssertIsIBCHost(cur realm, t *testing.T) {
	cases := []struct {
		name      string
		caller    string
		wantAbort string
	}{
		{"core caller", coreRealmPath, ""},
		{"non-core caller", "gno.land/r/onbloc/ibc/notcore", "ibc host only"},
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

func TestEmitRecvErrorRejectsNonProxyRealm(cur realm, t *testing.T) {
	uassert.AbortsContains(t, cur, ErrNotProxyRealm, func(cur realm) {
		testing.SetRealm(testing.NewCodeRealm(proxyPkgPath + "/v1"))
		EmitRecvError(0, cur, types.ChannelId(1), types.ChannelId(2), "test")
	})
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
