package impl

import (
	"testing"

	"gno.land/p/nt/uassert/v0"
	"gno.land/p/onbloc/ibc/union/lightclient"
	"gno.land/p/onbloc/ibc/union/types"
	core "gno.land/r/onbloc/ibc/union/core"
)

func TestConnectionOpenInit(cur realm, t *testing.T) {
	v := newTestImpl()
	clientId := createClient(cur, v, &mockLightClient{}, nil, nil)

	v.ConnectionOpenInit(0, cur, types.MsgConnectionOpenInit{
		ClientId:             clientId,
		CounterpartyClientId: types.ClientId(7),
	})

	conn, ok := v.store.GetConnection(types.ConnectionId(1))
	uassert.True(t, ok)
	uassert.True(t, conn.State == types.ConnectionStateInit)
	uassert.Equal(t, uint32(clientId), uint32(conn.ClientId))
	uassert.Equal(t, uint32(7), uint32(conn.CounterpartyClientId))
}

func TestConnectionProofEntrypointsInactiveClientAbortBeforeVerification(cur realm, t *testing.T) {
	tests := []struct {
		name string
		run  func(cur realm, v *coreV1, lc *mockLightClient, clientId types.ClientId)
	}{
		{
			name: "open try",
			run: func(cur realm, v *coreV1, lc *mockLightClient, clientId types.ClientId) {
				v.ConnectionOpenTry(0, cur, types.MsgConnectionOpenTry{
					ClientId:                 clientId,
					CounterpartyClientId:     types.ClientId(7),
					CounterpartyConnectionId: types.ConnectionId(3),
					ProofHeight:              10,
					ProofInit:                []byte("proof"),
				})
			},
		},
		{
			name: "open ack",
			run: func(cur realm, v *coreV1, lc *mockLightClient, clientId types.ClientId) {
				v.ConnectionOpenInit(0, cur, types.MsgConnectionOpenInit{
					ClientId:             clientId,
					CounterpartyClientId: types.ClientId(7),
				})
				v.ConnectionOpenAck(0, cur, types.MsgConnectionOpenAck{
					ConnectionId:             types.ConnectionId(1),
					CounterpartyConnectionId: types.ConnectionId(5),
					ProofHeight:              10,
					ProofTry:                 []byte("proof"),
				})
			},
		},
		{
			name: "open confirm",
			run: func(cur realm, v *coreV1, lc *mockLightClient, clientId types.ClientId) {
				v.store.SaveConnection(0, cur, types.ConnectionId(1),
					core.NewConnection(types.ConnectionStateTryOpen, clientId, types.ClientId(7), types.ConnectionId(5)))
				v.ConnectionOpenConfirm(0, cur, types.MsgConnectionOpenConfirm{
					ConnectionId: types.ConnectionId(1),
					ProofHeight:  10,
					ProofAck:     []byte("proof"),
				})
			},
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			v := newTestImpl()
			lc := &mockLightClient{status: lightclient.Frozen}
			clientId := createClient(cur, v, lc, nil, nil)

			uassert.AbortsContains(t, cur, "client is not active", func(cur realm) {
				tc.run(cur, v, lc, clientId)
			})
			uassert.Equal(t, 0, lc.membershipCalls)
		})
	}
}

func TestConnectionOpenTry(cur realm, t *testing.T) {
	tests := []struct {
		name            string
		lc              *mockLightClient
		verify          bool
		missingClient   bool
		wantAbort       string
		wantCalls       int
		wantSaved       bool
	}{
		{"verifies proof and saves try-open", &mockLightClient{}, true, false, "", 1, true},
		{"force path skips proof verification", &mockLightClient{status: lightclient.Frozen}, false, false, "", 0, true},
		// Converted from Union connection_open_try_client_not_found:
		// https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/core/src/tests/connection/ibc.rs#L170-L226
		{"missing client aborts when verifying", &mockLightClient{}, true, true, "client 1 not found", 0, false},
		{"proof failure aborts", &mockLightClient{membershipErr: "bad proof"}, true, false, "bad proof", 1, false},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			v := newTestImpl()
			clientId := types.ClientId(1)
			if !tc.missingClient {
				clientId = createClient(cur, v, tc.lc, nil, nil)
			}
			msg := types.MsgConnectionOpenTry{
				ClientId:                 clientId,
				CounterpartyClientId:     types.ClientId(7),
				CounterpartyConnectionId: types.ConnectionId(3),
				ProofHeight:              10,
				ProofInit:                []byte("proof"),
			}

			run := func(cur realm) {
				v.connectionOpenTry(0, cur, msg, tc.verify)
			}
			if tc.wantAbort != "" {
				uassert.AbortsContains(t, cur, tc.wantAbort, run)
			} else {
				uassert.NotAborts(t, cur, func() {
					v.connectionOpenTry(0, cur, msg, tc.verify)
				})
			}
			uassert.Equal(t, tc.wantCalls, tc.lc.membershipCalls)
			_, ok := v.store.GetConnection(types.ConnectionId(1))
			uassert.Equal(t, tc.wantSaved, ok)
		})
	}
}

