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

	uassert.True(t, v.GetStatus(clientId) == types.StatusActive)

	typ, ok := v.GetClientType(clientId)
	uassert.True(t, ok)
	uassert.Equal(t, "cometbls", string(typ))

	implId, ok := v.GetClientImpl(clientId)
	uassert.True(t, ok)
	uassert.Equal(t, "cometbls", implId)

	cs, ok := v.GetClientStateBytes(clientId)
	uassert.True(t, ok)
	uassert.Equal(t, "client-state", string(cs))

	cons, ok := v.GetConsensusStateBytes(clientId, types.NewHeight(5))
	uassert.True(t, ok)
	uassert.Equal(t, "consensus-5", string(cons))

	h, ok := v.GetLatestHeight(clientId)
	uassert.True(t, ok)
	uassert.Equal(t, uint64(42), h)

	ts, ok := v.GetTimestampAtHeight(clientId, 5)
	uassert.True(t, ok)
	uassert.Equal(t, uint64(123), uint64(ts))
}

func TestGetMissingClient(cur realm, t *testing.T) {
	v := newTestImpl()

	uassert.True(t, v.GetStatus(types.ClientId(99)) == types.StatusUnknown)
	_, ok := v.GetClientType(types.ClientId(99))
	uassert.False(t, ok)
	_, ok = v.GetLatestHeight(types.ClientId(99))
	uassert.False(t, ok)
	_, ok = v.GetClientStateBytes(types.ClientId(99))
	uassert.False(t, ok)
}

func TestGetFrozenStatus(cur realm, t *testing.T) {
	v := newTestImpl()
	clientId := createClient(cur, v, &mockLightClient{status: lightclient.Frozen}, nil, nil)

	uassert.True(t, v.GetStatus(clientId) == types.StatusFrozen)
}

func TestGetBestEffortGetters(cur realm, t *testing.T) {
	v := newTestImpl()

	// gno has no client-type registry and no per-app channel set.
	uassert.False(t, v.GetRegisteredClientType(types.ClientType("cometbls")))
	uassert.Equal(t, 0, len(v.GetChannels("some-app")))
}

func TestGetConnectionAndChannel(cur realm, t *testing.T) {
	v := newTestImpl()
	ms := v.store.(*mockStore)
	ms.SaveConnection(0, cur, types.ConnectionId(1),
		core.NewConnection(types.ConnectionStateOpen, types.ClientId(1), types.ClientId(7), types.ConnectionId(2)))
	ms.channels[3] = types.Channel{State: types.ChannelStateOpen, ConnectionId: types.ConnectionId(1)}

	conn, ok := v.GetConnectionTyped(types.ConnectionId(1))
	uassert.True(t, ok)
	uassert.True(t, conn.State == types.ConnectionStateOpen)

	ch, ok := v.GetChannelTyped(types.ChannelId(3))
	uassert.True(t, ok)
	uassert.True(t, ch.State == types.ChannelStateOpen)

	_, ok = v.GetConnectionTyped(types.ConnectionId(99))
	uassert.False(t, ok)
}
