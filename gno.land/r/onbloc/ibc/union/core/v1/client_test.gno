package impl

import (
	"testing"

	"gno.land/p/nt/uassert/v0"
	"gno.land/p/onbloc/ibc/union/lightclient"
	"gno.land/p/onbloc/ibc/union/types"
)

const testClientType = types.ClientType("cometbls")

// createClient registers lc under the test client type and creates a client from
// the given state bytes, returning the assigned id. It mirrors the proxy's
// RegisterClient -> CreateClient flow used by the host entrypoints. CreateClient
// no longer returns the id, so the id is read back from the mock store's sequence.
func createClient(cur realm, v *coreV1, lc lightclient.Interface, clientState, consensusState []byte) types.ClientId {
	v.RegisterClient(0, cur, testClientType, lc)
	v.CreateClient(0, cur, types.NewMsgCreateClient(testClientType, clientState, consensusState))
	return types.ClientId(v.store.(*mockStore).seq)
}

func TestRegisterClientRejectsNil(cur realm, t *testing.T) {
	v := newTestImpl()

	uassert.AbortsContains(t, cur, "unauthorized", func(cur realm) {
		v.RegisterClient(0, cur, testClientType, nil)
	})
}

func TestRegisterClientRejectsDuplicate(cur realm, t *testing.T) {
	v := newTestImpl()
	v.RegisterClient(0, cur, testClientType, &mockLightClient{})

	uassert.AbortsContains(t, cur, "client type already exists", func(cur realm) {
		v.RegisterClient(0, cur, testClientType, &mockLightClient{})
	})
}

func TestCreateClientRejectsUnregisteredType(cur realm, t *testing.T) {
	v := newTestImpl()

	uassert.AbortsContains(t, cur, "client type not found", func(cur realm) {
		v.CreateClient(0, cur, types.NewMsgCreateClient(testClientType, nil, nil))
	})
}

func TestCreateClientRegistersAndVerifies(cur realm, t *testing.T) {
	v := newTestImpl()
	lc := &mockLightClient{latestHeight: 1}

	clientId := createClient(cur, v, lc, []byte("client-state"), []byte("consensus-state"))

	uassert.True(t, v.store.ClientExists(clientId))
	typ, ok := v.store.ClientType(clientId)
	uassert.True(t, ok)
	uassert.Equal(t, "cometbls", string(typ))
	got, ok := v.store.GetLightClient(clientId)
	uassert.True(t, ok)
	uassert.True(t, got == lightclient.Interface(lc))

	mc := v.store.(*mockStore).clients[uint32(clientId)]
	uassert.Equal(t, "client-state", string(mc.clientState))
	uassert.Equal(t, "consensus-state", string(mc.consensus[types.NewHeight(1).String()]))
}

func TestCreateClientVerifyCreationFailureAborts(cur realm, t *testing.T) {
	v := newTestImpl()
	lc := &mockLightClient{createErr: "bad genesis"}

	uassert.AbortsContains(t, cur, "create client: bad genesis", func(cur realm) {
		createClient(cur, v, lc, nil, nil)
	})
}

func TestCreateClientPersistsCreationStorageWrites(cur realm, t *testing.T) {
	v := newTestImpl()
	lc := &mockLightClient{creationWrites: map[string][]byte{"create-key": []byte("create-value")}}

	clientId := createClient(cur, v, lc, nil, nil)

	mc := v.store.(*mockStore).clients[uint32(clientId)]
	uassert.Equal(t, "create-value", string(mc.clientStore["create-key"]))
}

func TestUpdateClientSavesStateAndConsensus(cur realm, t *testing.T) {
	v := newTestImpl()
	lc := &mockLightClient{update: types.StateUpdate{
		Height:              7,
		ClientStateBytes:    []byte("client-state"),
		ConsensusStateBytes: []byte("consensus-state"),
		StorageWrites:       map[string][]byte{"update-key": []byte("update-value")},
	}}
	clientId := createClient(cur, v, lc, nil, nil)

	v.UpdateClient(0, cur, types.MsgUpdateClient{
		ClientId:      clientId,
		ClientMessage: []byte("header"),
	})

	height := types.NewHeight(7)
	mc := v.store.(*mockStore).clients[uint32(clientId)]
	uassert.Equal(t, "client-state", string(mc.clientState))
	uassert.Equal(t, "consensus-state", string(mc.consensus[height.String()]))
	uassert.Equal(t, "update-value", string(mc.clientStore["update-key"]))
}

