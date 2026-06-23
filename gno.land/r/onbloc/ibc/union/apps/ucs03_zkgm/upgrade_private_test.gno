package zkgm

import (
	"testing"

	"gno.land/p/nt/uassert/v0"
	types "gno.land/p/onbloc/ibc/union/types"
)

func TestRegisterImpl(cur realm, t *testing.T) {
	resetZkgmForTest()

	uassert.AbortsContains(t, cur, "zkgm: previous impl path is not a prefix of the current impl path", func(cur realm) {
		RegisterImpl(cross(cur), func(store IStore) IApp { return &dummyImpl{} })
	})
}

func TestMustGetImpl(cur realm, t *testing.T) {
	cases := []struct {
		name      string
		install   bool
		wantAbort string
	}{
		{"missing impl", false, "zkgm: implementation not installed"},
		{"installed impl", true, ""},
	}

	for _, tc := range cases {
		resetZkgmForTest()
		d := &dummyImpl{}
		if tc.install {
			currentImpl = d
		}

		if tc.wantAbort != "" {
			uassert.AbortsContains(t, cur, tc.wantAbort, func(cur realm) {
				mustGetImpl()
			})
			continue
		}

		impl := mustGetImpl()
		if impl == nil {
			t.Fatal("mustGetImpl returned nil after install")
		}
		impl.OnTimeoutPacket(0, cur, types.Packet{}, address("g1relayer"))
		if !d.timeoutCalled {
			t.Fatal("mustGetImpl must return the installed impl")
		}
	}
}
