package core

import (
	"testing"

	"gno.land/p/nt/uassert/v0"
	"gno.land/p/onbloc/ibc/union/types"
	"gno.land/r/onbloc/ibc/union/access"
)

// connection_proxy_test.gno covers delegation for the connection handshake
// entrypoints in connection.gno. Non-admin/non-relayer rejection is covered by
// connection_test.gno; here we assert each authorized call forwards its message
// to mustGetImpl().
//
// Gate classes:
//   - relayer-gated: ConnectionOpenInit, ConnectionOpenTry, ConnectionOpenAck, ConnectionOpenConfirm
//   - admin-gated:   ForceConnectionOpenTry, ForceConnectionOpenAck, ForceConnectionOpenConfirm

func TestConnectionOpenInit(cur realm, t *testing.T) {
	cases := []struct {
		name                 string
		clientId             types.ClientId
		counterpartyClientId types.ClientId
	}{
		{"typical", 1, 2},
		{"zero ids", 0, 0},
	}

	for _, tc := range cases {
		resetStore(cur)
		rec, restore := installRecordingCore()

		testing.SetRealm(adminRealm)
		access.GrantRole(cross(cur), RelayerRole, testRelayer)
		testing.SetRealm(relayerRealm)
		ConnectionOpenInit(cross(cur), types.MsgConnectionOpenInit{ClientId: tc.clientId, CounterpartyClientId: tc.counterpartyClientId})
		testing.SetRealm(adminRealm)
		access.RevokeRole(cross(cur), RelayerRole, testRelayer)

		uassert.Equal(t, 1, rec.calls["ConnectionOpenInit"])
		uassert.Equal(t, uint64(tc.clientId), uint64(rec.connOpenInitMsg.ClientId))
		uassert.Equal(t, uint64(tc.counterpartyClientId), uint64(rec.connOpenInitMsg.CounterpartyClientId))

		restore()
	}
}

func TestConnectionOpenTry(cur realm, t *testing.T) {
	cases := []struct {
		name                     string
		clientId                 types.ClientId
		counterpartyConnectionId types.ConnectionId
	}{
		{"typical", 3, 7},
		{"zero ids", 0, 0},
	}

	for _, tc := range cases {
		resetStore(cur)
		rec, restore := installRecordingCore()

		testing.SetRealm(adminRealm)
		access.GrantRole(cross(cur), RelayerRole, testRelayer)
		testing.SetRealm(relayerRealm)
		ConnectionOpenTry(cross(cur), types.MsgConnectionOpenTry{ClientId: tc.clientId, CounterpartyConnectionId: tc.counterpartyConnectionId})
		testing.SetRealm(adminRealm)
		access.RevokeRole(cross(cur), RelayerRole, testRelayer)

		uassert.Equal(t, 1, rec.calls["ConnectionOpenTry"])
		uassert.Equal(t, uint64(tc.clientId), uint64(rec.connOpenTryMsg.ClientId))
		uassert.Equal(t, uint64(tc.counterpartyConnectionId), uint64(rec.connOpenTryMsg.CounterpartyConnectionId))

		restore()
	}
}

func TestConnectionOpenAck(cur realm, t *testing.T) {
	cases := []struct {
		name                     string
		connectionId             types.ConnectionId
		counterpartyConnectionId types.ConnectionId
	}{
		{"typical", 5, 8},
		{"zero ids", 0, 0},
	}

	for _, tc := range cases {
		resetStore(cur)
		rec, restore := installRecordingCore()

		testing.SetRealm(adminRealm)
		access.GrantRole(cross(cur), RelayerRole, testRelayer)
		testing.SetRealm(relayerRealm)
		ConnectionOpenAck(cross(cur), types.MsgConnectionOpenAck{ConnectionId: tc.connectionId, CounterpartyConnectionId: tc.counterpartyConnectionId})
		testing.SetRealm(adminRealm)
		access.RevokeRole(cross(cur), RelayerRole, testRelayer)

		uassert.Equal(t, 1, rec.calls["ConnectionOpenAck"])
		uassert.Equal(t, uint64(tc.connectionId), uint64(rec.connOpenAckMsg.ConnectionId))
		uassert.Equal(t, uint64(tc.counterpartyConnectionId), uint64(rec.connOpenAckMsg.CounterpartyConnectionId))

		restore()
	}
}

func TestConnectionOpenConfirm(cur realm, t *testing.T) {
	cases := []struct {
		name         string
		connectionId types.ConnectionId
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
		ConnectionOpenConfirm(cross(cur), types.MsgConnectionOpenConfirm{ConnectionId: tc.connectionId})
		testing.SetRealm(adminRealm)
		access.RevokeRole(cross(cur), RelayerRole, testRelayer)

		uassert.Equal(t, 1, rec.calls["ConnectionOpenConfirm"])
		uassert.Equal(t, uint64(tc.connectionId), uint64(rec.connOpenConfirmMsg.ConnectionId))

		restore()
	}
}

func TestForceConnectionOpenTry(cur realm, t *testing.T) {
	cases := []struct {
		name     string
		clientId types.ClientId
	}{
		{"typical", 3},
		{"zero id", 0},
	}

	for _, tc := range cases {
		resetStore(cur)
		rec, restore := installRecordingCore()

		testing.SetRealm(adminRealm)
		ForceConnectionOpenTry(cross(cur), types.MsgConnectionOpenTry{ClientId: tc.clientId})

		uassert.Equal(t, 1, rec.calls["ForceConnectionOpenTry"])
		uassert.Equal(t, uint64(tc.clientId), uint64(rec.forceConnTryMsg.ClientId))

		restore()
	}
}

func TestForceConnectionOpenAck(cur realm, t *testing.T) {
	cases := []struct {
		name         string
		connectionId types.ConnectionId
	}{
		{"typical", 5},
		{"zero id", 0},
	}

	for _, tc := range cases {
		resetStore(cur)
		rec, restore := installRecordingCore()

		testing.SetRealm(adminRealm)
		ForceConnectionOpenAck(cross(cur), types.MsgConnectionOpenAck{ConnectionId: tc.connectionId})

		uassert.Equal(t, 1, rec.calls["ForceConnectionOpenAck"])
		uassert.Equal(t, uint64(tc.connectionId), uint64(rec.forceConnAckMsg.ConnectionId))

		restore()
	}
}

func TestForceConnectionOpenConfirm(cur realm, t *testing.T) {
	cases := []struct {
		name         string
		connectionId types.ConnectionId
	}{
		{"typical", 6},
		{"zero id", 0},
	}

	for _, tc := range cases {
		resetStore(cur)
		rec, restore := installRecordingCore()

		testing.SetRealm(adminRealm)
		ForceConnectionOpenConfirm(cross(cur), types.MsgConnectionOpenConfirm{ConnectionId: tc.connectionId})

		uassert.Equal(t, 1, rec.calls["ForceConnectionOpenConfirm"])
		uassert.Equal(t, uint64(tc.connectionId), uint64(rec.forceConnConfirmMsg.ConnectionId))

		restore()
	}
}
