package impl

import (
	"testing"

	"gno.land/p/nt/uassert/v0"
	"gno.land/p/onbloc/ibc/union/lightclient"
	"gno.land/p/onbloc/ibc/union/types"
)

const testClientType = types.ClientType("cometbls")

// createClient registers the mock light client's factory for testClientType, then
// creates a client from the given state bytes, returning the assigned id.
func createClient(cur realm, v *coreV1, lc *mockLightClient, clientState, consensusState []byte) types.ClientId {
	v.RegisterClient(0, cur, testClientType, lc.ClientImpl)
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
	v.RegisterClient(0, cur, testClientType, (&mockLightClient{}).ClientImpl)

	uassert.AbortsContains(t, cur, "client type already exists", func(cur realm) {
		v.RegisterClient(0, cur, testClientType, (&mockLightClient{}).ClientImpl)
	})
}

func TestHasClient(cur realm, t *testing.T) {
	cases := []struct {
		name string
		seed func(*coreV1)
		typ  types.ClientType
		want bool
	}{
		{"registered", func(v *coreV1) { v.RegisterClient(0, cur, testClientType, (&mockLightClient{}).ClientImpl) }, testClientType, true},
		{"missing", func(v *coreV1) {}, types.ClientType("missing"), false},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			v := newTestImpl()
			tc.seed(v)
			uassert.Equal(t, tc.want, v.HasClient(tc.typ))
		})
	}
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

