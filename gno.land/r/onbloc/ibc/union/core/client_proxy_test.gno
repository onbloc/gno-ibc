package core

import (
	"testing"

	"gno.land/p/nt/uassert/v0"
	"gno.land/p/onbloc/ibc/union/lightclient"
	"gno.land/r/onbloc/ibc/union/access"
	"gno.land/p/onbloc/ibc/union/types"
)

// client_proxy_test.gno covers the public proxy entrypoints in client.gno. Each
// entrypoint either gates then delegates to mustGetImpl() or delegates directly.
// The tests assert three things per gated entrypoint: the call reaches the impl
// with its arguments intact (delegation), an unauthorized caller is rejected
// (gate), and a missing impl panics.
//
// Gate classes:
//   - relayer-gated: RegisterClient, CreateClient, UpdateClient, Misbehaviour
//   - admin-gated:   ForceUpdateClient
//   - ungated:       VerifyClientMembership, HasClient

func noopClientImpl(clientStateBytes, consensusStateBytes []byte) (lightclient.Interface, error) {
	return nil, nil
}

func TestRegisterClient(cur realm, t *testing.T) {
	cases := []struct {
		name string
		typ  types.ClientType
	}{
		{"cometbls", "cometbls"},
		{"state lens", "state-lens/ics23/mpt"},
		{"empty type", ""},
	}

	for _, tc := range cases {
		resetStore(cur)
		rec, restore := installRecordingCore()

		testing.SetRealm(adminRealm)
		access.GrantRole(cross(cur), RelayerRole, testRelayer)
		testing.SetRealm(relayerRealm)
		RegisterClient(cross(cur), tc.typ, noopClientImpl)
		testing.SetRealm(adminRealm)
		access.RevokeRole(cross(cur), RelayerRole, testRelayer)

		uassert.Equal(t, 1, rec.calls["RegisterClient"])
		uassert.Equal(t, string(tc.typ), string(rec.registerClientType))
		uassert.True(t, rec.registerClientImpl != nil)

		restore()
	}
}

func TestRegisterClient_RejectsNonRelayer(cur realm, t *testing.T) {
	resetStore(cur)
	requireSelectorProtectedForTest(cur, SelectorRegisterClient)

	uassert.AbortsContains(t, cur, accessManagerUnauthorizedCallError, func(cur realm) {
		RegisterClient(cross(cur), "cometbls", noopClientImpl)
	})
}

func TestCreateClient(cur realm, t *testing.T) {
	cases := []struct {
		name string
		msg  types.MsgCreateClient
	}{
		{"with state bytes", types.MsgCreateClient{ClientType: "cometbls", ClientStateBytes: []byte{0x01}, ConsensusStateBytes: []byte{0x02}, Relayer: "r1"}},
		{"empty msg", types.MsgCreateClient{}},
	}

	for _, tc := range cases {
		resetStore(cur)
		rec, restore := installRecordingCore()

		testing.SetRealm(adminRealm)
		access.GrantRole(cross(cur), RelayerRole, testRelayer)
		testing.SetRealm(relayerRealm)
		CreateClient(cross(cur), tc.msg)
		testing.SetRealm(adminRealm)
		access.RevokeRole(cross(cur), RelayerRole, testRelayer)

		uassert.Equal(t, 1, rec.calls["CreateClient"])
		uassert.Equal(t, string(tc.msg.ClientType), string(rec.createClientMsg.ClientType))

		restore()
	}
}

func TestCreateClient_RejectsNonRelayer(cur realm, t *testing.T) {
	resetStore(cur)
	requireSelectorProtectedForTest(cur, SelectorCreateClient)

	uassert.AbortsContains(t, cur, accessManagerUnauthorizedCallError, func(cur realm) {
		CreateClient(cross(cur), types.MsgCreateClient{ClientType: "cometbls"})
	})
}

func TestCreateClient_RequiresInstalledImpl(cur realm, t *testing.T) {
	resetStore(cur)
	old := currentImpl
	currentImpl = nil
	defer func() { currentImpl = old }()

	testing.SetRealm(adminRealm)
	access.GrantRole(cross(cur), RelayerRole, testRelayer)
	testing.SetRealm(relayerRealm)
	uassert.AbortsContains(t, cur, "implementation not installed", func(cur realm) {
		testing.SetRealm(relayerRealm)
		CreateClient(cross(cur), types.MsgCreateClient{})
	})
	testing.SetRealm(adminRealm)
	access.RevokeRole(cross(cur), RelayerRole, testRelayer)
}

func TestUpdateClient(cur realm, t *testing.T) {
	cases := []struct {
		name string
		msg  types.MsgUpdateClient
	}{
		{"with message", types.MsgUpdateClient{ClientId: 7, ClientMessage: []byte{0xaa}, Relayer: "r"}},
		{"zero client id", types.MsgUpdateClient{ClientId: 0}},
	}

	for _, tc := range cases {
		resetStore(cur)
		rec, restore := installRecordingCore()

		testing.SetRealm(adminRealm)
		access.GrantRole(cross(cur), RelayerRole, testRelayer)
		testing.SetRealm(relayerRealm)
		UpdateClient(cross(cur), tc.msg)
		testing.SetRealm(adminRealm)
		access.RevokeRole(cross(cur), RelayerRole, testRelayer)

		uassert.Equal(t, 1, rec.calls["UpdateClient"])
		uassert.Equal(t, uint64(tc.msg.ClientId), uint64(rec.updateClientMsg.ClientId))

		restore()
	}
}

