package impl

import (
	"testing"

	"gno.land/p/nt/uassert/v0"
	"gno.land/p/onbloc/ibc/union/lightclient"
	"gno.land/p/onbloc/ibc/union/types"
	core "gno.land/r/onbloc/ibc/union/core"
)

func TestGetClientGetters(cur realm, t *testing.T) {
	v := newTestImpl()
	lc := &mockLightClient{latestHeight: 42, timestampAtHt: types.Timestamp(123)}
	clientId := createClient(cur, v, lc, nil, nil)
	v.UpdateClient(0, cur, types.MsgUpdateClient{
		ClientId:      clientId,
		ClientMessage: []byte("h"),
	})
	// UpdateClient with a zero-height update writes nothing; set state explicitly.
	v.store.SaveClientState(0, cur, clientId, []byte("client-state"))
	v.store.SaveConsensusState(0, cur, clientId, types.NewHeight(5), []byte("consensus-5"))

	status, err := v.GetStatus(clientId)
	uassert.NoError(t, err)
	uassert.True(t, status == types.StatusActive)

	typ, err := v.GetClientType(clientId)
	uassert.NoError(t, err)
	uassert.Equal(t, "cometbls", string(typ))

	implId, err := v.GetClientImpl(clientId)
	uassert.NoError(t, err)
	uassert.Equal(t, "cometbls", implId)

	cs, err := v.GetClientStateBytes(clientId)
	uassert.NoError(t, err)
	uassert.Equal(t, "client-state", string(cs))

	cons, err := v.GetConsensusStateBytes(clientId, types.NewHeight(5))
	uassert.NoError(t, err)
	uassert.Equal(t, "consensus-5", string(cons))

	h, err := v.GetLatestHeight(clientId)
	uassert.NoError(t, err)
	uassert.Equal(t, uint64(42), h)

	ts, err := v.GetTimestampAtHeight(clientId, 5)
	uassert.NoError(t, err)
	uassert.Equal(t, uint64(123), uint64(ts))
}

func TestGetMissingClient(cur realm, t *testing.T) {
	v := newTestImpl()

	_, err := v.GetStatus(types.ClientId(99))
	uassert.ErrorIs(t, err, core.ErrClientNotFound)
	_, err = v.GetClientType(types.ClientId(99))
	uassert.ErrorIs(t, err, core.ErrClientNotFound)
	_, err = v.GetLatestHeight(types.ClientId(99))
	uassert.ErrorIs(t, err, core.ErrClientNotFound)
	_, err = v.GetClientStateBytes(types.ClientId(99))
	uassert.ErrorIs(t, err, core.ErrClientStateNotFound)
	_, err = v.GetConsensusStateBytes(types.ClientId(99), types.NewHeight(1))
	uassert.ErrorIs(t, err, core.ErrConsensusStateNotFound)
}

func TestGetFrozenStatus(cur realm, t *testing.T) {
	v := newTestImpl()
	clientId := createClient(cur, v, &mockLightClient{status: lightclient.Frozen}, nil, nil)

	status, err := v.GetStatus(clientId)
	uassert.NoError(t, err)
	uassert.True(t, status == types.StatusFrozen)
}

func TestGetBestEffortGetters(cur realm, t *testing.T) {
	v := newTestImpl()

	// gno has no client-type registry.
	uassert.False(t, v.GetRegisteredClientType(types.ClientType("cometbls")))
}

func TestGetConnectionAndChannel(cur realm, t *testing.T) {
	v := newTestImpl()
	ms := v.store.(*mockStore)
	ms.SaveConnection(0, cur, types.ConnectionId(1),
		core.NewConnection(types.ConnectionStateOpen, types.ClientId(1), types.ClientId(7), types.ConnectionId(2)))
	ms.channels[3] = types.Channel{State: types.ChannelStateOpen, ConnectionId: types.ConnectionId(1)}

	conn, err := v.GetConnection(types.ConnectionId(1))
	uassert.NoError(t, err)
	uassert.True(t, conn.State == types.ConnectionStateOpen)

	ch, err := v.GetChannel(types.ChannelId(3))
	uassert.NoError(t, err)
	uassert.True(t, ch.State == types.ChannelStateOpen)

	_, err = v.GetConnection(types.ConnectionId(99))
	uassert.ErrorIs(t, err, core.ErrConnectionNotFound)
}

func TestGetBatchPacketAndReceiptCommitments(cur realm, t *testing.T) {
	v := newTestImpl()
	chId := types.ChannelId(7)
	batchHash := types.Keccak([]byte("batch"))
	packetValue := types.Keccak([]byte("packets"))
	receiptValue := types.Keccak([]byte("receipts"))

	v.store.SaveBatchPackets(0, cur, chId, batchHash, packetValue)
	v.store.SaveBatchReceipts(0, cur, chId, batchHash, receiptValue)

	gotPacket, err := v.GetBatchPacketsCommitment(batchHash)
	uassert.NoError(t, err)
	uassert.True(t, gotPacket == packetValue)

	gotReceipt, err := v.GetBatchReceiptsCommitment(batchHash)
	uassert.NoError(t, err)
	uassert.True(t, gotReceipt == receiptValue)

	_, err = v.GetBatchPacketsCommitment(types.Keccak([]byte("missing")))
	uassert.ErrorIs(t, err, core.ErrBatchPacketsNotFound)
	_, err = v.GetBatchReceiptsCommitment(types.Keccak([]byte("missing")))
	uassert.ErrorIs(t, err, core.ErrBatchReceiptsNotFound)
}
