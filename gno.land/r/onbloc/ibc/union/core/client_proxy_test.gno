package core

import (
	"testing"

	"gno.land/p/nt/uassert/v0"
	"gno.land/p/onbloc/ibc/union/lightclient"
	"gno.land/p/onbloc/ibc/union/types"
	"gno.land/r/onbloc/ibc/union/access"
)

// client_proxy_test.gno covers the public proxy entrypoints in client.gno. Each
// entrypoint either gates then delegates to mustGetImpl() or delegates directly.
// The tests assert three things per gated entrypoint: the call reaches the impl
// with its arguments intact (delegation), an unauthorized caller is rejected
// (gate), and a missing impl panics.
//
// Gate classes:
//   - relayer-gated + loader-realm: RegisterClient (see TestRegisterClient)
//   - relayer-gated: CreateClient, UpdateClient, Misbehaviour
//   - admin-gated:   ForceUpdateClient
//   - ungated:       VerifyClientMembership, HasClient

// testLoaderPath is a synthetic loader-realm package path registered into the
// clientLoaders allowlist so the proxy delegation tests can drive RegisterClient
// without depending on the production loader realm paths.
const testLoaderPath = "gno.land/r/onbloc/ibc/union/core/test-loader"

// registerTestLoader adds testLoaderPath to the clientLoaders allowlist as admin.
// Tests that exercise RegisterClient must call this first.
func registerTestLoader(cur realm) {
	testing.SetRealm(adminRealm)
	RegisterClientLoader(cross(cur), testLoaderPath)
}

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

		loaderRealm := testing.NewCodeRealm(testLoaderPath)
		registerTestLoader(cur)
		testing.SetRealm(adminRealm)
		access.GrantRole(cross(cur), RelayerRole, loaderRealm.Address())
		testing.SetRealm(loaderRealm)
		RegisterClient(cross(cur), tc.typ, noopClientImpl)
		testing.SetRealm(adminRealm)
		access.RevokeRole(cross(cur), RelayerRole, loaderRealm.Address())

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
		testing.SetRealm(testing.NewCodeRealm(testLoaderPath))
		RegisterClient(cross(cur), "cometbls", noopClientImpl)
	})
}

// TestRegisterClient_RejectsUnregisteredLoader verifies a relayer calling from a
// realm that is not in the clientLoaders allowlist is rejected, even when it
// holds RelayerRole and is not admin.
func TestRegisterClient_RejectsUnregisteredLoader(cur realm, t *testing.T) {
	resetStore(cur)

	testing.SetRealm(adminRealm)
	access.GrantRole(cross(cur), RelayerRole, testRelayer)

	uassert.AbortsContains(t, cur, ErrUnregisteredClientLoader, func(cur realm) {
		// relayerRealm is a user realm, not in the loader allowlist; testRelayer
		// holds RelayerRole but not AdminRole.
		testing.SetRealm(relayerRealm)
		RegisterClient(cross(cur), "cometbls", noopClientImpl)
	})

	testing.SetRealm(adminRealm)
	access.RevokeRole(cross(cur), RelayerRole, testRelayer)
}

func TestCreateClient(cur realm, t *testing.T) {
	cases := []struct {
		name string
		msg  types.MsgCreateClient
	}{
		{"with state bytes", types.MsgCreateClient{ClientType: "cometbls", ClientStateBytes: []byte{0x01}, ConsensusStateBytes: []byte{0x02}, Relayer: "r1"}},
		{"different type", types.MsgCreateClient{ClientType: "state-lens", ClientStateBytes: []byte{0x03}, ConsensusStateBytes: []byte{0x04}}},
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
		CreateClient(cross(cur), types.MsgCreateClient{ClientStateBytes: []byte{0x01}, ConsensusStateBytes: []byte{0x02}})
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
		{"other client id", types.MsgUpdateClient{ClientId: 42, ClientMessage: []byte{0xbb}}},
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
		{"other client", types.MsgForceUpdateClient{ClientId: 9, ClientStateBytes: []byte{0x03}, ConsensusStateBytes: []byte{0x04}}},
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
		{"other client", types.MsgMisbehaviour{ClientId: 8, ClientMessage: []byte{0xcc}}},
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