func TestCreateClientStoresClientImplResult(cur realm, t *testing.T) {
	v := newTestImpl()
	created := &mockLightClient{latestHeight: 2}
	clientImpl := &mockLightClient{latestHeight: 9, implClient: created}

	clientId := createClient(cur, v, clientImpl, []byte("impl-client"), []byte("impl-consensus"))

	uassert.Equal(t, 1, clientImpl.implCalls)
	uassert.Equal(t, "impl-client", string(clientImpl.implCS))
	uassert.Equal(t, "impl-consensus", string(clientImpl.implCons))
	got, ok := v.store.GetLightClient(clientId)
	uassert.True(t, ok)
	uassert.True(t, got == lightclient.Interface(created))
	mc := v.store.(*mockStore).clients[uint32(clientId)]
	uassert.Equal(t, "impl-consensus", string(mc.consensus[types.NewHeight(2).String()]))
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
	cases := []struct {
		name        string
		seed        func(*coreV1) (types.ClientId, *mockLightClient)
		wantHeight  uint64
		wantState   string
		wantStore   string
		wantPanic   string
		wantConsKey string
	}{
		{
			name: "stores submitted state and creation writes",
			seed: func(v *coreV1) (types.ClientId, *mockLightClient) {
				lc := &mockLightClient{
					latestHeight: 5,
					creationWrites: map[string][]byte{
						"k": []byte("v"),
					},
				}
				v.RegisterClient(0, cur, testClientType, lc.ClientImpl)
				id := v.store.AddClient(0, cur, testClientType, cur.Previous().Address(), lc)
				return id, lc
			},
			wantHeight:  5,
			wantState:   "client-state",
			wantStore:   "v",
			wantConsKey: types.NewHeight(5).String(),
		},
		{
			name: "stores creation writes at initial height",
			seed: func(v *coreV1) (types.ClientId, *mockLightClient) {
				lc := &mockLightClient{
					latestHeight:    1,
					creationWrites: map[string][]byte{"k": []byte("v")},
				}
				v.RegisterClient(0, cur, testClientType, lc.ClientImpl)
				id := v.store.AddClient(0, cur, testClientType, cur.Previous().Address(), lc)
				return id, lc
			},
			wantHeight:  1,
			wantState:   "client-state",
			wantStore:   "v",
			wantConsKey: types.NewHeight(1).String(),
		},
		{
			name: "missing client",
			seed: func(v *coreV1) (types.ClientId, *mockLightClient) {
				return types.ClientId(404), &mockLightClient{}
			},
			wantPanic: "not found",
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			v := newTestImpl()
			clientId, _ := tc.seed(v)
			run := func(cur realm) {
				height := v.initClient(0, cur, clientId, []byte("client-state"), []byte("consensus-state"), cur.Previous().Address())
				uassert.Equal(t, tc.wantHeight, height.RevisionHeight)
			}
			if tc.wantPanic != "" {
				uassert.AbortsContains(t, cur, tc.wantPanic, run)
				return
			}

			uassert.NotAborts(t, cur, run)
			mc := v.store.(*mockStore).clients[uint32(clientId)]
			uassert.Equal(t, tc.wantState, string(mc.clientState))
			uassert.Equal(t, "consensus-state", string(mc.consensus[tc.wantConsKey]))
			uassert.Equal(t, tc.wantStore, string(mc.clientStore["k"]))
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

func TestForceUpdateClientRebuildsSubmittedState(cur realm, t *testing.T) {
	v := newTestImpl()
	lc := &mockLightClient{latestHeight: 1}
	clientId := createClient(cur, v, lc, []byte("old-client"), []byte("old-consensus"))

	lc.latestHeight = 3
	v.ForceUpdateClient(0, cur, types.NewMsgForceUpdateClient(clientId, []byte("new-client"), []byte("new-consensus")))

	mc := v.store.(*mockStore).clients[uint32(clientId)]
	uassert.Equal(t, "new-client", string(mc.clientState))
	uassert.Equal(t, "new-consensus", string(mc.consensus[types.NewHeight(3).String()]))
}

func TestForceUpdateClientReplacesExistingClient(cur realm, t *testing.T) {
	v := newTestImpl()
	initial := &mockLightClient{latestHeight: 1}
	rebuilt := &mockLightClient{latestHeight: 4}
	clientImpl := &mockLightClient{implClient: initial}
	clientId := createClient(cur, v, clientImpl, []byte("old-client"), []byte("old-consensus"))

	clientImpl.implClient = rebuilt
	v.ForceUpdateClient(0, cur, types.NewMsgForceUpdateClient(clientId, []byte("new-client"), []byte("new-consensus")))

	uassert.Equal(t, 2, clientImpl.implCalls)
	uassert.Equal(t, "new-client", string(clientImpl.implCS))
	uassert.Equal(t, "new-consensus", string(clientImpl.implCons))
	got, ok := v.store.GetLightClient(clientId)
	uassert.True(t, ok)
	uassert.True(t, got == lightclient.Interface(rebuilt))
	mc := v.store.(*mockStore).clients[uint32(clientId)]
	uassert.Equal(t, "new-consensus", string(mc.consensus[types.NewHeight(4).String()]))
}

func TestForceUpdateClientUnknownClientAborts(cur realm, t *testing.T) {
	v := newTestImpl()

	uassert.AbortsContains(t, cur, "not found", func(cur realm) {
		v.ForceUpdateClient(0, cur, types.NewMsgForceUpdateClient(types.ClientId(99), nil, nil))
	})
}

func TestMisbehaviourUpdatesClientState(cur realm, t *testing.T) {
	cases := []struct {
		name      string
		initial   []byte
		returned  []byte
		wantState string
	}{
		{
			name:      "returned state mirrors frozen state",
			initial:   []byte("old-client"),
			returned:  []byte("frozen-client"),
			wantState: "frozen-client",
		},
		{
			name:      "empty returned state keeps previous state",
			initial:   []byte("old-client"),
			returned:  nil,
			wantState: "old-client",
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			v := newTestImpl()
			lc := &mockLightClient{misbehaviourState: tc.returned}
			clientId := createClient(cur, v, lc, tc.initial, nil)

			v.Misbehaviour(0, cur, types.NewMsgMisbehaviour(clientId, []byte("evidence"), "g1relayer"))

			uassert.Equal(t, 1, lc.misbehaviourCalls)
			mc := v.store.(*mockStore).clients[uint32(clientId)]
			uassert.Equal(t, tc.wantState, string(mc.clientState))
		})
	}
}

func TestMisbehaviourRejectsInvalidMessages(cur realm, t *testing.T) {
	cases := []struct {
		name      string
		setup     func(*coreV1) (types.MsgMisbehaviour, *mockLightClient)
		wantPanic string
		wantCalls int
	}{
		{
			name: "unknown client",
			setup: func(v *coreV1) (types.MsgMisbehaviour, *mockLightClient) {
				return types.NewMsgMisbehaviour(types.ClientId(99), []byte("evidence"), ""), nil
			},
			wantPanic: "not found",
		},
		{
			name: "inactive client",
			setup: func(v *coreV1) (types.MsgMisbehaviour, *mockLightClient) {
				lc := &mockLightClient{status: lightclient.Expired}
				clientId := createClient(cur, v, lc, nil, nil)
				return types.NewMsgMisbehaviour(clientId, []byte("evidence"), ""), lc
			},
			wantPanic: "client is not active",
		},
		{
			name: "light client error",
			setup: func(v *coreV1) (types.MsgMisbehaviour, *mockLightClient) {
				lc := &mockLightClient{misbehaviourErr: "bad evidence"}
				clientId := createClient(cur, v, lc, nil, nil)
				return types.NewMsgMisbehaviour(clientId, []byte("evidence"), ""), lc
			},
			wantPanic: "misbehaviour: bad evidence",
			wantCalls: 1,
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			v := newTestImpl()
			msg, lc := tc.setup(v)

			uassert.AbortsContains(t, cur, tc.wantPanic, func(cur realm) {
				v.Misbehaviour(0, cur, msg)
			})
			if lc != nil {
				uassert.Equal(t, tc.wantCalls, lc.misbehaviourCalls)
			}
		})
	}
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
	lc := &mockLightClient{status: lightclient.Expired}
	clientId := createClient(cur, v, lc, nil, nil)

	uassert.AbortsContains(t, cur, "client is not active", func(cur realm) {
		v.VerifyClientMembership(0, cur, clientId, types.NewHeight(1), []byte("proof"), []byte("path"), []byte("value"))
	})
	uassert.Equal(t, 0, lc.membershipCalls)
}

func TestVerifyClientMembershipProofFailureAborts(cur realm, t *testing.T) {
	v := newTestImpl()
	clientId := createClient(cur, v, &mockLightClient{membershipErr: "bad proof"}, nil, nil)

	uassert.AbortsContains(t, cur, "bad proof", func(cur realm) {
		v.VerifyClientMembership(0, cur, clientId, types.NewHeight(1), []byte("proof"), []byte("path"), []byte("value"))
	})
}

func TestGetActiveClient(cur realm, t *testing.T) {
	cases := []struct {
		name      string
		seed      func(*coreV1) types.ClientId
		wantPanic string
	}{
		{
			name: "active client",
			seed: func(v *coreV1) types.ClientId {
				return createClient(cur, v, &mockLightClient{}, nil, nil)
			},
		},
		{
			name: "missing client",
			seed: func(v *coreV1) types.ClientId {
				return types.ClientId(404)
			},
			wantPanic: "not found",
		},
		{
			name: "inactive client",
			seed: func(v *coreV1) types.ClientId {
				return createClient(cur, v, &mockLightClient{status: lightclient.Frozen}, nil, nil)
			},
			wantPanic: "client is not active",
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			v := newTestImpl()
			clientId := tc.seed(v)
			run := func(cur realm) {
				lc, err := v.getActiveClient(clientId)
				if err != nil {
					panic(err)
				}
				if lc == nil {
					t.Fatal("active client returned nil")
				}
			}
			if tc.wantPanic != "" {
				uassert.AbortsContains(t, cur, tc.wantPanic, run)
				return
			}
			uassert.NotAborts(t, cur, run)
		})
	}
}

func TestVerifyMembership(cur realm, t *testing.T) {
	cases := []struct {
		name        string
		lc          *mockLightClient
		clientId    types.ClientId
		wantPanic   string
		wantCalls   int
		useExisting bool
	}{
		{"active client", &mockLightClient{}, 0, "", 1, true},
		{"missing client", &mockLightClient{}, types.ClientId(404), "not found", 0, false},
		{"inactive client", &mockLightClient{status: lightclient.Expired}, 0, "client is not active", 0, true},
		{"proof failure", &mockLightClient{membershipErr: "bad proof"}, 0, "bad proof", 1, true},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			v := newTestImpl()
			clientId := tc.clientId
			if tc.useExisting {
				clientId = createClient(cur, v, tc.lc, nil, nil)
			}

			run := func(cur realm) {
				v.verifyMembership(clientId, types.NewHeight(3), []byte("proof"), []byte("key"), []byte("value"))
			}
			if tc.wantPanic != "" {
				uassert.AbortsContains(t, cur, tc.wantPanic, run)
			} else {
				uassert.NotAborts(t, cur, run)
			}
			uassert.Equal(t, tc.wantCalls, tc.lc.membershipCalls)
		})
	}
}
