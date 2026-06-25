package access

import (
	"testing"

	"gno.land/p/nt/testutils/v0"
	"gno.land/p/nt/uassert/v0"
	"gno.land/p/onbloc/access/manager"
)

func TestAssertCanCall(cur realm, t *testing.T) {
	admin := testutils.TestAddress("access-admin")
	caller := testutils.TestAddress("access-caller")
	resetAccess(admin)

	testing.SetRealm(testing.NewUserRealm(admin))
	SetFunctionRole(cross(cur), "set_hook", manager.PublicRole)

	tests := []struct {
		name     string
		setup    func(cur realm)
		selector manager.Selector
		aborts   bool
	}{
		{
			name: "authorized public selector",
			setup: func(cur realm) {
				SetTargetClosed(cross(cur), false)
			},
			selector: "set_hook",
		},
		{
			name: "closed target",
			setup: func(cur realm) {
				SetTargetClosed(cross(cur), true)
			},
			selector: "set_hook",
			aborts:   true,
		},
		{
			name: "admin selector without role",
			setup: func(cur realm) {
				SetTargetClosed(cross(cur), false)
			},
			selector: "grant_role",
			aborts:   true,
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			testing.SetRealm(testing.NewUserRealm(admin))
			tc.setup(cur)

			testing.SetRealm(testing.NewUserRealm(caller))

			if tc.aborts {
				uassert.AbortsContains(t, cur, ErrAccessManagerUnauthorizedCall, func(cur realm) {
					func(cur realm) {
						AssertCanCall(0, cur, tc.selector)
					}(cross(cur))
				})
			} else {
				func(cur realm) {
					AssertCanCall(0, cur, tc.selector)
				}(cross(cur))
			}
		})
	}
}
