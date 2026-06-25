package impl

import (
	"testing"

	"gno.land/p/nt/uassert/v0"
	"gno.land/p/onbloc/ibc/union/lightclient"
	"gno.land/p/onbloc/ibc/union/types"
	core "gno.land/r/onbloc/ibc/union/core"
)

func TestConnectionOpenInit(cur realm, t *testing.T) {
	testing.SetRealm(testing.NewCodeRealm(coreRealmPath))
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

func TestConnectionOpenTryVerifiesAndSaves(cur realm, t *testing.T) {
	testing.SetRealm(testing.NewCodeRealm(coreRealmPath))
	v := newTestImpl()
	lc := &mockLightClient{}
	clientId := createClient(cur, v, lc, nil, nil)

	v.ConnectionOpenTry(0, cur, types.MsgConnectionOpenTry{
		ClientId:                 clientId,
		CounterpartyClientId:     types.ClientId(7),
		CounterpartyConnectionId: types.ConnectionId(3),
		ProofHeight:              10,
		ProofInit:                []byte("proof"),
	})

	conn, ok := v.store.GetConnection(types.ConnectionId(1))
	uassert.True(t, ok)
	uassert.True(t, conn.State == types.ConnectionStateTryOpen)
	uassert.Equal(t, uint32(3), uint32(conn.CounterpartyConnectionId))
	uassert.Equal(t, 1, lc.membershipCalls)
}

func TestConnectionOpenTryProofFailureAborts(cur realm, t *testing.T) {
	testing.SetRealm(testing.NewCodeRealm(coreRealmPath))
	v := newTestImpl()
	clientId := createClient(cur, v, &mockLightClient{membershipErr: "bad proof"}, nil, nil)

	uassert.AbortsContains(t, cur, "bad proof", func(cur realm) {
		testing.SetRealm(testing.NewCodeRealm(coreRealmPath))
		v.ConnectionOpenTry(0, cur, types.MsgConnectionOpenTry{
			ClientId:                 clientId,
			CounterpartyClientId:     types.ClientId(7),
			CounterpartyConnectionId: types.ConnectionId(3),
			ProofHeight:              10,
			ProofInit:                []byte("proof"),
		})
	})
}

func TestConnectionOpenAckMovesInitToOpen(cur realm, t *testing.T) {
	testing.SetRealm(testing.NewCodeRealm(coreRealmPath))
	v := newTestImpl()
	lc := &mockLightClient{}
	clientId := createClient(cur, v, lc, nil, nil)
	v.ConnectionOpenInit(0, cur, types.MsgConnectionOpenInit{ClientId: clientId, CounterpartyClientId: types.ClientId(7)})

	v.ConnectionOpenAck(0, cur, types.MsgConnectionOpenAck{
		ConnectionId:             types.ConnectionId(1),
		CounterpartyConnectionId: types.ConnectionId(5),
		ProofHeight:              10,
		ProofTry:                 []byte("proof"),
	})

	conn, _ := v.store.GetConnection(types.ConnectionId(1))
	uassert.True(t, conn.State == types.ConnectionStateOpen)
	uassert.Equal(t, uint32(5), uint32(conn.CounterpartyConnectionId))
	uassert.Equal(t, 1, lc.membershipCalls)
}

func TestConnectionOpenAckWrongStateAborts(cur realm, t *testing.T) {
	testing.SetRealm(testing.NewCodeRealm(coreRealmPath))
	v := newTestImpl()
	clientId := createClient(cur, v, &mockLightClient{}, nil, nil)
	// TryOpen (not Init) is the wrong state for an ack.
	v.ConnectionOpenTry(0, cur, types.MsgConnectionOpenTry{
		ClientId:                 clientId,
		CounterpartyClientId:     types.ClientId(7),
		CounterpartyConnectionId: types.ConnectionId(3),
		ProofHeight:              10,
		ProofInit:                []byte("proof"),
	})

	uassert.AbortsContains(t, cur, "invalid connection state", func(cur realm) {
		testing.SetRealm(testing.NewCodeRealm(coreRealmPath))
		v.ConnectionOpenAck(0, cur, types.MsgConnectionOpenAck{
			ConnectionId:             types.ConnectionId(1),
			CounterpartyConnectionId: types.ConnectionId(5),
			ProofHeight:              10,
			ProofTry:                 []byte("proof"),
		})
	})
}

func TestConnectionOpenConfirmMovesTryOpenToOpen(cur realm, t *testing.T) {
	testing.SetRealm(testing.NewCodeRealm(coreRealmPath))
	v := newTestImpl()
	clientId := createClient(cur, v, &mockLightClient{}, nil, nil)
	v.ConnectionOpenTry(0, cur, types.MsgConnectionOpenTry{
		ClientId:                 clientId,
		CounterpartyClientId:     types.ClientId(7),
		CounterpartyConnectionId: types.ConnectionId(3),
		ProofHeight:              10,
		ProofInit:                []byte("proof"),
	})

	v.ConnectionOpenConfirm(0, cur, types.MsgConnectionOpenConfirm{
		ConnectionId: types.ConnectionId(1),
		ProofHeight:  11,
		ProofAck:     []byte("proof"),
	})

	conn, _ := v.store.GetConnection(types.ConnectionId(1))
	uassert.True(t, conn.State == types.ConnectionStateOpen)
}

func TestConnectionOpenAckUnknownAborts(cur realm, t *testing.T) {
	testing.SetRealm(testing.NewCodeRealm(coreRealmPath))
	v := newTestImpl()

	uassert.AbortsContains(t, cur, "not found", func(cur realm) {
		testing.SetRealm(testing.NewCodeRealm(coreRealmPath))
		v.ConnectionOpenAck(0, cur, types.MsgConnectionOpenAck{ConnectionId: types.ConnectionId(99), ProofTry: []byte("p")})
	})
}

// Converted from Union connection_open_try_client_not_found:
// https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/core/src/tests/connection/ibc.rs#L170-L226
func TestConnectionOpenTryClientNotFound(cur realm, t *testing.T) {
	testing.SetRealm(testing.NewCodeRealm(coreRealmPath))
	v := newTestImpl()

	uassert.AbortsContains(t, cur, "client not found, 1", func(cur realm) {
		testing.SetRealm(testing.NewCodeRealm(coreRealmPath))
		v.ConnectionOpenTry(0, cur, types.MsgConnectionOpenTry{
			ClientId:                 types.ClientId(1),
			CounterpartyClientId:     types.ClientId(2),
			CounterpartyConnectionId: types.ConnectionId(1),
			ProofInit:                []byte{1, 2, 3},
			ProofHeight:              1,
		})
	})
}

// Converted from Union force_connection_open_try dispatch:
// https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/core/src/contract.rs#L195-L208
// A frozen client makes the proof-verifying path abort ("client is not active");
// the Force variant must skip verification and still save the connection.
func TestForceConnectionOpenTryBypassesProofVerification(cur realm, t *testing.T) {
	testing.SetRealm(testing.NewCodeRealm(coreRealmPath))
	v := newTestImpl()
	clientId := createClient(cur, v, &mockLightClient{status: lightclient.Frozen}, nil, nil)

	v.ForceConnectionOpenTry(0, cur, types.MsgConnectionOpenTry{
		ClientId:                 clientId,
		CounterpartyClientId:     types.ClientId(99),
		CounterpartyConnectionId: types.ConnectionId(77),
		ProofInit:                []byte("ignored-proof"),
		ProofHeight:              10,
	})

	conn, ok := v.store.GetConnection(types.ConnectionId(1))
	uassert.True(t, ok)
	uassert.True(t, conn.State == types.ConnectionStateTryOpen)
	uassert.Equal(t, uint32(77), uint32(conn.CounterpartyConnectionId))
}

// Converted from Union force_connection_open_ack dispatch:
// https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/core/src/contract.rs#L223-L234
func TestForceConnectionOpenAckBypassesProofVerification(cur realm, t *testing.T) {
	testing.SetRealm(testing.NewCodeRealm(coreRealmPath))
	v := newTestImpl()
	clientId := createClient(cur, v, &mockLightClient{status: lightclient.Frozen}, nil, nil)
	id := v.store.NextConnectionId(0, cur)
	v.store.SaveConnection(0, cur, id, core.NewConnection(types.ConnectionStateInit, clientId, types.ClientId(99), 0))

	v.ForceConnectionOpenAck(0, cur, types.MsgConnectionOpenAck{
		ConnectionId:             id,
		CounterpartyConnectionId: types.ConnectionId(77),
		ProofTry:                 []byte("ignored-proof"),
		ProofHeight:              10,
	})

	conn, ok := v.store.GetConnection(id)
	uassert.True(t, ok)
	uassert.True(t, conn.State == types.ConnectionStateOpen)
	uassert.Equal(t, uint32(77), uint32(conn.CounterpartyConnectionId))
}

// Converted from Union force_connection_open_confirm dispatch:
// https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/core/src/contract.rs#L247-L258
func TestForceConnectionOpenConfirmBypassesProofVerification(cur realm, t *testing.T) {
	testing.SetRealm(testing.NewCodeRealm(coreRealmPath))
	v := newTestImpl()
	clientId := createClient(cur, v, &mockLightClient{status: lightclient.Frozen}, nil, nil)
	id := v.store.NextConnectionId(0, cur)
	v.store.SaveConnection(0, cur, id, core.NewConnection(types.ConnectionStateTryOpen, clientId, types.ClientId(99), types.ConnectionId(77)))

	v.ForceConnectionOpenConfirm(0, cur, types.MsgConnectionOpenConfirm{
		ConnectionId: id,
		ProofAck:     []byte("ignored-proof"),
		ProofHeight:  10,
	})

	conn, ok := v.store.GetConnection(id)
	uassert.True(t, ok)
	uassert.True(t, conn.State == types.ConnectionStateOpen)
}

func TestPrivateConnectionOpenTry(cur realm, t *testing.T) {
	testing.SetRealm(testing.NewCodeRealm(coreRealmPath))
	cases := []struct {
		name      string
		lc        *mockLightClient
		verify    bool
		wantPanic string
		wantCalls int
	}{
		{"verified", &mockLightClient{}, true, "", 1},
		{"unverified", &mockLightClient{}, false, "", 0},
		{"proof failure", &mockLightClient{membershipErr: "bad proof"}, true, "bad proof", 1},
		{"inactive client", &mockLightClient{status: lightclient.Expired}, true, "client is not active", 0},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			v := newTestImpl()
			clientId := createClient(cur, v, tc.lc, nil, nil)
			msg := types.MsgConnectionOpenTry{
				ClientId:                 clientId,
				CounterpartyClientId:     types.ClientId(7),
				CounterpartyConnectionId: types.ConnectionId(3),
				ProofHeight:              10,
				ProofInit:                []byte("proof"),
			}
			run := func(cur realm) {
				testing.SetRealm(testing.NewCodeRealm(coreRealmPath))
				v.connectionOpenTry(0, cur, msg, tc.verify)
			}
			if tc.wantPanic != "" {
				uassert.AbortsContains(t, cur, tc.wantPanic, run)
			} else {
				uassert.NotAborts(t, cur, run)
				conn, ok := v.store.GetConnection(types.ConnectionId(1))
				uassert.True(t, ok)
				uassert.True(t, conn.State == types.ConnectionStateTryOpen)
			}
			uassert.Equal(t, tc.wantCalls, tc.lc.membershipCalls)
		})
	}
}

