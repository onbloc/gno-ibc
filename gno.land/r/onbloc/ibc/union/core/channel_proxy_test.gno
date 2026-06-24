package core

import (
	"testing"

	"gno.land/p/nt/uassert/v0"
	"gno.land/p/onbloc/ibc/union/types"
	"gno.land/r/onbloc/ibc/union/access"
)

// channel_proxy_test.gno covers delegation for the channel handshake entrypoints
// in channel.gno. The non-admin/non-relayer rejection paths are already covered
// by channel_auth_test.gno; here we assert each entrypoint forwards its message
// to mustGetImpl() once the caller is authorized.
//
// testing.SetRealm only affects the frame it is called in, so each gated
// entrypoint is invoked inline in the test-body frame (never through a func
// value), with the authorizing SetRealm immediately preceding it.
//
// Gate classes:
//   - relayer-gated: ChannelOpenInit, ChannelOpenTry, ChannelOpenAck, ChannelOpenConfirm
//   - admin-gated:   ForceChannelOpenTry, ForceChannelOpenAck, ForceChannelOpenConfirm,
//                    ChannelCloseInit, ChannelCloseConfirm

func TestChannelOpenInit(cur realm, t *testing.T) {
	cases := []struct {
		name         string
		connectionId types.ConnectionId
		version      string
	}{
		{"typical", 1, "ics20-1"},
		{"zero connection", 0, ""},
	}

	for _, tc := range cases {
		resetStore(cur)
		rec, restore := installRecordingCore()

		testing.SetRealm(adminRealm)
		access.GrantRole(cross(cur), RelayerRole, testRelayer)
		testing.SetRealm(relayerRealm)
		ChannelOpenInit(cross(cur), types.MsgChannelOpenInit{ConnectionId: tc.connectionId, Version: tc.version})
		testing.SetRealm(adminRealm)
		access.RevokeRole(cross(cur), RelayerRole, testRelayer)

		uassert.Equal(t, 1, rec.calls["ChannelOpenInit"])
		uassert.Equal(t, uint64(tc.connectionId), uint64(rec.chanOpenInitMsg.ConnectionId))
		uassert.Equal(t, tc.version, rec.chanOpenInitMsg.Version)

		restore()
	}
}

func TestChannelOpenTry(cur realm, t *testing.T) {
	cases := []struct {
		name                string
		counterpartyVersion string
	}{
		{"with counterparty version", "ics20-1"},
		{"empty counterparty version", ""},
	}

	for _, tc := range cases {
		resetStore(cur)
		rec, restore := installRecordingCore()

		testing.SetRealm(adminRealm)
		access.GrantRole(cross(cur), RelayerRole, testRelayer)
		testing.SetRealm(relayerRealm)
		ChannelOpenTry(cross(cur), types.MsgChannelOpenTry{CounterpartyVersion: tc.counterpartyVersion})
		testing.SetRealm(adminRealm)
		access.RevokeRole(cross(cur), RelayerRole, testRelayer)

		uassert.Equal(t, 1, rec.calls["ChannelOpenTry"])
		uassert.Equal(t, tc.counterpartyVersion, rec.chanOpenTryMsg.CounterpartyVersion)

		restore()
	}
}

func TestChannelOpenAck(cur realm, t *testing.T) {
	cases := []struct {
		name                  string
		channelId             types.ChannelId
		counterpartyChannelId types.ChannelId
	}{
		{"typical", 4, 9},
		{"zero ids", 0, 0},
	}

	for _, tc := range cases {
		resetStore(cur)
		rec, restore := installRecordingCore()

		testing.SetRealm(adminRealm)
		access.GrantRole(cross(cur), RelayerRole, testRelayer)
		testing.SetRealm(relayerRealm)
		ChannelOpenAck(cross(cur), types.MsgChannelOpenAck{ChannelId: tc.channelId, CounterpartyChannelId: tc.counterpartyChannelId})
		testing.SetRealm(adminRealm)
		access.RevokeRole(cross(cur), RelayerRole, testRelayer)

		uassert.Equal(t, 1, rec.calls["ChannelOpenAck"])
		uassert.Equal(t, uint64(tc.channelId), uint64(rec.chanOpenAckMsg.ChannelId))
		uassert.Equal(t, uint64(tc.counterpartyChannelId), uint64(rec.chanOpenAckMsg.CounterpartyChannelId))

		restore()
	}
}

