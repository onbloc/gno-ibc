package core

import (
	"testing"

	"gno.land/p/nt/uassert/v0"
	"gno.land/r/onbloc/ibc/union/access"
)

const (
	testImplPathA = "gno.land/r/onbloc/ibc/union/core/v1"
	testImplPathB = "gno.land/r/onbloc/ibc/union/core/v2"
)

type testInstalledImpl struct {
	ICore
}

func resetImplForTest(cur realm) {
	resetStore(cur)
	currentImpl = nil
	currentImplPath = ""
	implConstructors = make(map[string]func(store IStore) ICore)
}

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
			wantAbort:    "core: previous impl path is not a prefix of the current impl path",
		},
		{
			name:         "registers constructor under previous impl path",
			previousPath: testImplPathA,
		},
		{
			name:          "rejects duplicate impl registration",
			previousPath:  testImplPathA,
			preRegistered: true,
			wantAbort:     "core: impl already registered",
		},
	}

	for _, tc := range cases {
		resetImplForTest(cur)
		if tc.preRegistered {
			implConstructors[tc.previousPath] = func(store IStore) ICore {
				return &testInstalledImpl{}
			}
		}

		if tc.wantAbort != "" {
			uassert.AbortsContains(t, cur, tc.wantAbort, func(cur realm) {
				testing.SetRealm(testing.NewCodeRealm(tc.previousPath))
				RegisterImpl(cross(cur), func(store IStore) ICore {
					return &testInstalledImpl{}
				})
			})
			continue
		}

		testing.SetRealm(testing.NewCodeRealm(tc.previousPath))
		RegisterImpl(cross(cur), func(store IStore) ICore {
			return &testInstalledImpl{}
		})
		if _, ok := implConstructors[tc.previousPath]; !ok {
			t.Fatalf("%s: constructor was not registered under %q", tc.name, tc.previousPath)
		}
	}
}

func TestUpdateImpl(cur realm, t *testing.T) {
	admin := access.DefaultAdminAddress
	nonAdmin := address("g1notadmin")

	cases := []struct {
		name            string
		registerA       bool
		registerB       bool
		caller          address
		path            string
		secondPath      string
		wantAbort       string
		wantPath        string
		wantStoreInject bool
	}{
		{
			name:      "rejects non-admin caller",
			registerA: true,
			caller:    nonAdmin,
			path:      testImplPathA,
			wantAbort: access.ErrorAccessManagerUnauthorizedCall,
		},
		{
			name:      "rejects unregistered path",
			caller:    admin,
			path:      testImplPathA,
			wantAbort: "core: impl constructor not found",
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
			name:            "admin swaps current impl path",
			registerA:       true,
			registerB:       true,
			caller:          admin,
			path:            testImplPathA,
			secondPath:      testImplPathB,
			wantPath:        testImplPathB,
			wantStoreInject: true,
		},
	}

	for _, tc := range cases {
		resetImplForTest(cur)
		firstImpl := &testInstalledImpl{}
		secondImpl := &testInstalledImpl{}
		firstConstructorCalled := false
		secondConstructorCalled := false
		storeInjectedA := false
		storeInjectedB := false
		if tc.registerA {
			implConstructors[testImplPathA] = func(got IStore) ICore {
				firstConstructorCalled = true
				if got == store {
					storeInjectedA = true
				}
				return firstImpl
			}
		}
		if tc.registerB {
			implConstructors[testImplPathB] = func(got IStore) ICore {
				secondConstructorCalled = true
				if got == store {
					storeInjectedB = true
				}
				return secondImpl
			}
		}

		if tc.wantAbort != "" {
			uassert.AbortsContains(t, cur, tc.wantAbort, func(cur realm) {
				testing.SetRealm(testing.NewUserRealm(tc.caller))
				UpdateImpl(cross(cur), tc.path)
			})
			if currentImpl != nil {
				t.Fatalf("%s: rejected UpdateImpl installed an impl", tc.name)
			}
			if currentImplPath != "" {
				t.Fatalf("%s: rejected UpdateImpl changed currentImplPath to %q", tc.name, currentImplPath)
			}
			continue
		}

		testing.SetRealm(testing.NewUserRealm(tc.caller))
		UpdateImpl(cross(cur), tc.path)
		if tc.secondPath != "" {
			UpdateImpl(cross(cur), tc.secondPath)
		}

		if currentImplPath != tc.wantPath {
			t.Fatalf("%s: currentImplPath = %q, want %q", tc.name, currentImplPath, tc.wantPath)
		}
		wantImpl := ICore(firstImpl)
		if tc.secondPath != "" {
			wantImpl = secondImpl
		}
		if currentImpl != wantImpl {
			t.Fatalf("%s: currentImpl did not point at the installed impl", tc.name)
		}
		if got := mustGetImpl(); got != wantImpl {
			t.Fatalf("%s: mustGetImpl returned the wrong impl", tc.name)
		}
		if !firstConstructorCalled {
			t.Fatalf("%s: first constructor was not called", tc.name)
		}
		if tc.secondPath != "" && !secondConstructorCalled {
			t.Fatalf("%s: second constructor was not called", tc.name)
		}
		if tc.wantStoreInject {
			if !storeInjectedA {
				t.Fatalf("%s: first constructor did not receive the proxy store", tc.name)
			}
			if tc.secondPath != "" && !storeInjectedB {
				t.Fatalf("%s: second constructor did not receive the proxy store", tc.name)
			}
		}
	}
}

func TestMustGetImpl(cur realm, t *testing.T) {
	cases := []struct {
		name      string
		impl      ICore
		wantAbort string
	}{
		{
			name:      "missing impl",
			wantAbort: "core: implementation not installed",
		},
		{
			name: "installed impl",
			impl: &testInstalledImpl{},
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			resetImplForTest(cur)
			currentImpl = tc.impl

			if tc.wantAbort != "" {
				uassert.AbortsContains(t, cur, tc.wantAbort, func(cur realm) {
					mustGetImpl()
				})
				return
			}

			if got := mustGetImpl(); got != tc.impl {
				t.Fatal("mustGetImpl returned the wrong impl")
			}
		})
	}
}
