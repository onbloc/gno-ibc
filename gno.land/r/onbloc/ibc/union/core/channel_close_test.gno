package core

import (
	"bytes"
	"testing"

	"gno.land/p/nt/uassert/v0"
	"gno.land/p/onbloc/ibc/union/types"
)

func setupCloseChannelWithConnectionState(t *testing.T, state types.ConnectionState) (types.ChannelId, *mockClient) {
	t.Helper()

	client := &mockClient{chainId: "union-1", height: types.NewHeight(100), status: types.StatusActive}
	clientId := addMockClient(client).id
	connId := store.nextConnectionId()
	store.saveConnection(connId, types.Connection{
		State:                    state,
		ClientId:                 clientId,
		CounterpartyClientId:     types.ClientId(99),
		CounterpartyConnectionId: types.ConnectionId(99),
	})

	portId := types.Bytes(testCorePkgPath)
	store.ports[portKey(portId)] = &mockApp{}

	channelId := store.nextChannelId()
	store.createChannel(channelId, types.Channel{
		State:                 types.ChannelStateOpen,
		ConnectionId:          connId,
		CounterpartyChannelId: types.ChannelId(99),
		CounterpartyPortId:    types.Bytes("counterparty"),
		Version:               "ics20-1",
	}, portId)
	return channelId, client
}

// Local regression for ChannelCloseInit success and callback attribution.
func TestChannelCloseInitClosesOpenChannel(cur realm, t *testing.T) {
	resetStore(cur)
	portId, _, channelId := setupOpenChannel(t)
	app := store.ports[portKey(portId)].(*mockApp)
	wantRelayer := cur.Address()

	ChannelCloseInit(cross(cur), types.NewMsgChannelCloseInit(channelId, "g1msgrelayer"))

	channel := store.getChannel(channelId)
	if channel.State != types.ChannelStateClosed {
		t.Fatalf("ChannelCloseInit state: got %d want %d", channel.State, types.ChannelStateClosed)
	}
	if len(app.closedChannels) != 1 || app.closedChannels[0] != channelId {
		t.Fatalf("OnChannelCloseInit calls: got %v want [%d]", app.closedChannels, channelId)
	}
	if len(app.closeInitStates) != 1 || app.closeInitStates[0] != types.ChannelStateClosed {
		t.Fatalf("OnChannelCloseInit state: got %v want [%d]", app.closeInitStates, types.ChannelStateClosed)
	}
	if len(app.closeInitRelayers) != 1 || app.closeInitRelayers[0] != wantRelayer {
		t.Fatalf("OnChannelCloseInit relayer: got %v want [%s]", app.closeInitRelayers, wantRelayer)
	}
}

// Local regression for ChannelCloseInit connection preconditions.
func TestChannelCloseInitRejectsNonOpenConnection(cur realm, t *testing.T) {
	resetStore(cur)
	channelId, _ := setupCloseChannelWithConnectionState(t, types.ConnectionStateInit)

	uassert.AbortsContains(t, cur, "invalid connection state", func(cur realm) {
		channelCloseInit(cur, types.NewMsgChannelCloseInit(channelId, "g1msgrelayer"))
	})

	if store.getChannel(channelId).State != types.ChannelStateOpen {
		t.Fatal("non-open connection must not close the channel")
	}
}

// Local regression for Gno's zero-as-None representation of Union counterparty_channel_id.
func TestChannelCloseInitRejectsInvalidCounterpartyChannelId(cur realm, t *testing.T) {
	resetStore(cur)
	_, _, channelId := setupOpenChannel(t)
	channel := store.getChannel(channelId)
	channel.CounterpartyChannelId = 0
	store.saveChannel(channelId, channel)

	uassert.AbortsContains(t, cur, "invalid counterparty channel id", func(cur realm) {
		channelCloseInit(cur, types.NewMsgChannelCloseInit(channelId, "g1msgrelayer"))
	})

	if store.getChannel(channelId).State != types.ChannelStateOpen {
		t.Fatal("invalid counterparty channel id must not close the channel")
	}
}

