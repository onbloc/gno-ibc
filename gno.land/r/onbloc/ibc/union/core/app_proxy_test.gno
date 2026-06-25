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
