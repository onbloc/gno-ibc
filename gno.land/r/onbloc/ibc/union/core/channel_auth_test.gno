package core

import (
	"testing"

	"gno.land/p/nt/testutils/v0"
	"gno.land/p/nt/uassert/v0"
	"gno.land/p/onbloc/ibc/union/types"
)

func setNonAdminForTest() func() {
	oldAdmin := admin
	admin = testutils.TestAddress("authorized-admin")
	return func() {
		admin = oldAdmin
	}
}

func TestChannelAdminEntrypointsRejectNonAdmin(cur realm, t *testing.T) {
	cases := []struct {
		name string
		run  func(realm)
	}{
		{
			name: "ChannelOpenInit",
			run: func(cur realm) {
				ChannelOpenInit(cur, types.NewMsgChannelOpenInit(nil, nil, 1, "ics20-1", "g1msgrelayer"))
			},
		},
		{
			name: "ChannelOpenTry",
			run: func(cur realm) {
				ChannelOpenTry(cur, types.MsgChannelOpenTry{})
			},
		},
		{
			name: "ForceChannelOpenTry",
			run: func(cur realm) {
				ForceChannelOpenTry(cur, types.MsgChannelOpenTry{})
			},
		},
		{
			name: "ChannelOpenAck",
			run: func(cur realm) {
				ChannelOpenAck(cur, types.MsgChannelOpenAck{})
			},
		},
		{
			name: "ForceChannelOpenAck",
			run: func(cur realm) {
				ForceChannelOpenAck(cur, types.MsgChannelOpenAck{})
			},
		},
		{
			name: "ChannelOpenConfirm",
			run: func(cur realm) {
				ChannelOpenConfirm(cur, types.MsgChannelOpenConfirm{})
			},
		},
		{
			name: "ForceChannelOpenConfirm",
			run: func(cur realm) {
				ForceChannelOpenConfirm(cur, types.MsgChannelOpenConfirm{})
			},
		},
		{
			name: "ChannelCloseInit",
			run: func(cur realm) {
				ChannelCloseInit(cur, types.MsgChannelCloseInit{})
			},
		},
		{
			name: "ChannelCloseConfirm",
			run: func(cur realm) {
				ChannelCloseConfirm(cur, types.MsgChannelCloseConfirm{})
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
