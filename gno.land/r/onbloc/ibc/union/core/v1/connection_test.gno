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

func TestConnectionOpenTryVerifiesAndSaves(cur realm, t *testing.T) {
	v := newTestImpl()
	clientId := createClient(cur, v, &mockLightClient{}, nil, nil)

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
}

func TestConnectionOpenTryProofFailureAborts(cur realm, t *testing.T) {
	v := newTestImpl()
	clientId := createClient(cur, v, &mockLightClient{membershipErr: "bad proof"}, nil, nil)

	uassert.AbortsContains(t, cur, "bad proof", func(cur realm) {
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
	v := newTestImpl()
	clientId := createClient(cur, v, &mockLightClient{}, nil, nil)
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
}

func TestConnectionOpenAckWrongStateAborts(cur realm, t *testing.T) {
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
		v.ConnectionOpenAck(0, cur, types.MsgConnectionOpenAck{
			ConnectionId:             types.ConnectionId(1),
			CounterpartyConnectionId: types.ConnectionId(5),
			ProofHeight:              10,
			ProofTry:                 []byte("proof"),
		})
	})
}

func TestConnectionOpenConfirmMovesTryOpenToOpen(cur realm, t *testing.T) {
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
	v := newTestImpl()

	uassert.AbortsContains(t, cur, "not found", func(cur realm) {
		v.ConnectionOpenAck(0, cur, types.MsgConnectionOpenAck{ConnectionId: types.ConnectionId(99), ProofTry: []byte("p")})
	})
}

// Converted from Union connection_open_try_client_not_found:
// https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/core/src/tests/connection/ibc.rs#L170-L226
func TestConnectionOpenTryClientNotFound(cur realm, t *testing.T) {
	v := newTestImpl()

	uassert.AbortsContains(t, cur, "client 1 not found", func(cur realm) {
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

// --- ensureConnectionOpen ---

func TestEnsureConnectionOpenPanicsOnInit(cur realm, t *testing.T) {
	v := newTestImpl()
	clientId := createClient(cur, v, &mockLightClient{}, nil, nil)
	id := v.store.NextConnectionId(0, cur)
	v.store.SaveConnection(0, cur, id, core.NewConnection(types.ConnectionStateInit, clientId, types.ClientId(7), 0))

	uassert.AbortsContains(t, cur, "invalid connection state", func(cur realm) {
		v.ensureConnectionOpen(id)
	})
}

func TestEnsureConnectionOpenSucceeds(cur realm, t *testing.T) {
	v := newTestImpl()
	clientId := createClient(cur, v, &mockLightClient{}, nil, nil)
	id := v.store.NextConnectionId(0, cur)
	v.store.SaveConnection(0, cur, id, core.NewConnection(types.ConnectionStateOpen, clientId, types.ClientId(7), types.ConnectionId(99)))

	conn := v.ensureConnectionOpen(id)
	uassert.True(t, conn.State == types.ConnectionStateOpen)
}

func TestEnsureConnectionOpenAllowsMissingCounterpartyConnectionId(cur realm, t *testing.T) {
	v := newTestImpl()
	clientId := createClient(cur, v, &mockLightClient{}, nil, nil)
	id := v.store.NextConnectionId(0, cur)
	v.store.SaveConnection(0, cur, id, core.NewConnection(types.ConnectionStateOpen, clientId, types.ClientId(7), 0))

	conn := v.ensureConnectionOpen(id)
	uassert.True(t, conn.State == types.ConnectionStateOpen)
}
