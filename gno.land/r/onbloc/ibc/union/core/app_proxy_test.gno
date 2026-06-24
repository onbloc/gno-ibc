package core

import (
	"testing"

	"gno.land/p/nt/uassert/v0"
	"gno.land/p/onbloc/ibc/union/app"
)

// app_proxy_test.gno covers the public proxy entrypoints in app.gno:
// RegisterApp (impl delegation), RegisterAppForPort (admin gate + store write),
// and HasApp (store read). The channel_auth suite already covers the
// RegisterAppForPort non-admin rejection; here we cover the success/delegation
// paths and HasApp's true/false reporting.

func TestRegisterApp(cur realm, t *testing.T) {
	app1 := &mockApp{}
	app2 := &mockApp{}

	cases := []struct {
		name string
		app  app.IApp
	}{
		{"forwards mock app", app1},
		{"forwards a different app", app2},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			resetStore(cur)
			rec, restore := installRecordingCore()
			defer restore()

			RegisterApp(cross(cur), tc.app)

			uassert.Equal(t, 1, rec.calls["RegisterApp"])
			uassert.True(t, rec.registerApp == tc.app)
		})
	}
}

func TestRegisterApp_RequiresInstalledImpl(cur realm, t *testing.T) {
	resetStore(cur)
	old := currentImpl
	currentImpl = nil
	defer func() { currentImpl = old }()

	uassert.AbortsContains(t, cur, "implementation not installed", func(cur realm) {
		RegisterApp(cross(cur), &mockApp{})
	})
}

func TestRegisterAppForPort_ByAdminRegistersAtExplicitPort(cur realm, t *testing.T) {
	cases := []struct {
		name   string
		portId []byte
	}{
		{"ascii port", []byte("gno.land/r/onbloc/ibc/union/apps/custom")},
		{"binary port", []byte{0x00, 0x01, 0x02}},
		{"single byte port", []byte{0xff}},
	}

	for _, tc := range cases {
		resetStore(cur)
		testing.SetRealm(adminRealm)
		RegisterAppForPort(cross(cur), tc.portId, &mockApp{})

		uassert.True(t, HasApp(tc.portId))
	}
}

func TestRegisterAppForPort_RejectsDuplicatePort(cur realm, t *testing.T) {
	resetStore(cur)

	portId := []byte("gno.land/r/onbloc/ibc/union/apps/dup")
	testing.SetRealm(adminRealm)
	RegisterAppForPort(cross(cur), portId, &mockApp{})

	uassert.AbortsContains(t, cur, "", func(cur realm) {
		testing.SetRealm(adminRealm)
		RegisterAppForPort(cross(cur), portId, &mockApp{})
	})
}

func TestHasApp(cur realm, t *testing.T) {
	registered := []byte("gno.land/r/onbloc/ibc/union/apps/registered")

	cases := []struct {
		name   string
		portId []byte
		want   bool
	}{
		{"registered port", registered, true},
		{"unregistered port", []byte("gno.land/r/onbloc/ibc/union/apps/missing"), false},
		{"empty port", []byte{}, false},
		{"nil port", nil, false},
	}

	resetStore(cur)
	testing.SetRealm(adminRealm)
	RegisterAppForPort(cross(cur), registered, &mockApp{})

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			uassert.Equal(t, tc.want, HasApp(tc.portId))
		})
	}
}
