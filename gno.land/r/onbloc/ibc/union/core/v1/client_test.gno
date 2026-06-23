package impl

import (
	"testing"

	"gno.land/p/nt/uassert/v0"
	"gno.land/p/onbloc/ibc/union/lightclient"
	"gno.land/p/onbloc/ibc/union/types"
)

const testClientType = types.ClientType("cometbls")

// createClient registers lc, creates a test client, and returns its id.
// Since CreateClient does not return the id, it is read from the mock store.
func createClient(cur realm, v *coreV1, lc lightclient.Interface, clientState, consensusState []byte) types.ClientId {
	v.RegisterClient(0, cur, testClientType, lc)
	v.CreateClient(0, cur, types.NewMsgCreateClient(testClientType, clientState, consensusState))
	return types.ClientId(v.store.(*mockStore).seq)
}

func TestRegisterClient(cur realm, t *testing.T) {
	tests := []struct {
		name      string
		setup     func(v *coreV1)
		lc        lightclient.Interface
		wantAbort string
	}{
		{
			name:      "rejects nil",
			lc:        nil,
			wantAbort: "unauthorized",
		},
		{
			name: "rejects duplicate",
			setup: func(v *coreV1) {
				v.RegisterClient(0, cur, testClientType, &mockLightClient{})
			},
			lc:        &mockLightClient{},
			wantAbort: "client type already exists",
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			v := newTestImpl()
			if tc.setup != nil {
				tc.setup(v)
			}

			uassert.AbortsContains(t, cur, tc.wantAbort, func(cur realm) {
				v.RegisterClient(0, cur, testClientType, tc.lc)
			})
		})
	}
}

func TestCreateClient(cur realm, t *testing.T) {
	tests := []struct {
		name            string
		lc              *mockLightClient
		registerClient  bool
		clientState     []byte
		consensusState  []byte
		wantAbort       string
		wantClientState string
		wantConsensus   string
		wantStoreKey    string
		wantStoreValue  string
	}{
		{
			name:      "rejects unregistered type",
			wantAbort: "client type not found",
		},
		{
			name:           "creation verification failure aborts",
			lc:             &mockLightClient{createErr: "bad genesis"},
			registerClient: true,
			wantAbort:      "create client: bad genesis",
		},
		{
			name:            "registers and verifies",
			lc:              &mockLightClient{latestHeight: 1},
			registerClient:  true,
			clientState:     []byte("client-state"),
			consensusState:  []byte("consensus-state"),
			wantClientState: "client-state",
			wantConsensus:   "consensus-state",
		},
		{
			name:           "persists creation storage writes",
			lc:             &mockLightClient{creationWrites: map[string][]byte{"create-key": []byte("create-value")}},
			registerClient: true,
			wantStoreKey:   "create-key",
			wantStoreValue: "create-value",
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			v := newTestImpl()
			if tc.registerClient {
				v.RegisterClient(0, cur, testClientType, tc.lc)
			}

			if tc.wantAbort != "" {
				uassert.AbortsContains(t, cur, tc.wantAbort, func(cur realm) {
					v.CreateClient(0, cur, types.NewMsgCreateClient(testClientType, nil, nil))
				})
				return
			}

			v.CreateClient(0, cur, types.NewMsgCreateClient(testClientType, tc.clientState, tc.consensusState))
			clientId := types.ClientId(v.store.(*mockStore).seq)

			uassert.True(t, v.store.ClientExists(clientId))
			typ, ok := v.store.ClientType(clientId)
			uassert.True(t, ok)
			uassert.Equal(t, "cometbls", string(typ))
			got, ok := v.store.GetLightClient(clientId)
			uassert.True(t, ok)
			uassert.True(t, got == lightclient.Interface(tc.lc))

			mc := v.store.(*mockStore).clients[uint32(clientId)]
			if tc.wantClientState != "" {
				uassert.Equal(t, tc.wantClientState, string(mc.clientState))
			}
			if tc.wantConsensus != "" {
				uassert.Equal(t, tc.wantConsensus, string(mc.consensus[types.NewHeight(tc.lc.latestHeight).String()]))
			}
			if tc.wantStoreKey != "" {
				uassert.Equal(t, tc.wantStoreValue, string(mc.clientStore[tc.wantStoreKey]))
			}
		})
	}
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

