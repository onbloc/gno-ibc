package core

import (
	"testing"

	"gno.land/p/nt/uassert/v0"
	"gno.land/p/onbloc/ibc/union/types"
)

func TestConnectionOpenPanicsWhenCallerIsNotAdmin(cur realm, t *testing.T) {
	cases := []struct {
		name string
		run  func(realm)
	}{
		{
			name: "ConnectionOpenInit",
			run: func(cur realm) {
				ConnectionOpenInit(cur, types.NewMsgConnectionOpenInit(types.ClientId(1), types.ClientId(99)))
			},
		},
		{
			name: "ConnectionOpenTry",
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
			name: "ConnectionOpenAck",
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
			name: "ConnectionOpenConfirm",
			run: func(cur realm) {
				ConnectionOpenConfirm(cur, types.NewMsgConnectionOpenConfirm(types.ConnectionId(1), nil, 10))
			},
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			resetStore(cur)
			cleanup := setNonAdminForTest()
			defer cleanup()

			uassert.AbortsContains(t, cur, "unauthorized", tc.run)
		})
	}
}

// The Force* proof-bypass behavior is covered by the v1 implementation tests
// (core/v1/connection_test.gno). The proxy only keeps the admin gate.
func TestForceConnectionOpenPanicsWhenCallerIsNotAdmin(cur realm, t *testing.T) {
	cases := []struct {
		name string
		run  func(realm)
	}{
		{
			name: "ForceConnectionOpenTry",
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
			name: "ForceConnectionOpenAck",
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
			name: "ForceConnectionOpenConfirm",
			run: func(cur realm) {
				ForceConnectionOpenConfirm(cur, types.NewMsgConnectionOpenConfirm(types.ConnectionId(1), nil, 10))
			},
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			resetStore(cur)
			cleanup := setNonAdminForTest()
			defer cleanup()

			uassert.AbortsContains(t, cur, "unauthorized", tc.run)
		})
	}
}
