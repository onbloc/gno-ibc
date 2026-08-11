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

	got, err := QueryClientState(clientId)
	uassert.NoError(t, err)
	uassert.Equal(t, hexString(raw), got)
}

func TestQueryClientStateMissingReturnsError(cur realm, t *testing.T) {
	resetStore(cur)
	got, err := QueryClientState(types.ClientId(999))
	uassert.Equal(t, "", got)
	uassert.ErrorContains(t, err, ErrClientStateNotFound)
}

// --- QueryConsensusState ---

func TestQueryConsensusStateReturnsHex(cur realm, t *testing.T) {
	resetStore(cur)
	clientId := registerMockClient(&mockClient{status: types.StatusActive})
	raw := []byte("consensus-state-bytes")
	height := uint64(42)
	store.SaveConsensusState(0, cur, clientId, types.NewHeight(height), raw)

	got, err := QueryConsensusState(clientId, height)
	uassert.NoError(t, err)
	uassert.Equal(t, hexString(raw), got)
}

func TestQueryConsensusStateMissingReturnsError(cur realm, t *testing.T) {
	resetStore(cur)
	clientId := registerMockClient(&mockClient{status: types.StatusActive})
	got, err := QueryConsensusState(clientId, 999)
	uassert.Equal(t, "", got)
	uassert.ErrorContains(t, err, ErrConsensusStateNotFound)
}

func TestQueryConsensusStateWrongHeightReturnsError(cur realm, t *testing.T) {
	resetStore(cur)
	clientId := registerMockClient(&mockClient{status: types.StatusActive})
	store.SaveConsensusState(0, cur, clientId, types.NewHeight(10), []byte("cs"))

	got, err := QueryConsensusState(clientId, 99)
	uassert.Equal(t, "", got)
	uassert.ErrorContains(t, err, ErrConsensusStateNotFound)
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

	got, err := QueryConnection(id)
	uassert.NoError(t, err)
	uassert.Equal(t, hexString(mustEncodeABI(conn.EncodeABI())), got)
}

func TestQueryConnectionMissingReturnsError(cur realm, t *testing.T) {
	resetStore(cur)
	got, err := QueryConnection(types.ConnectionId(999))
	uassert.Equal(t, "", got)
	uassert.ErrorContains(t, err, ErrConnectionNotFound)
}

// --- QueryChannel ---

func TestQueryChannelReturnsABIHex(cur realm, t *testing.T) {
	resetStore(cur)
	_, _, channelId := setupOpenChannel(t)

	got, err := QueryChannel(channelId)
	uassert.NoError(t, err)
	uassert.NotEqual(t, "", got)

	ch, ok := store.GetChannel(channelId)
	if !ok {
		t.Fatal("channel not found in store")
	}
	uassert.Equal(t, hexString(mustEncodeABI(ch.EncodeABI())), got)
}

func TestQueryChannelMissingReturnsError(cur realm, t *testing.T) {
	resetStore(cur)
	got, err := QueryChannel(types.ChannelId(999))
	uassert.Equal(t, "", got)
	uassert.ErrorContains(t, err, ErrChannelNotFound)
}

// --- GetClientStatus ---

func TestGetClientStatusActive(cur realm, t *testing.T) {
	resetStore(cur)
	clientId := registerMockClient(&mockClient{status: types.StatusActive})
	got, err := GetClientStatus(clientId)
	uassert.NoError(t, err)
	uassert.Equal(t, strconv.FormatUint(uint64(types.StatusActive), 10), got)
}

func TestGetClientStatusExpired(cur realm, t *testing.T) {
	resetStore(cur)
	clientId := registerMockClient(&mockClient{status: types.StatusExpired})
	got, err := GetClientStatus(clientId)
	uassert.NoError(t, err)
	uassert.Equal(t, strconv.FormatUint(uint64(types.StatusExpired), 10), got)
}

func TestGetClientStatusFrozen(cur realm, t *testing.T) {
	resetStore(cur)
	clientId := registerMockClient(&mockClient{status: types.StatusFrozen})
	got, err := GetClientStatus(clientId)
	uassert.NoError(t, err)
	uassert.Equal(t, strconv.FormatUint(uint64(types.StatusFrozen), 10), got)
}

func TestGetClientStatusMissingReturnsError(cur realm, t *testing.T) {
	resetStore(cur)
	got, err := GetClientStatus(types.ClientId(999))
	uassert.Equal(t, strconv.FormatUint(uint64(types.StatusUnknown), 10), got)
	uassert.ErrorContains(t, err, ErrClientNotFound)
}
