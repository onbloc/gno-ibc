package ucs03_zkgm

import (
	"testing"

	"gno.land/p/nt/uassert/v0"
	types "gno.land/p/onbloc/ibc/union/types"
	"gno.land/r/onbloc/ibc/union/access"
	core "gno.land/r/onbloc/ibc/union/core"
)

const (
	testImplPathA = "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/v1"
	testImplPathB = "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/v2"
)

// upgrade_test covers upgrade.gno's swap model. An impl realm registers its
// constructor under its own package path via RegisterImpl; the admin later
// activates a registered path via UpdateImpl, which injects the proxy store and
// builds the active impl. The model rejects non-admin callers and unregistered
// paths.

func TestRegisterImpl(cur realm, t *testing.T) {
	cases := []struct {
		name          string
		previousPath  string
		preRegistered bool
		wantAbort     string
	}{
		{
			name:         "rejects previous realm outside proxy namespace",
			previousPath: "gno.land/r/outside/impl",
			wantAbort:    "previous impl path is not a prefix of the current impl path",
		},
		{
			name:         "registers constructor under previous impl path",
			previousPath: testImplPathA,
		},
		{
			name:          "rejects duplicate impl registration",
			previousPath:  testImplPathA,
			preRegistered: true,
			wantAbort:     "impl already registered",
		},
	}

	for _, tc := range cases {
		resetZkgmForTest(cur)
		if tc.preRegistered {
			implConstructors[tc.previousPath] = func(store IStore) IApp { return &dummyImpl{} }
		}

		if tc.wantAbort != "" {
			uassert.AbortsContains(t, cur, tc.wantAbort, func(cur realm) {
				testing.SetRealm(testing.NewCodeRealm(tc.previousPath))
				RegisterImpl(cross(cur), func(store IStore) IApp { return &dummyImpl{} })
			})
			continue
		}

		testing.SetRealm(testing.NewCodeRealm(tc.previousPath))
		RegisterImpl(cross(cur), func(store IStore) IApp { return &dummyImpl{} })
		if _, ok := implConstructors[tc.previousPath]; !ok {
			t.Errorf("%s: constructor was not registered under previous impl path", tc.name)
		}
	}
}

func TestUpdateImpl(cur realm, t *testing.T) {
	admin := access.DefaultAdminAddress
	nonAdmin := address("g1notadmin")

	cases := []struct {
		name             string
		registerA        bool
		registerB        bool
		caller           address
		path             string
		secondPath       string
		wantAbort        string
		wantPath         string
		wantStoreInject  bool
		driveRecv        bool
		wantLatestCalled bool
	}{
		{
			name:      "rejects non-admin caller",
			registerA: true,
			caller:    nonAdmin,
			path:      testImplPathA,
			wantAbort: access.ErrAccessManagerUnauthorizedCall,
		},
		{
			name:      "rejects unregistered path",
			caller:    admin,
			path:      testImplPathA,
			wantAbort: "impl constructor not found",
		},
		{
			name:            "admin installs registered impl",
			registerA:       true,
			caller:          admin,
			path:            testImplPathA,
			wantPath:        testImplPathA,
			wantStoreInject: true,
		},
		{
			name:             "admin swaps to latest target",
			registerA:        true,
			registerB:        true,
			caller:           admin,
			path:             testImplPathA,
			secondPath:       testImplPathB,
			wantPath:         testImplPathB,
			driveRecv:        true,
			wantLatestCalled: true,
		},
	}

	for _, tc := range cases {
		resetZkgmForTest(cur)
		first := &dummyImpl{}
		second := &dummyImpl{}
		storeInjected := false
		if tc.registerA {
			implConstructors[testImplPathA] = func(got IStore) IApp {
				if got == store {
					storeInjected = true
				}
				return first
			}
		}
		if tc.registerB {
			implConstructors[testImplPathB] = func(store IStore) IApp { return second }
		}

		if tc.wantAbort != "" {
			// Set the caller realm inside the abort closure so cur.Previous()
			// resolves to the intended user realm before UpdateImpl checks it.
			uassert.AbortsContains(t, cur, tc.wantAbort, func(cur realm) {
				testing.SetRealm(testing.NewUserRealm(tc.caller))
				UpdateImpl(cross(cur), tc.path)
			})
			if currentImpl != nil {
				t.Errorf("%s: rejected UpdateImpl must not install an impl", tc.name)
			}
			continue
		}

		testing.SetRealm(testing.NewUserRealm(tc.caller))
		UpdateImpl(cross(cur), tc.path)
		if tc.secondPath != "" {
			UpdateImpl(cross(cur), tc.secondPath)
		}

		if currentImpl == nil {
			t.Errorf("%s: UpdateImpl by admin must install the impl", tc.name)
		}
		if currentImplPath != tc.wantPath {
			t.Errorf("%s: currentImplPath = %q, want %q", tc.name, currentImplPath, tc.wantPath)
		}
		if tc.wantStoreInject && !storeInjected {
			t.Errorf("%s: constructor did not receive the proxy store", tc.name)
		}

		if tc.driveRecv {
			packet := core.NewPacket(1, 2, []byte("d"), 0)
			// Drive a packet through the proxy; only the latest impl must receive it.
			testing.SetRealm(testing.NewCodeRealm(coreRealmPath))
			(&App{}).OnRecvPacket(cross(cur), packet, address("g1relayer"), nil)

			if first.recvCalled {
				t.Errorf("%s: displaced impl must not receive packets", tc.name)
			}
			if second.recvCalled != tc.wantLatestCalled {
				t.Errorf("%s: latest impl recvCalled = %v, want %v", tc.name, second.recvCalled, tc.wantLatestCalled)
			}
		}
	}
}

func TestMustGetImpl(cur realm, t *testing.T) {
	cases := []struct {
		name      string
		install   bool
		wantAbort string
	}{
		{"missing impl", false, "implementation not installed"},
		{"installed impl", true, ""},
	}

	for _, tc := range cases {
		resetZkgmForTest(cur)
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