func TestUpdateClientUnknownClientAborts(cur realm, t *testing.T) {
	v := newTestImpl()

	uassert.AbortsContains(t, cur, "not found", func(cur realm) {
		v.UpdateClient(0, cur, types.MsgUpdateClient{ClientId: types.ClientId(99)})
	})
}

func TestUpdateClientInactiveAborts(cur realm, t *testing.T) {
	v := newTestImpl()
	lc := &mockLightClient{status: lightclient.Expired}
	clientId := createClient(cur, v, lc, nil, nil)

	uassert.AbortsContains(t, cur, "client is not active", func(cur realm) {
		v.UpdateClient(0, cur, types.MsgUpdateClient{ClientId: clientId, ClientMessage: []byte("h")})
	})
}

func TestUpdateClientVerifyHeaderFailureAborts(cur realm, t *testing.T) {
	v := newTestImpl()
	lc := &mockLightClient{headerErr: "stale header"}
	clientId := createClient(cur, v, lc, nil, nil)

	uassert.AbortsContains(t, cur, "update client: stale header", func(cur realm) {
		v.UpdateClient(0, cur, types.MsgUpdateClient{ClientId: clientId, ClientMessage: []byte("h")})
	})
}

func TestForceUpdateClientReinitializesSubmittedState(cur realm, t *testing.T) {
	v := newTestImpl()
	lc := &mockLightClient{latestHeight: 1}
	clientId := createClient(cur, v, lc, []byte("old-client"), []byte("old-consensus"))

	lc.latestHeight = 3
	v.ForceUpdateClient(0, cur, types.NewMsgForceUpdateClient(clientId, []byte("new-client"), []byte("new-consensus")))

	mc := v.store.(*mockStore).clients[uint32(clientId)]
	uassert.Equal(t, "new-client", string(mc.clientState))
	uassert.Equal(t, "new-consensus", string(mc.consensus[types.NewHeight(3).String()]))
}

func TestForceUpdateClientUnknownClientAborts(cur realm, t *testing.T) {
	v := newTestImpl()

	uassert.AbortsContains(t, cur, "not found", func(cur realm) {
		v.ForceUpdateClient(0, cur, types.NewMsgForceUpdateClient(types.ClientId(99), nil, nil))
	})
}

func TestVerifyClientMembershipActivePasses(cur realm, t *testing.T) {
	v := newTestImpl()
	clientId := createClient(cur, v, &mockLightClient{}, nil, nil)

	uassert.NotAborts(t, cur, func() {
		v.VerifyClientMembership(0, cur, clientId, types.NewHeight(1), []byte("proof"), []byte("path"), []byte("value"))
	})
}

func TestVerifyClientMembershipInactiveAborts(cur realm, t *testing.T) {
	v := newTestImpl()
	clientId := createClient(cur, v, &mockLightClient{status: lightclient.Expired}, nil, nil)

	uassert.AbortsContains(t, cur, "client is not active", func(cur realm) {
		v.VerifyClientMembership(0, cur, clientId, types.NewHeight(1), []byte("proof"), []byte("path"), []byte("value"))
	})
}

func TestVerifyClientMembershipProofFailureAborts(cur realm, t *testing.T) {
	v := newTestImpl()
	clientId := createClient(cur, v, &mockLightClient{membershipErr: "bad proof"}, nil, nil)

	uassert.AbortsContains(t, cur, "bad proof", func(cur realm) {
		v.VerifyClientMembership(0, cur, clientId, types.NewHeight(1), []byte("proof"), []byte("path"), []byte("value"))
	})
}
