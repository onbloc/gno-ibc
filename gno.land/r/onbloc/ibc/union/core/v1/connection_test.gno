package impl

import (
	"testing"

	"gno.land/p/nt/uassert/v0"
	"gno.land/p/onbloc/ibc/union/types"
)

func TestConnectionOpenInit(cur realm, t *testing.T) {
	v := newTestImpl()
	clientId := v.CreateClient(0, cur, types.ClientType("cometbls"), &mockLightClient{})

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
	clientId := v.CreateClient(0, cur, types.ClientType("cometbls"), &mockLightClient{})

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
	clientId := v.CreateClient(0, cur, types.ClientType("cometbls"), &mockLightClient{membershipErr: "bad proof"})

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
	clientId := v.CreateClient(0, cur, types.ClientType("cometbls"), &mockLightClient{})
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
	clientId := v.CreateClient(0, cur, types.ClientType("cometbls"), &mockLightClient{})
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
	clientId := v.CreateClient(0, cur, types.ClientType("cometbls"), &mockLightClient{})
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