// Local regression for ChannelCloseConfirm proof verification and close effects.
func TestChannelCloseConfirmVerifiesCounterpartyCloseAndClosesChannel(cur realm, t *testing.T) {
	resetStore(cur)
	portId, _, channelId := setupOpenChannel(t)
	client := mockClientFor(channelId)
	app := store.ports[portKey(portId)].(*mockApp)
	wantRelayer := cur.Address()

	ChannelCloseConfirm(cross(cur), types.NewMsgChannelCloseConfirm(channelId, types.Bytes("close-proof"), 44, "g1msgrelayer"))

	channel := store.getChannel(channelId)
	if channel.State != types.ChannelStateClosed {
		t.Fatalf("ChannelCloseConfirm state: got %d want %d", channel.State, types.ChannelStateClosed)
	}
	if len(app.closedChannels) != 1 || app.closedChannels[0] != channelId {
		t.Fatalf("OnChannelCloseConfirm calls: got %v want [%d]", app.closedChannels, channelId)
	}
	if len(app.closeConfirmStates) != 1 || app.closeConfirmStates[0] != types.ChannelStateClosed {
		t.Fatalf("OnChannelCloseConfirm state: got %v want [%d]", app.closeConfirmStates, types.ChannelStateClosed)
	}
	if len(app.closeConfirmRelayers) != 1 || app.closeConfirmRelayers[0] != wantRelayer {
		t.Fatalf("OnChannelCloseConfirm relayer: got %v want [%s]", app.closeConfirmRelayers, wantRelayer)
	}
	if len(client.membershipKeys) != 1 {
		t.Fatalf("membership calls: got %d want 1", len(client.membershipKeys))
	}
	if client.membershipHeights[0] != types.NewHeight(44) {
		t.Fatalf("membership height: got %v want 44", client.membershipHeights[0])
	}
	if !bytes.Equal(client.membershipProofs[0], []byte("close-proof")) {
		t.Fatalf("membership proof: got %x want %x", client.membershipProofs[0], []byte("close-proof"))
	}
	counterpartyKey := types.ChannelPath(types.ChannelId(99))
	if !bytes.Equal(client.membershipKeys[0], counterpartyKey[:]) {
		t.Fatalf("membership key: got %x want %x", client.membershipKeys[0], counterpartyKey[:])
	}
	expectedChannel := types.Channel{
		State:                 types.ChannelStateClosed,
		ConnectionId:          types.ConnectionId(99),
		CounterpartyChannelId: channelId,
		CounterpartyPortId:    portId,
		Version:               "ics20-1",
	}
	expectedValue := channelValue(expectedChannel)
	if !bytes.Equal(client.membershipValues[0], expectedValue[:]) {
		t.Fatalf("membership value: got %x want %x", client.membershipValues[0], expectedValue[:])
	}
}

// Local regression for Gno's zero-as-None representation of Union counterparty_channel_id.
func TestChannelCloseConfirmRejectsInvalidCounterpartyChannelIdBeforeProof(cur realm, t *testing.T) {
	resetStore(cur)
	_, _, channelId := setupOpenChannel(t)
	client := mockClientFor(channelId)
	channel := store.getChannel(channelId)
	channel.CounterpartyChannelId = 0
	store.saveChannel(channelId, channel)

	uassert.AbortsContains(t, cur, "invalid counterparty channel id", func(cur realm) {
		channelCloseConfirm(cur, types.NewMsgChannelCloseConfirm(channelId, types.Bytes("close-proof"), 44, "g1msgrelayer"))
	})

	if len(client.membershipKeys) != 0 {
		t.Fatalf("membership calls: got %d want 0", len(client.membershipKeys))
	}
	if store.getChannel(channelId).State != types.ChannelStateOpen {
		t.Fatal("invalid counterparty channel id must not close the channel")
	}
}

// Local regression for ChannelCloseConfirm state preconditions before proof verification.
func TestChannelCloseConfirmRejectsWrongStateBeforeProof(cur realm, t *testing.T) {
	resetStore(cur)
	_, _, channelId := setupOpenChannel(t)
	client := mockClientFor(channelId)
	channel := store.getChannel(channelId)
	channel.State = types.ChannelStateClosed
	store.saveChannel(channelId, channel)

	uassert.AbortsContains(t, cur, "invalid channel state", func(cur realm) {
		channelCloseConfirm(cur, types.NewMsgChannelCloseConfirm(channelId, types.Bytes("close-proof"), 44, "g1msgrelayer"))
	})

	if len(client.membershipKeys) != 0 {
		t.Fatalf("membership calls: got %d want 0", len(client.membershipKeys))
	}
}

// Local regression for ChannelCloseConfirm connection preconditions before proof verification.
func TestChannelCloseConfirmRejectsNonOpenConnectionBeforeProof(cur realm, t *testing.T) {
	resetStore(cur)
	channelId, client := setupCloseChannelWithConnectionState(t, types.ConnectionStateInit)

	uassert.AbortsContains(t, cur, "invalid connection state", func(cur realm) {
		channelCloseConfirm(cur, types.NewMsgChannelCloseConfirm(channelId, types.Bytes("close-proof"), 44, "g1msgrelayer"))
	})

	if len(client.membershipKeys) != 0 {
		t.Fatalf("membership calls: got %d want 0", len(client.membershipKeys))
	}
	if store.getChannel(channelId).State != types.ChannelStateOpen {
		t.Fatal("non-open connection must not close the channel")
	}
}

// Local regression for inactive client short-circuit before proof verification.
func TestChannelCloseConfirmRejectsInactiveClientBeforeProof(cur realm, t *testing.T) {
	resetStore(cur)
	_, _, channelId := setupOpenChannel(t)
	client := mockClientFor(channelId)
	client.status = types.StatusExpired

	uassert.AbortsContains(t, cur, "client is not active", func(cur realm) {
		channelCloseConfirm(cur, types.NewMsgChannelCloseConfirm(channelId, types.Bytes("close-proof"), 44, "g1msgrelayer"))
	})

	if len(client.membershipKeys) != 0 {
		t.Fatalf("membership calls: got %d want 0", len(client.membershipKeys))
	}
	if store.getChannel(channelId).State != types.ChannelStateOpen {
		t.Fatal("inactive client must not close the channel")
	}
}
