package core

import (
	"testing"

	"gno.land/p/nt/uassert/v0"
	"gno.land/p/onbloc/access/manager"
	"gno.land/p/onbloc/ibc/union/types"
	"gno.land/r/onbloc/ibc/union/access"
)

const accessManagerUnauthorizedCallError = access.ErrAccessManagerUnauthorizedCall

func TestChannelAdminEntrypointsRejectNonAdmin(cur realm, t *testing.T) {
	cases := []struct {
		name     string
		selector manager.Selector
		run      func(realm)
	}{
		{
			name:     "ChannelOpenInit",
			selector: SelectorChannelOpenInit,
			run: func(cur realm) {
				ChannelOpenInit(cur, types.NewMsgChannelOpenInit(nil, nil, 1, "ics20-1", "g1msgrelayer"))
			},
		},
		{
			name:     "ChannelOpenTry",
			selector: SelectorChannelOpenTry,
			run: func(cur realm) {
				ChannelOpenTry(cur, types.MsgChannelOpenTry{})
			},
		},
		{
			name:     "ForceChannelOpenTry",
			selector: SelectorForceChannelTry,
			run: func(cur realm) {
				ForceChannelOpenTry(cur, types.MsgChannelOpenTry{})
			},
		},
		{
			name:     "ChannelOpenAck",
			selector: SelectorChannelOpenAck,
			run: func(cur realm) {
				ChannelOpenAck(cur, types.MsgChannelOpenAck{})
			},
		},
		{
			name:     "ForceChannelOpenAck",
			selector: SelectorForceChannelAck,
			run: func(cur realm) {
				ForceChannelOpenAck(cur, types.MsgChannelOpenAck{})
			},
		},
		{
			name:     "ChannelOpenConfirm",
			selector: SelectorChannelOpenConfirm,
			run: func(cur realm) {
				ChannelOpenConfirm(cur, types.MsgChannelOpenConfirm{})
			},
		},
		{
			name:     "ForceChannelOpenConfirm",
			selector: SelectorForceChannelConfirm,
			run: func(cur realm) {
				ForceChannelOpenConfirm(cur, types.MsgChannelOpenConfirm{})
			},
		},
		{
			name:     "ChannelCloseInit",
			selector: SelectorChannelCloseInit,
			run: func(cur realm) {
				ChannelCloseInit(cur, types.MsgChannelCloseInit{})
			},
		},
		{
			name:     "ChannelCloseConfirm",
			selector: SelectorChannelCloseConfirm,
			run: func(cur realm) {
				ChannelCloseConfirm(cur, types.MsgChannelCloseConfirm{})
			},
		},
		{
			name:     "RegisterAppForPort",
			selector: SelectorRegisterPort,
			run: func(cur realm) {
				RegisterAppForPort(cur, []byte("explicit-port"), &mockApp{})
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
