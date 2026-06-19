package impl

import (
	"testing"

	"gno.land/p/nt/uassert/v0"
	"gno.land/p/onbloc/ibc/union/lightclient"
	"gno.land/p/onbloc/ibc/union/types"
)

func TestCreateClientRegistersAndVerifies(cur realm, t *testing.T) {
	v := newTestImpl()
	lc := &mockLightClient{}

	clientId := v.CreateClient(0, cur, types.ClientType("cometbls"), lc)

	uassert.True(t, v.store.ClientExists(clientId))
	typ, ok := v.store.ClientType(clientId)
	uassert.True(t, ok)
	uassert.Equal(t, "cometbls", string(typ))
	got, ok := v.store.GetLightClient(clientId)
	uassert.True(t, ok)
	uassert.True(t, got == lightclient.Interface(lc))
}

func TestCreateClientVerifyCreationFailureAborts(cur realm, t *testing.T) {
	v := newTestImpl()
	lc := &mockLightClient{createErr: "bad genesis"}

	uassert.AbortsContains(t, cur, "create client: bad genesis", func(cur realm) {
		v.CreateClient(0, cur, types.ClientType("cometbls"), lc)
	})
}

func TestUpdateClientSavesStateAndConsensus(cur realm, t *testing.T) {
	v := newTestImpl()
	lc := &mockLightClient{update: types.StateUpdate{
		Height:              7,
		ClientStateBytes:    []byte("client-state"),
		ConsensusStateBytes: []byte("consensus-state"),
	}}
	clientId := v.CreateClient(0, cur, types.ClientType("cometbls"), lc)

	height := v.UpdateClient(0, cur, types.MsgUpdateClient{
		ClientId:      clientId,
		ClientMessage: []byte("header"),
	})

	uassert.Equal(t, uint64(7), height.RevisionHeight)
	mc := v.store.(*mockStore).clients[uint32(clientId)]
	uassert.Equal(t, "client-state", string(mc.clientState))
	uassert.Equal(t, "consensus-state", string(mc.consensus[height.String()]))
}

func TestUpdateClientUnknownClientAborts(cur realm, t *testing.T) {
	v := newTestImpl()

	uassert.AbortsContains(t, cur, "not found", func(cur realm) {
		v.UpdateClient(0, cur, types.MsgUpdateClient{ClientId: types.ClientId(99)})
	})
}

func TestUpdateClientVerifyHeaderFailureAborts(cur realm, t *testing.T) {
	v := newTestImpl()
	lc := &mockLightClient{headerErr: "stale header"}
	clientId := v.CreateClient(0, cur, types.ClientType("cometbls"), lc)

	uassert.AbortsContains(t, cur, "update client: stale header", func(cur realm) {
		v.UpdateClient(0, cur, types.MsgUpdateClient{ClientId: clientId, ClientMessage: []byte("h")})
	})
}

func TestVerifyClientMembershipActivePasses(cur realm, t *testing.T) {
	v := newTestImpl()
	clientId := v.CreateClient(0, cur, types.ClientType("cometbls"), &mockLightClient{})

	uassert.NotAborts(t, cur, func() {
		v.VerifyClientMembership(0, cur, clientId, types.NewHeight(1), []byte("proof"), []byte("path"), []byte("value"))
	})
}

func TestVerifyClientMembershipInactiveAborts(cur realm, t *testing.T) {
	v := newTestImpl()
	clientId := v.CreateClient(0, cur, types.ClientType("cometbls"), &mockLightClient{status: lightclient.Expired})

	uassert.AbortsContains(t, cur, "client is not active", func(cur realm) {
		v.VerifyClientMembership(0, cur, clientId, types.NewHeight(1), []byte("proof"), []byte("path"), []byte("value"))
	})
}

func TestVerifyClientMembershipProofFailureAborts(cur realm, t *testing.T) {
	v := newTestImpl()
	clientId := v.CreateClient(0, cur, types.ClientType("cometbls"), &mockLightClient{membershipErr: "bad proof"})

	uassert.AbortsContains(t, cur, "bad proof", func(cur realm) {
		v.VerifyClientMembership(0, cur, clientId, types.NewHeight(1), []byte("proof"), []byte("path"), []byte("value"))
	})
}