func TestConnectionOpenAck(cur realm, t *testing.T) {
	tests := []struct {
		name       string
		lc         *mockLightClient
		verify     bool
		seedState  types.ConnectionState
		missing    bool
		wantAbort  string
		wantCalls  int
		wantOpen   bool
	}{
		{"verifies proof and opens init connection", &mockLightClient{}, true, types.ConnectionStateInit, false, "", 1, true},
		{"force path skips proof verification", &mockLightClient{status: lightclient.Frozen}, false, types.ConnectionStateInit, false, "", 0, true},
		{"missing connection aborts", &mockLightClient{}, true, types.ConnectionStateInit, true, "connection 1 not found", 0, false},
		// TryOpen (not Init) is the wrong state for an ack.
		{"wrong state aborts before proof", &mockLightClient{}, true, types.ConnectionStateTryOpen, false, "invalid connection state", 0, false},
		{"proof failure aborts", &mockLightClient{membershipErr: "bad proof"}, true, types.ConnectionStateInit, false, "bad proof", 1, false},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			v := newTestImpl()
			clientId := createClient(cur, v, tc.lc, nil, nil)
			if !tc.missing {
				v.store.SaveConnection(0, cur, types.ConnectionId(1),
					core.NewConnection(tc.seedState, clientId, types.ClientId(7), types.ConnectionId(3)))
			}
			msg := types.MsgConnectionOpenAck{
				ConnectionId:             types.ConnectionId(1),
				CounterpartyConnectionId: types.ConnectionId(5),
				ProofHeight:              10,
				ProofTry:                 []byte("proof"),
			}

			run := func(cur realm) {
				v.connectionOpenAck(0, cur, msg, tc.verify)
			}
			if tc.wantAbort != "" {
				uassert.AbortsContains(t, cur, tc.wantAbort, run)
			} else {
				uassert.NotAborts(t, cur, func() {
					v.connectionOpenAck(0, cur, msg, tc.verify)
				})
			}
			uassert.Equal(t, tc.wantCalls, tc.lc.membershipCalls)
			conn, ok := v.store.GetConnection(types.ConnectionId(1))
			uassert.Equal(t, !tc.missing, ok)
			if tc.wantOpen {
				uassert.True(t, conn.State == types.ConnectionStateOpen)
				uassert.Equal(t, uint32(5), uint32(conn.CounterpartyConnectionId))
			}
		})
	}
}

func TestConnectionOpenConfirm(cur realm, t *testing.T) {
	tests := []struct {
		name       string
		lc         *mockLightClient
		verify     bool
		seedState  types.ConnectionState
		missing    bool
		wantAbort  string
		wantCalls  int
		wantOpen   bool
	}{
		{"verifies proof and opens try-open connection", &mockLightClient{}, true, types.ConnectionStateTryOpen, false, "", 1, true},
		{"force path skips proof verification", &mockLightClient{status: lightclient.Frozen}, false, types.ConnectionStateTryOpen, false, "", 0, true},
		{"missing connection aborts", &mockLightClient{}, true, types.ConnectionStateTryOpen, true, "connection 1 not found", 0, false},
		{"wrong state aborts before proof", &mockLightClient{}, true, types.ConnectionStateOpen, false, "invalid connection state", 0, false},
		{"proof failure aborts", &mockLightClient{membershipErr: "bad proof"}, true, types.ConnectionStateTryOpen, false, "bad proof", 1, false},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			v := newTestImpl()
			clientId := createClient(cur, v, tc.lc, nil, nil)
			if !tc.missing {
				v.store.SaveConnection(0, cur, types.ConnectionId(1),
					core.NewConnection(tc.seedState, clientId, types.ClientId(7), types.ConnectionId(5)))
			}
			msg := types.MsgConnectionOpenConfirm{
				ConnectionId: types.ConnectionId(1),
				ProofHeight:  10,
				ProofAck:     []byte("proof"),
			}

			run := func(cur realm) {
				v.connectionOpenConfirm(0, cur, msg, tc.verify)
			}
			if tc.wantAbort != "" {
				uassert.AbortsContains(t, cur, tc.wantAbort, run)
			} else {
				uassert.NotAborts(t, cur, func() {
					v.connectionOpenConfirm(0, cur, msg, tc.verify)
				})
			}
			uassert.Equal(t, tc.wantCalls, tc.lc.membershipCalls)
			conn, ok := v.store.GetConnection(types.ConnectionId(1))
			uassert.Equal(t, !tc.missing, ok)
			if tc.wantOpen {
				uassert.True(t, conn.State == types.ConnectionStateOpen)
			}
		})
	}
}