func TestUpdateClient(cur realm, t *testing.T) {
	tests := []struct {
		name            string
		lc              *mockLightClient
		missing         bool
		wantAbort       string
		wantHeight      types.Height
		wantClientState string
		wantConsensus   string
		wantStoreKey    string
		wantStoreValue  string
	}{
		{
			name: "saves state and consensus",
			lc: &mockLightClient{update: types.StateUpdate{
				Height:              7,
				ClientStateBytes:    []byte("client-state"),
				ConsensusStateBytes: []byte("consensus-state"),
				StorageWrites:       map[string][]byte{"update-key": []byte("update-value")},
			}},
			wantHeight:      types.NewHeight(7),
			wantClientState: "client-state",
			wantConsensus:   "consensus-state",
			wantStoreKey:    "update-key",
			wantStoreValue:  "update-value",
		},
		{
			name:      "unknown client aborts",
			lc:        &mockLightClient{},
			missing:   true,
			wantAbort: "not found",
		},
		{
			name:      "inactive client aborts",
			lc:        &mockLightClient{status: lightclient.Expired},
			wantAbort: "client is not active",
		},
		{
			name:      "verify header failure aborts",
			lc:        &mockLightClient{headerErr: "stale header"},
			wantAbort: "update client: stale header",
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			v := newTestImpl()
			clientId := types.ClientId(99)
			if !tc.missing {
				clientId = createClient(cur, v, tc.lc, nil, nil)
			}

			if tc.wantAbort != "" {
				uassert.AbortsContains(t, cur, tc.wantAbort, func(cur realm) {
					v.UpdateClient(0, cur, types.MsgUpdateClient{ClientId: clientId, ClientMessage: []byte("h")})
				})
				return
			}

			v.UpdateClient(0, cur, types.MsgUpdateClient{
				ClientId:      clientId,
				ClientMessage: []byte("header"),
			})

			mc := v.store.(*mockStore).clients[uint32(clientId)]
			uassert.Equal(t, tc.wantClientState, string(mc.clientState))
			uassert.Equal(t, tc.wantConsensus, string(mc.consensus[tc.wantHeight.String()]))
			if tc.wantStoreKey != "" {
				uassert.Equal(t, tc.wantStoreValue, string(mc.clientStore[tc.wantStoreKey]))
			}
		})
	}
}

func TestForceUpdateClient(cur realm, t *testing.T) {
	tests := []struct {
		name            string
		lc              *mockLightClient
		missing         bool
		clientState     []byte
		consensusState  []byte
		wantAbort       string
		wantClientState string
		wantConsensus   string
	}{
		{
			name:            "reinitializes submitted state",
			lc:              &mockLightClient{latestHeight: 1},
			clientState:     []byte("new-client"),
			consensusState:  []byte("new-consensus"),
			wantClientState: "new-client",
			wantConsensus:   "new-consensus",
		},
		{
			name:      "unknown client aborts",
			lc:        &mockLightClient{},
			missing:   true,
			wantAbort: "not found",
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			v := newTestImpl()
			clientId := types.ClientId(99)
			if !tc.missing {
				clientId = createClient(cur, v, tc.lc, []byte("old-client"), []byte("old-consensus"))
				tc.lc.latestHeight = 3
			}

			if tc.wantAbort != "" {
				uassert.AbortsContains(t, cur, tc.wantAbort, func(cur realm) {
					v.ForceUpdateClient(0, cur, types.NewMsgForceUpdateClient(clientId, tc.clientState, tc.consensusState))
				})
				return
			}

			v.ForceUpdateClient(0, cur, types.NewMsgForceUpdateClient(clientId, tc.clientState, tc.consensusState))

			mc := v.store.(*mockStore).clients[uint32(clientId)]
			uassert.Equal(t, tc.wantClientState, string(mc.clientState))
			uassert.Equal(t, tc.wantConsensus, string(mc.consensus[types.NewHeight(tc.lc.latestHeight).String()]))
		})
	}
}

func TestVerifyMembership(cur realm, t *testing.T) {
	tests := []struct {
		name        string
		lc          *mockLightClient
		missing     bool
		wantAbort   string
		wantCalls   int
		wantNoAbort bool
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