func TestPrivateConnectionOpenAck(cur realm, t *testing.T) {
	testing.SetRealm(testing.NewCodeRealm(coreRealmPath))
	cases := []struct {
		name      string
		state     types.ConnectionState
		verify    bool
		lc        *mockLightClient
		wantPanic string
		wantCalls int
	}{
		{"verified", types.ConnectionStateInit, true, &mockLightClient{}, "", 1},
		{"unverified", types.ConnectionStateInit, false, &mockLightClient{}, "", 0},
		{"wrong state", types.ConnectionStateTryOpen, false, &mockLightClient{}, "invalid connection state", 0},
		{"proof failure", types.ConnectionStateInit, true, &mockLightClient{membershipErr: "bad proof"}, "bad proof", 1},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			v := newTestImpl()
			clientId := createClient(cur, v, tc.lc, nil, nil)
			id := v.store.NextConnectionId(0, cur)
			v.store.SaveConnection(0, cur, id, core.NewConnection(tc.state, clientId, types.ClientId(7), 0))
			msg := types.MsgConnectionOpenAck{
				ConnectionId:             id,
				CounterpartyConnectionId: types.ConnectionId(5),
				ProofHeight:              10,
				ProofTry:                 []byte("proof"),
			}
			run := func(cur realm) {
				testing.SetRealm(testing.NewCodeRealm(coreRealmPath))
				v.connectionOpenAck(0, cur, msg, tc.verify)
			}
			if tc.wantPanic != "" {
				uassert.AbortsContains(t, cur, tc.wantPanic, run)
			} else {
				uassert.NotAborts(t, cur, run)
				conn, _ := v.store.GetConnection(id)
				uassert.True(t, conn.State == types.ConnectionStateOpen)
			}
			uassert.Equal(t, tc.wantCalls, tc.lc.membershipCalls)
		})
	}
}

