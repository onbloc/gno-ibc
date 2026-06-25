package core

import (
	"strconv"
	"testing"

	"gno.land/p/nt/uassert/v0"
	"gno.land/p/onbloc/ibc/union/types"
)

// --- QueryClientState ---

func TestQueryClientStateReturnsHex(cur realm, t *testing.T) {
	resetStore(cur)
	clientId := registerMockClient(&mockClient{status: types.StatusActive})
	raw := []byte("client-state-bytes")
	store.SaveClientState(0, cur, clientId, raw)

	got := QueryClientState(clientId)
	want := hexString(raw)
	uassert.Equal(t, want, got)
}

func TestQueryClientStateMissingReturnsEmpty(cur realm, t *testing.T) {
	resetStore(cur)
	uassert.Equal(t, "", QueryClientState(types.ClientId(999)))
}

// --- QueryConsensusState ---

func TestQueryConsensusStateReturnsHex(cur realm, t *testing.T) {
	resetStore(cur)
	clientId := registerMockClient(&mockClient{status: types.StatusActive})
	raw := []byte("consensus-state-bytes")
	height := uint64(42)
	store.SaveConsensusState(0, cur, clientId, types.NewHeight(0, height), raw)

	got := QueryConsensusState(clientId, height)
	want := hexString(raw)
	uassert.Equal(t, want, got)
}

func TestQueryConsensusStateMissingReturnsEmpty(cur realm, t *testing.T) {
	resetStore(cur)
	clientId := registerMockClient(&mockClient{status: types.StatusActive})
	uassert.Equal(t, "", QueryConsensusState(clientId, 999))
}

func TestQueryConsensusStateWrongHeightReturnsEmpty(cur realm, t *testing.T) {
	resetStore(cur)
	clientId := registerMockClient(&mockClient{status: types.StatusActive})
	store.SaveConsensusState(0, cur, clientId, types.NewHeight(0, 10), []byte("cs"))

	uassert.Equal(t, "", QueryConsensusState(clientId, 99))
}

// --- QueryConnection ---

func TestQueryConnectionReturnsABIHex(cur realm, t *testing.T) {
	resetStore(cur)
	clientId := registerMockClient(&mockClient{status: types.StatusActive})
	conn := types.Connection{
		State:                    types.ConnectionStateOpen,
		ClientId:                 clientId,
		CounterpartyClientId:     types.ClientId(99),
		CounterpartyConnectionId: types.ConnectionId(99),
	}
	id := store.nextConnectionId()
	store.saveConnection(id, conn)

	got := QueryConnection(id)
	want := hexString(mustEncodeABI(conn.EncodeABI()))
	uassert.Equal(t, want, got)
}

func TestQueryConnectionMissingReturnsEmpty(cur realm, t *testing.T) {
	resetStore(cur)
	uassert.Equal(t, "", QueryConnection(types.ConnectionId(999)))
}

// --- QueryChannel ---

func TestQueryChannelReturnsABIHex(cur realm, t *testing.T) {
	resetStore(cur)
	_, _, channelId := setupOpenChannel(t)

	got := QueryChannel(channelId)
	uassert.NotEqual(t, "", got)

	ch, ok := store.GetChannel(channelId)
	if !ok {
		t.Fatal("channel not found in store")
	}
	want := hexString(mustEncodeABI(ch.EncodeABI()))
	uassert.Equal(t, want, got)
}

func TestQueryChannelMissingReturnsEmpty(cur realm, t *testing.T) {
	resetStore(cur)
	uassert.Equal(t, "", QueryChannel(types.ChannelId(999)))
}

// --- GetClientStatus ---

func TestGetClientStatusActive(cur realm, t *testing.T) {
	resetStore(cur)
	clientId := registerMockClient(&mockClient{status: types.StatusActive})
	uassert.Equal(t, strconv.FormatUint(uint64(types.StatusActive), 10), GetClientStatus(clientId))
}

func TestGetClientStatusExpired(cur realm, t *testing.T) {
	resetStore(cur)
	clientId := registerMockClient(&mockClient{status: types.StatusExpired})
	uassert.Equal(t, strconv.FormatUint(uint64(types.StatusExpired), 10), GetClientStatus(clientId))
}

func TestGetClientStatusFrozen(cur realm, t *testing.T) {
	resetStore(cur)
	clientId := registerMockClient(&mockClient{status: types.StatusFrozen})
	uassert.Equal(t, strconv.FormatUint(uint64(types.StatusFrozen), 10), GetClientStatus(clientId))
}

func TestGetClientStatusMissingReturnsUnknown(cur realm, t *testing.T) {
	resetStore(cur)
	uassert.Equal(t, strconv.FormatUint(uint64(types.StatusUnknown), 10), GetClientStatus(types.ClientId(999)))
}
