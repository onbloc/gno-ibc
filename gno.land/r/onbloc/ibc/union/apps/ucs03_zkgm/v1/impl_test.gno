package impl

// impl_test.gno covers impl.gno's IBC App receiver surface: channel-handshake
// version enforcement and the closed-channel policy. The packet lifecycle
// (OnRecvPacket / OnAcknowledgementPacket / OnTimeoutPacket) is covered by
// dispatch_test and the per-opcode suites; the user-initiated Send drives
// core.SendPacket and is integration-tested in the e2e suite.

import (
	"testing"

	types "gno.land/p/onbloc/ibc/union/types"

	"gno.land/p/nt/uassert/v0"
	zkgm "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm"
)

func TestNewUCS03ZkgmV1(t *testing.T) {
	app := NewUCS03ZkgmV1(testStore)
	v, ok := app.(*ucs03ZkgmV1)

	uassert.True(t, ok)
	uassert.True(t, v.store == testStore)
}

func TestEnforceVersion(cur realm, t *testing.T) {
	cases := []struct {
		name      string
		version   string
		wantPanic bool
	}{
		{"protocol version", zkgm.Version, false},
		{"empty version", "", true},
		{"wrong version", "wrong", true},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			if tc.wantPanic {
				uassert.AbortsContains(t, cur, "unsupported channel version", func(cur realm) {
					enforceVersion(tc.version)
				})
				return
			}

			enforceVersion(tc.version)
		})
	}
}

func TestChannelCallbacks(cur realm, t *testing.T) {
	cases := []struct {
		name      string
		wantAbort string
		call      func(cur realm, app *ucs03ZkgmV1)
	}{
		{
			name:      "open init rejects wrong version",
			wantAbort: "unsupported channel version",
			call: func(cur realm, app *ucs03ZkgmV1) {
				app.OnChannelOpenInit(0, cur, types.ConnectionId(1), types.ChannelId(1), "wrong", address("g1relayer"))
			},
		},
		{
			name: "open init accepts protocol version",
			call: func(cur realm, app *ucs03ZkgmV1) {
				app.OnChannelOpenInit(0, cur, types.ConnectionId(1), types.ChannelId(1), zkgm.Version, address("g1relayer"))
			},
		},
		{
			name:      "open try rejects wrong counterparty version",
			wantAbort: "unsupported channel version",
			call: func(cur realm, app *ucs03ZkgmV1) {
				app.OnChannelOpenTry(0, cur, types.ConnectionId(1), types.ChannelId(1), zkgm.Version, "wrong", address("g1relayer"))
			},
		},
		{
			name:      "open ack rejects wrong counterparty version",
			wantAbort: "unsupported channel version",
			call: func(cur realm, app *ucs03ZkgmV1) {
				app.OnChannelOpenAck(0, cur, types.ChannelId(1), types.ChannelId(2), "wrong", address("g1relayer"))
			},
		},
		{
			name:      "close init is rejected",
			wantAbort: "channel closing is not allowed",
			call: func(cur realm, app *ucs03ZkgmV1) {
				app.OnChannelCloseInit(0, cur, types.ChannelId(1), address("g1relayer"))
			},
		},
		{
			name:      "close confirm is rejected",
			wantAbort: "channel closing is not allowed",
			call: func(cur realm, app *ucs03ZkgmV1) {
				app.OnChannelCloseConfirm(0, cur, types.ChannelId(1), address("g1relayer"))
			},
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			app := newTestImpl()
			if tc.wantAbort != "" {
				uassert.AbortsContains(t, cur, tc.wantAbort, func(cur realm) {
					tc.call(cur, app)
				})
				return
			}

			tc.call(cur, app)
		})
	}
}