func TestUpdateClient_RejectsNonRelayer(cur realm, t *testing.T) {
	resetStore(cur)
	requireSelectorProtectedForTest(cur, SelectorUpdateClient)

	uassert.AbortsContains(t, cur, accessManagerUnauthorizedCallError, func(cur realm) {
		UpdateClient(cross(cur), types.MsgUpdateClient{ClientId: 1})
	})
}

func TestForceUpdateClient(cur realm, t *testing.T) {
	cases := []struct {
		name string
		msg  types.MsgForceUpdateClient
	}{
		{"recover client", types.MsgForceUpdateClient{ClientId: 3, ClientStateBytes: []byte{0x01}, ConsensusStateBytes: []byte{0x02}}},
		{"zero client id", types.MsgForceUpdateClient{ClientId: 0}},
	}

	for _, tc := range cases {
		resetStore(cur)
		rec, restore := installRecordingCore()

		testing.SetRealm(adminRealm)
		ForceUpdateClient(cross(cur), tc.msg)

		uassert.Equal(t, 1, rec.calls["ForceUpdateClient"])
		uassert.Equal(t, uint64(tc.msg.ClientId), uint64(rec.forceUpdateMsg.ClientId))

		restore()
	}
}

func TestForceUpdateClient_RejectsNonAdmin(cur realm, t *testing.T) {
	resetStore(cur)
	requireSelectorProtectedForTest(cur, SelectorForceUpdateClient)

	uassert.AbortsContains(t, cur, accessManagerUnauthorizedCallError, func(cur realm) {
		ForceUpdateClient(cross(cur), types.MsgForceUpdateClient{ClientId: 1})
	})
}

func TestMisbehaviour(cur realm, t *testing.T) {
	cases := []struct {
		name string
		msg  types.MsgMisbehaviour
	}{
		{"freeze client", types.MsgMisbehaviour{ClientId: 5, ClientMessage: []byte{0xbb}, Relayer: "r"}},
		{"zero client id", types.MsgMisbehaviour{ClientId: 0}},
	}

	for _, tc := range cases {
		resetStore(cur)
		rec, restore := installRecordingCore()

		testing.SetRealm(adminRealm)
		access.GrantRole(cross(cur), RelayerRole, testRelayer)
		testing.SetRealm(relayerRealm)
		Misbehaviour(cross(cur), tc.msg)
		testing.SetRealm(adminRealm)
		access.RevokeRole(cross(cur), RelayerRole, testRelayer)

		uassert.Equal(t, 1, rec.calls["Misbehaviour"])
		uassert.Equal(t, uint64(tc.msg.ClientId), uint64(rec.misbehaviourMsg.ClientId))

		restore()
	}
}

func TestMisbehaviour_RejectsNonRelayer(cur realm, t *testing.T) {
	resetStore(cur)
	requireSelectorProtectedForTest(cur, SelectorMisbehaviour)

	uassert.AbortsContains(t, cur, accessManagerUnauthorizedCallError, func(cur realm) {
		Misbehaviour(cross(cur), types.MsgMisbehaviour{ClientId: 1})
	})
}

func TestVerifyClientMembership(cur realm, t *testing.T) {
	cases := []struct {
		name     string
		clientId types.ClientId
		height   types.Height
		proof    []byte
		path     []byte
		value    []byte
	}{
		{"full args", 9, types.NewHeight(100), []byte{0x01}, []byte("path"), []byte("value")},
		{"empty proof and value", 0, types.NewHeight(0), nil, nil, nil},
	}

	for _, tc := range cases {
		resetStore(cur)
		rec, restore := installRecordingCore()

		// ungated: no SetRealm needed for authorization
		VerifyClientMembership(cross(cur), tc.clientId, tc.height, tc.proof, tc.path, tc.value)

		uassert.Equal(t, 1, rec.calls["VerifyClientMembership"])
		uassert.Equal(t, uint64(tc.clientId), uint64(rec.verifyClientId))

		restore()
	}
}

func TestHasClient(cur realm, t *testing.T) {
	cases := []struct {
		name      string
		typ       types.ClientType
		implReply bool
		want      bool
	}{
		{"registered type", "cometbls", true, true},
		{"unregistered type", "unknown", false, false},
	}

	for _, tc := range cases {
		resetStore(cur)
		rec, restore := installRecordingCore()
		rec.hasClientResult = tc.implReply

		got := HasClient(tc.typ)

		uassert.Equal(t, tc.want, got)
		uassert.Equal(t, string(tc.typ), string(rec.hasClientType))

		restore()
	}
}