func TestPrivateConnectionOpenConfirm(cur realm, t *testing.T) {
	testing.SetRealm(testing.NewCodeRealm(coreRealmPath))
	cases := []struct {
		name      string
		state     types.ConnectionState
		verify    bool
		lc        *mockLightClient
		wantPanic string
		wantCalls int
	}{
		{"verified", types.ConnectionStateTryOpen, true, &mockLightClient{}, "", 1},
		{"unverified", types.ConnectionStateTryOpen, false, &mockLightClient{}, "", 0},
		{"wrong state", types.ConnectionStateInit, false, &mockLightClient{}, "invalid connection state", 0},
		{"proof failure", types.ConnectionStateTryOpen, true, &mockLightClient{membershipErr: "bad proof"}, "bad proof", 1},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			v := newTestImpl()
			clientId := createClient(cur, v, tc.lc, nil, nil)
			id := v.store.NextConnectionId(0, cur)
			v.store.SaveConnection(0, cur, id, core.NewConnection(tc.state, clientId, types.ClientId(7), types.ConnectionId(5)))
			msg := types.MsgConnectionOpenConfirm{
				ConnectionId: id,
				ProofHeight:  10,
				ProofAck:     []byte("proof"),
			}
			run := func(cur realm) {
				testing.SetRealm(testing.NewCodeRealm(coreRealmPath))
				v.connectionOpenConfirm(0, cur, msg, tc.verify)
			}
			if tc.wantPanic != "" {
				uassert.AbortsContains(t, cur, tc.wantPanic, run)
			} else {
				uassert.NotAborts(t, cur, run)
				conn, _ := v.store.GetConnection(id)
				uassert.True(t, conn.State == types.ConnectionStateOpen)
			}
			uassert.Equal(t, tc.wantCalls, tc.lc.membershipCalls)
		})
	}
}

