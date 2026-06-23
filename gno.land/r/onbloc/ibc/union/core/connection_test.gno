package core

import (
	"testing"

	"gno.land/p/nt/uassert/v0"
	"gno.land/p/onbloc/access/manager"
	"gno.land/p/onbloc/ibc/union/types"
)

func TestConnectionOpenPanicsWhenCallerIsNotAdmin(cur realm, t *testing.T) {
	cases := []struct {
		name     string
		selector manager.Selector
		run      func(realm)
	}{
		{
			name:     "ConnectionOpenInit",
			selector: SelectorConnectionOpenInit,
			run: func(cur realm) {
				ConnectionOpenInit(cur, types.NewMsgConnectionOpenInit(types.ClientId(1), types.ClientId(99)))
			},
		},
		{
			name:     "ConnectionOpenTry",
			selector: SelectorConnectionOpenTry,
			run: func(cur realm) {
				ConnectionOpenTry(cur, types.NewMsgConnectionOpenTry(
					types.ClientId(1),
					types.ClientId(99),
					types.ConnectionId(77),
					nil,
					10,
				))
			},
		},
		{
			name:     "ConnectionOpenAck",
			selector: SelectorConnectionOpenAck,
			run: func(cur realm) {
				ConnectionOpenAck(cur, types.NewMsgConnectionOpenAck(
					types.ConnectionId(1),
					types.ConnectionId(77),
					nil,
					10,
				))
			},
		},
		{
			name:     "ConnectionOpenConfirm",
			selector: SelectorConnectionOpenConfirm,
			run: func(cur realm) {
				ConnectionOpenConfirm(cur, types.NewMsgConnectionOpenConfirm(types.ConnectionId(1), nil, 10))
			},
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			resetStore(cur)
			requireSelectorProtectedForTest(cur, tc.selector)

			uassert.AbortsContains(t, cur, accessManagerUnauthorizedCallError, func(cur realm) {
				tc.run(cross(cur))
			})
		})
	}
}

// The Force* proof-bypass behavior is covered by the v1 implementation tests
// (core/v1/connection_test.gno). The proxy only keeps the admin gate.
func TestForceConnectionOpenPanicsWhenCallerIsNotAdmin(cur realm, t *testing.T) {
	cases := []struct {
		name     string
		selector manager.Selector
		run      func(realm)
	}{
		{
			name:     "ForceConnectionOpenTry",
			selector: SelectorForceConnectionTry,
			run: func(cur realm) {
				ForceConnectionOpenTry(cur, types.NewMsgConnectionOpenTry(
					types.ClientId(1),
					types.ClientId(99),
					types.ConnectionId(77),
					nil,
					10,
				))
			},
		},
		{
			name:     "ForceConnectionOpenAck",
			selector: SelectorForceConnectionAck,
			run: func(cur realm) {
				ForceConnectionOpenAck(cur, types.NewMsgConnectionOpenAck(
					types.ConnectionId(1),
					types.ConnectionId(77),
					nil,
					10,
				))
			},
		},
		{
			name:     "ForceConnectionOpenConfirm",
			selector: SelectorForceConnectionConfirm,
			run: func(cur realm) {
				ForceConnectionOpenConfirm(cur, types.NewMsgConnectionOpenConfirm(types.ConnectionId(1), nil, 10))
			},
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			resetStore(cur)
			requireSelectorProtectedForTest(cur, tc.selector)

			uassert.AbortsContains(t, cur, accessManagerUnauthorizedCallError, func(cur realm) {
				tc.run(cross(cur))
			})
		})
	}
}
