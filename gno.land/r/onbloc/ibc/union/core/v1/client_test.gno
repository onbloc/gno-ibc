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

func TestInitClient(cur realm, t *testing.T) {
	tests := []struct {
		name            string
		lc              *mockLightClient
		clientState     []byte
		consensusState  []byte
		wantHeight      types.Height
		wantClientState string
		wantConsensus   string
		wantStoreKey    string
		wantStoreValue  string
		wantAbort       string
	}{
		{
			name:            "persists submitted state at light client latest height",
			lc:              &mockLightClient{latestHeight: 3},
			clientState:     []byte("client-state"),
			consensusState:  []byte("consensus-state"),
			wantHeight:      types.NewHeight(3),
			wantClientState: "client-state",
			wantConsensus:   "consensus-state",
		},
		{
			name:            "creation result overwrites client state and storage",
			lc:              &mockLightClient{latestHeight: 4, creationState: []byte("verified-client"), creationWrites: map[string][]byte{"create-key": []byte("create-value")}},
			clientState:     []byte("submitted-client"),
			consensusState:  []byte("submitted-consensus"),
			wantHeight:      types.NewHeight(4),
			wantClientState: "verified-client",
			wantConsensus:   "submitted-consensus",
			wantStoreKey:    "create-key",
			wantStoreValue:  "create-value",
		},
		{
			name:      "creation verification error aborts",
			lc:        &mockLightClient{createErr: "bad genesis"},
			wantAbort: "create client: bad genesis",
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			v := newTestImpl()
			lc := tc.lc
			if lc == nil {
				lc = &mockLightClient{}
			}
			clientId := types.ClientId(1)
			v.store.(*mockStore).clients[uint32(clientId)] = &mockClient{typ: testClientType, lc: lc, consensus: make(map[string][]byte), clientStore: make(map[string][]byte)}

			if tc.wantAbort != "" {
				uassert.AbortsContains(t, cur, tc.wantAbort, func(cur realm) {
					v.initClient(0, cur, tc.clientState, tc.consensusState, cur.Previous().Address(), lc, clientId)
				})
				return
			}

			height := v.initClient(0, cur, tc.clientState, tc.consensusState, cur.Previous().Address(), lc, clientId)
			uassert.Equal(t, tc.wantHeight.String(), height.String())

			mc := v.store.(*mockStore).clients[uint32(clientId)]
			uassert.Equal(t, tc.wantClientState, string(mc.clientState))
			uassert.Equal(t, tc.wantConsensus, string(mc.consensus[tc.wantHeight.String()]))
			if tc.wantStoreKey != "" {
				uassert.Equal(t, tc.wantStoreValue, string(mc.clientStore[tc.wantStoreKey]))
			}
		})
	}
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

func TestVerifyMembership(cur realm, t *testing.T) {
	tests := []struct {
		name         string
		lc           *mockLightClient
		missing      bool
		wantAbort    string
		wantCalls    int
		wantNoAbort  bool
	}{
		{"active client verifies", &mockLightClient{}, false, "", 1, true},
		{"unknown client aborts", &mockLightClient{}, true, "client 99 not found", 0, false},
		{"inactive client aborts before proof verification", &mockLightClient{status: lightclient.Expired}, false, "client is not active", 0, false},
		{"proof failure aborts", &mockLightClient{membershipErr: "bad proof"}, false, "bad proof", 1, false},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			v := newTestImpl()
			clientId := types.ClientId(99)
			if !tc.missing {
				clientId = createClient(cur, v, tc.lc, nil, nil)
			}

			if tc.wantNoAbort {
				uassert.NotAborts(t, cur, func() {
					v.verifyMembership(clientId, types.NewHeight(1), []byte("proof"), []byte("path"), []byte("value"))
				})
			} else {
				uassert.AbortsContains(t, cur, tc.wantAbort, func(cur realm) {
					v.verifyMembership(clientId, types.NewHeight(1), []byte("proof"), []byte("path"), []byte("value"))
				})
			}
			uassert.Equal(t, tc.wantCalls, tc.lc.membershipCalls)
		})
	}
}