func TestChannelOpenConfirm(cur realm, t *testing.T) {
	cases := []struct {
		name      string
		channelId types.ChannelId
	}{
		{"typical", 6},
		{"zero id", 0},
	}

	for _, tc := range cases {
		resetStore(cur)
		rec, restore := installRecordingCore()

		testing.SetRealm(adminRealm)
		access.GrantRole(cross(cur), RelayerRole, testRelayer)
		testing.SetRealm(relayerRealm)
		ChannelOpenConfirm(cross(cur), types.MsgChannelOpenConfirm{ChannelId: tc.channelId})
		testing.SetRealm(adminRealm)
		access.RevokeRole(cross(cur), RelayerRole, testRelayer)

		uassert.Equal(t, 1, rec.calls["ChannelOpenConfirm"])
		uassert.Equal(t, uint64(tc.channelId), uint64(rec.chanOpenConfirmMsg.ChannelId))

		restore()
	}
}

func TestForceChannelOpenTry(cur realm, t *testing.T) {
	cases := []struct {
		name                string
		counterpartyVersion string
	}{
		{"with counterparty version", "ics20-1"},
		{"empty", ""},
	}

	for _, tc := range cases {
		resetStore(cur)
		rec, restore := installRecordingCore()

		testing.SetRealm(adminRealm)
		ForceChannelOpenTry(cross(cur), types.MsgChannelOpenTry{CounterpartyVersion: tc.counterpartyVersion})

		uassert.Equal(t, 1, rec.calls["ForceChannelOpenTry"])
		uassert.Equal(t, tc.counterpartyVersion, rec.forceChanTryMsg.CounterpartyVersion)

		restore()
	}
}

func TestForceChannelOpenAck(cur realm, t *testing.T) {
	cases := []struct {
		name      string
		channelId types.ChannelId
	}{
		{"typical", 11},
		{"zero id", 0},
	}

	for _, tc := range cases {
		resetStore(cur)
		rec, restore := installRecordingCore()

		testing.SetRealm(adminRealm)
		ForceChannelOpenAck(cross(cur), types.MsgChannelOpenAck{ChannelId: tc.channelId})

		uassert.Equal(t, 1, rec.calls["ForceChannelOpenAck"])
		uassert.Equal(t, uint64(tc.channelId), uint64(rec.forceChanAckMsg.ChannelId))

		restore()
	}
}

func TestForceChannelOpenConfirm(cur realm, t *testing.T) {
	cases := []struct {
		name      string
		channelId types.ChannelId
	}{
		{"typical", 12},
		{"zero id", 0},
	}

	for _, tc := range cases {
		resetStore(cur)
		rec, restore := installRecordingCore()

		testing.SetRealm(adminRealm)
		ForceChannelOpenConfirm(cross(cur), types.MsgChannelOpenConfirm{ChannelId: tc.channelId})

		uassert.Equal(t, 1, rec.calls["ForceChannelOpenConfirm"])
		uassert.Equal(t, uint64(tc.channelId), uint64(rec.forceChanConfirmMsg.ChannelId))

		restore()
	}
}

func TestChannelCloseInit(cur realm, t *testing.T) {
	cases := []struct {
		name      string
		channelId types.ChannelId
	}{
		{"typical", 13},
		{"zero id", 0},
	}

	for _, tc := range cases {
		resetStore(cur)
		rec, restore := installRecordingCore()

		testing.SetRealm(adminRealm)
		ChannelCloseInit(cross(cur), types.MsgChannelCloseInit{ChannelId: tc.channelId, Relayer: "r"})

		uassert.Equal(t, 1, rec.calls["ChannelCloseInit"])
		uassert.Equal(t, uint64(tc.channelId), uint64(rec.chanCloseInitMsg.ChannelId))

		restore()
	}
}

func TestChannelCloseConfirm(cur realm, t *testing.T) {
	cases := []struct {
		name      string
		channelId types.ChannelId
	}{
		{"typical", 14},
		{"zero id", 0},
	}

	for _, tc := range cases {
		resetStore(cur)
		rec, restore := installRecordingCore()

		testing.SetRealm(adminRealm)
		ChannelCloseConfirm(cross(cur), types.MsgChannelCloseConfirm{ChannelId: tc.channelId})

		uassert.Equal(t, 1, rec.calls["ChannelCloseConfirm"])
		uassert.Equal(t, uint64(tc.channelId), uint64(rec.chanCloseConfirmMsg.ChannelId))

		restore()
	}
}
