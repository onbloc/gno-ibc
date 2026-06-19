package core

import (
	"testing"

	"gno.land/p/onbloc/ibc/union/types"
)

func TestForceChannelOpenTrySkipsProofVerification(cur realm, t *testing.T) {
	resetStore(cur)
	portId, connectionId, client, app := setupChannelOpenUnionTest()
	client.status = types.StatusExpired
	msgChannel := types.Channel{
		State:                 types.ChannelStateTryOpen,
		ConnectionId:          connectionId,
		CounterpartyChannelId: types.ChannelId(123),
		CounterpartyPortId:    types.Bytes("counterparty"),
		Version:               "ics20-1",
	}

	channelId := ForceChannelOpenTry(cross(cur), types.NewMsgChannelOpenTry(portId, msgChannel, "ics20-1", types.Bytes("proof-init"), 44, "g1msgrelayer"))

	if channelId != types.ChannelId(1) {
		t.Fatalf("channel id: got %d want 1", channelId)
	}
	if len(client.membershipKeys) != 0 {
		t.Fatalf("membership calls: got %d want 0", len(client.membershipKeys))
	}
	if len(app.openTryStates) != 1 || app.openTryStates[0] != types.ChannelStateTryOpen {
		t.Fatalf("open try callback state: got %v want [%d]", app.openTryStates, types.ChannelStateTryOpen)
	}
}

func TestForceChannelOpenAckSkipsProofVerification(cur realm, t *testing.T) {
	resetStore(cur)
	portId, connectionId, client, app := setupChannelOpenUnionTest()
	client.status = types.StatusExpired
	channelId := store.nextChannelId()
	store.createChannel(channelId, types.Channel{
		State:              types.ChannelStateInit,
		ConnectionId:       connectionId,
		CounterpartyPortId: types.Bytes("counterparty"),
		Version:            "ics20-1",
	}, portId)

	ForceChannelOpenAck(cross(cur), types.NewMsgChannelOpenAck(channelId, "counterparty-v1", types.ChannelId(123), types.Bytes("proof-try"), 44, "g1msgrelayer"))

	channel := store.getChannel(channelId)
	if channel.State != types.ChannelStateOpen || channel.Version != "counterparty-v1" || channel.CounterpartyChannelId != types.ChannelId(123) {
		t.Fatalf("channel: got %+v", channel)
	}
	if len(client.membershipKeys) != 0 {
		t.Fatalf("membership calls: got %d want 0", len(client.membershipKeys))
	}
	if len(app.openAckStates) != 1 || app.openAckStates[0] != types.ChannelStateOpen {
		t.Fatalf("open ack callback state: got %v want [%d]", app.openAckStates, types.ChannelStateOpen)
	}
}

func TestForceChannelOpenConfirmSkipsProofVerification(cur realm, t *testing.T) {
	resetStore(cur)
	portId, connectionId, client, app := setupChannelOpenUnionTest()
	client.status = types.StatusExpired
	channelId := store.nextChannelId()
	store.createChannel(channelId, types.Channel{
		State:                 types.ChannelStateTryOpen,
		ConnectionId:          connectionId,
		CounterpartyChannelId: types.ChannelId(123),
		CounterpartyPortId:    types.Bytes("counterparty"),
		Version:               "ics20-1",
	}, portId)

	ForceChannelOpenConfirm(cross(cur), types.NewMsgChannelOpenConfirm(channelId, types.Bytes("proof-ack"), 44, "g1msgrelayer"))

	channel := store.getChannel(channelId)
	if channel.State != types.ChannelStateOpen {
		t.Fatalf("channel state: got %d want %d", channel.State, types.ChannelStateOpen)
	}
	if len(client.membershipKeys) != 0 {
		t.Fatalf("membership calls: got %d want 0", len(client.membershipKeys))
	}
	if len(app.openConfirmStates) != 1 || app.openConfirmStates[0] != types.ChannelStateOpen {
		t.Fatalf("open confirm callback state: got %v want [%d]", app.openConfirmStates, types.ChannelStateOpen)
	}
}