func TestForceConnectionOpenBypassesProofVerification(cur realm, t *testing.T) {
	tests := []struct {
		name           string
		wantState      types.ConnectionState
		wantCounterId  types.ConnectionId
		seedConnection func(cur realm, v *coreV1, clientId types.ClientId) types.ConnectionId
		run            func(cur realm, v *coreV1, id types.ConnectionId, clientId types.ClientId)
	}{
		{
			// Converted from Union force_connection_open_try dispatch:
			// https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/core/src/contract.rs#L195-L208
			// A frozen client makes the proof-verifying path abort ("client is not active");
			// the Force variant must skip verification and still save the connection.
			name:          "try",
			wantState:     types.ConnectionStateTryOpen,
			wantCounterId: types.ConnectionId(77),
			seedConnection: func(cur realm, v *coreV1, clientId types.ClientId) types.ConnectionId {
				return types.ConnectionId(1)
			},
			run: func(cur realm, v *coreV1, id types.ConnectionId, clientId types.ClientId) {
				v.ForceConnectionOpenTry(0, cur, types.MsgConnectionOpenTry{
					ClientId:                 clientId,
					CounterpartyClientId:     types.ClientId(99),
					CounterpartyConnectionId: types.ConnectionId(77),
					ProofInit:                []byte("ignored-proof"),
					ProofHeight:              10,
				})
			},
		},
		{
			// Converted from Union force_connection_open_ack dispatch:
			// https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/core/src/contract.rs#L223-L234
			name:          "ack",
			wantState:     types.ConnectionStateOpen,
			wantCounterId: types.ConnectionId(77),
			seedConnection: func(cur realm, v *coreV1, clientId types.ClientId) types.ConnectionId {
				id := v.store.NextConnectionId(0, cur)
				v.store.SaveConnection(0, cur, id, core.NewConnection(types.ConnectionStateInit, clientId, types.ClientId(99), 0))
				return id
			},
			run: func(cur realm, v *coreV1, id types.ConnectionId, clientId types.ClientId) {
				v.ForceConnectionOpenAck(0, cur, types.MsgConnectionOpenAck{
					ConnectionId:             id,
					CounterpartyConnectionId: types.ConnectionId(77),
					ProofTry:                 []byte("ignored-proof"),
					ProofHeight:              10,
				})
			},
		},
		{
			// Converted from Union force_connection_open_confirm dispatch:
			// https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/core/src/contract.rs#L247-L258
			name:          "confirm",
			wantState:     types.ConnectionStateOpen,
			wantCounterId: types.ConnectionId(77),
			seedConnection: func(cur realm, v *coreV1, clientId types.ClientId) types.ConnectionId {
				id := v.store.NextConnectionId(0, cur)
				v.store.SaveConnection(0, cur, id, core.NewConnection(types.ConnectionStateTryOpen, clientId, types.ClientId(99), types.ConnectionId(77)))
				return id
			},
			run: func(cur realm, v *coreV1, id types.ConnectionId, clientId types.ClientId) {
				v.ForceConnectionOpenConfirm(0, cur, types.MsgConnectionOpenConfirm{
					ConnectionId: id,
					ProofAck:     []byte("ignored-proof"),
					ProofHeight:  10,
				})
			},
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			v := newTestImpl()
			clientId := createClient(cur, v, &mockLightClient{status: lightclient.Frozen}, nil, nil)
			id := tc.seedConnection(cur, v, clientId)

			tc.run(cur, v, id, clientId)

			conn, ok := v.store.GetConnection(id)
			uassert.True(t, ok)
			uassert.True(t, conn.State == tc.wantState)
			uassert.Equal(t, uint32(tc.wantCounterId), uint32(conn.CounterpartyConnectionId))
		})
	}
}

func TestEnsureConnectionState(cur realm, t *testing.T) {
	tests := []struct {
		name             string
		state            types.ConnectionState
		counterpartyConn types.ConnectionId
		missing          bool
		wantAbort        string
	}{
		{"missing connection", types.ConnectionStateOpen, 0, true, "connection 1 not found"},
		{"init state aborts", types.ConnectionStateInit, 0, false, "invalid connection state"},
		{"open succeeds", types.ConnectionStateOpen, types.ConnectionId(99), false, ""},
		{"open allows missing counterparty connection id", types.ConnectionStateOpen, 0, false, ""},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			v := newTestImpl()
			clientId := createClient(cur, v, &mockLightClient{}, nil, nil)
			id := types.ConnectionId(1)
			if !tc.missing {
				v.store.SaveConnection(0, cur, id,
					core.NewConnection(tc.state, clientId, types.ClientId(7), tc.counterpartyConn))
			}

			if tc.wantAbort != "" {
				uassert.AbortsContains(t, cur, tc.wantAbort, func(cur realm) {
					v.ensureConnectionState(id)
				})
				return
			}

			conn := v.ensureConnectionState(id)
			uassert.True(t, conn.State == types.ConnectionStateOpen)
			uassert.Equal(t, uint32(tc.counterpartyConn), uint32(conn.CounterpartyConnectionId))
		})
	}
}