// --- ensureConnectionState ---

func TestEnsureConnectionOpenPanicsOnInit(cur realm, t *testing.T) {
	testing.SetRealm(testing.NewCodeRealm(coreRealmPath))
	v := newTestImpl()
	clientId := createClient(cur, v, &mockLightClient{}, nil, nil)
	id := v.store.NextConnectionId(0, cur)
	v.store.SaveConnection(0, cur, id, core.NewConnection(types.ConnectionStateInit, clientId, types.ClientId(7), 0))

	uassert.AbortsContains(t, cur, "invalid connection state", func(cur realm) {
		testing.SetRealm(testing.NewCodeRealm(coreRealmPath))
		v.ensureConnectionState(id)
	})
}

func TestEnsureConnectionOpenSucceeds(cur realm, t *testing.T) {
	testing.SetRealm(testing.NewCodeRealm(coreRealmPath))
	v := newTestImpl()
	clientId := createClient(cur, v, &mockLightClient{}, nil, nil)
	id := v.store.NextConnectionId(0, cur)
	v.store.SaveConnection(0, cur, id, core.NewConnection(types.ConnectionStateOpen, clientId, types.ClientId(7), types.ConnectionId(99)))

	conn := v.ensureConnectionState(id)
	uassert.True(t, conn.State == types.ConnectionStateOpen)
}

func TestEnsureConnectionOpenAllowsMissingCounterpartyConnectionId(cur realm, t *testing.T) {
	testing.SetRealm(testing.NewCodeRealm(coreRealmPath))
	v := newTestImpl()
	clientId := createClient(cur, v, &mockLightClient{}, nil, nil)
	id := v.store.NextConnectionId(0, cur)
	v.store.SaveConnection(0, cur, id, core.NewConnection(types.ConnectionStateOpen, clientId, types.ClientId(7), 0))

	conn := v.ensureConnectionState(id)
	uassert.True(t, conn.State == types.ConnectionStateOpen)
}
