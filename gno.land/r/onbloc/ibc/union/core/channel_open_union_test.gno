package core

import (
	"bytes"
	"testing"

	"gno.land/p/nt/uassert/v0"
	"gno.land/p/onbloc/ibc/union/types"
)

func setupChannelOpenUnionTest() (types.Bytes, types.ConnectionId, *mockClient, *mockApp) {
	client := &mockClient{chainId: "union-1", height: types.NewHeight(100), status: types.StatusActive}
	clientId := addMockClient(client).id
	connectionId := store.nextConnectionId()
	store.saveConnection(connectionId, types.Connection{
		State:                    types.ConnectionStateOpen,
		ClientId:                 clientId,
		CounterpartyClientId:     types.ClientId(99),
		CounterpartyConnectionId: types.ConnectionId(99),
	})

	portId := types.Bytes(testCorePkgPath)
	app := &mockApp{}
	store.ports[portKey(portId)] = app
	return portId, connectionId, client, app
}

// Converted from Union channel_open_init_ok.
// Union reference:
// https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/core/src/tests/channel/ibc_channel.rs#L23-L78
func TestChannelOpenInitOK(cur realm, t *testing.T) {
	resetStore()
	portId, connectionId, _, _ := setupChannelOpenUnionTest()

	channelId := ChannelOpenInit(cur, types.NewMsgChannelOpenInit(portId, types.Bytes("counterparty"), connectionId, "ics20-1", "g1msgrelayer"))

	if channelId != types.ChannelId(1) {
		t.Fatalf("channel id: got %d want 1", channelId)
	}
}

// Converted from Union channel_open_init_channel_claimed.
// Union reference:
// https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/core/src/tests/channel/ibc_channel.rs#L80-L124
func TestChannelOpenInitChannelClaimed(cur realm, t *testing.T) {
	resetStore()
	portId, connectionId, _, _ := setupChannelOpenUnionTest()

	channelId := ChannelOpenInit(cur, types.NewMsgChannelOpenInit(portId, types.Bytes("counterparty"), connectionId, "ics20-1", "g1msgrelayer"))

	if got := store.getChannelOwner(channelId); !bytes.Equal(got, portId) {
		t.Fatalf("channel owner: got %q want %q", string(got), string(portId))
	}
}

// Converted from Union channel_open_init_commitment_saved.
// Union reference:
// https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/core/src/tests/channel/ibc_channel.rs#L126-L176
func TestChannelOpenInitCommitmentSaved(cur realm, t *testing.T) {
	resetStore()
	portId, connectionId, _, _ := setupChannelOpenUnionTest()

	channelId := ChannelOpenInit(cur, types.NewMsgChannelOpenInit(portId, types.Bytes("counterparty"), connectionId, "ics20-1", "g1msgrelayer"))

	channel := store.getChannel(channelId)
	if channel.State != types.ChannelStateInit || channel.ConnectionId != connectionId || channel.CounterpartyChannelId != 0 || channel.Version != "ics20-1" {
		t.Fatalf("channel: got %+v", channel)
	}
	if !bytes.Equal(channel.CounterpartyPortId, []byte("counterparty")) {
		t.Fatalf("counterparty port: got %q", string(channel.CounterpartyPortId))
	}
}

// Converted from Union channel_open_try_ok.
// Union reference:
// https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/core/src/tests/channel/ibc_channel.rs#L178-L273
func TestChannelOpenTryOK(cur realm, t *testing.T) {
	resetStore()
	portId, connectionId, client, app := setupChannelOpenUnionTest()
	msgChannel := types.Channel{
		State:                 types.ChannelStateTryOpen,
		ConnectionId:          connectionId,
		CounterpartyChannelId: types.ChannelId(123),
		CounterpartyPortId:    types.Bytes("counterparty"),
		Version:               "ics20-1",
	}

	channelId := ChannelOpenTry(cur, types.NewMsgChannelOpenTry(portId, msgChannel, "ics20-1", types.Bytes("proof-init"), 44, "g1msgrelayer"))

	if channelId != types.ChannelId(1) {
		t.Fatalf("channel id: got %d want 1", channelId)
	}
	if len(client.membershipKeys) != 1 {
		t.Fatalf("membership calls: got %d want 1", len(client.membershipKeys))
	}
	if len(app.openTryStates) != 1 || app.openTryStates[0] != types.ChannelStateTryOpen {
		t.Fatalf("open try callback state: got %v want [%d]", app.openTryStates, types.ChannelStateTryOpen)
	}
}

// Converted from Union channel_open_try_invalid_state.
// Union reference:
// https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/core/src/tests/channel/ibc_channel.rs#L275-L346
func TestChannelOpenTryInvalidState(cur realm, t *testing.T) {
	resetStore()
	portId, connectionId, _, _ := setupChannelOpenUnionTest()
	msgChannel := types.Channel{
		State:                 types.ChannelStateOpen,
		ConnectionId:          connectionId,
		CounterpartyChannelId: types.ChannelId(123),
		CounterpartyPortId:    types.Bytes("counterparty"),
		Version:               "ics20-1",
	}

	uassert.AbortsContains(t, cur, "invalid channel state", func(cur realm) {
		channelOpenTry(cur, types.NewMsgChannelOpenTry(portId, msgChannel, "ics20-1", types.Bytes("proof-init"), 44, "g1msgrelayer"), true)
	})
}

// Converted from Union channel_open_try_channel_claimed.
// Union reference:
// https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/core/src/tests/channel/ibc_channel.rs#L348-L413
func TestChannelOpenTryChannelClaimed(cur realm, t *testing.T) {
	resetStore()
	portId, connectionId, _, _ := setupChannelOpenUnionTest()
	msgChannel := types.Channel{
		State:                 types.ChannelStateTryOpen,
		ConnectionId:          connectionId,
		CounterpartyChannelId: types.ChannelId(123),
		CounterpartyPortId:    types.Bytes("counterparty"),
		Version:               "ics20-1",
	}

	channelId := ChannelOpenTry(cur, types.NewMsgChannelOpenTry(portId, msgChannel, "ics20-1", types.Bytes("proof-init"), 44, "g1msgrelayer"))

	if got := store.getChannelOwner(channelId); !bytes.Equal(got, portId) {
		t.Fatalf("channel owner: got %q want %q", string(got), string(portId))
	}
}

// Converted from Union channel_open_try_commitment_saved.
// Union reference:
// https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/core/src/tests/channel/ibc_channel.rs#L415-L486
func TestChannelOpenTryCommitmentSaved(cur realm, t *testing.T) {
	resetStore()
	portId, connectionId, _, _ := setupChannelOpenUnionTest()
	msgChannel := types.Channel{
		State:                 types.ChannelStateTryOpen,
		ConnectionId:          connectionId,
		CounterpartyChannelId: types.ChannelId(123),
		CounterpartyPortId:    types.Bytes("counterparty"),
		Version:               "ics20-1",
	}

	channelId := ChannelOpenTry(cur, types.NewMsgChannelOpenTry(portId, msgChannel, "ics20-1", types.Bytes("proof-init"), 44, "g1msgrelayer"))

	channel := store.getChannel(channelId)
	if channel.State != types.ChannelStateTryOpen || channel.ConnectionId != connectionId || channel.CounterpartyChannelId != types.ChannelId(123) || channel.Version != "ics20-1" {
		t.Fatalf("channel: got %+v", channel)
	}
}

// Converted from Union channel_open_ack_ok.
// Union reference:
// https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/core/src/tests/channel/ibc_channel.rs#L488-L589
func TestChannelOpenAckOK(cur realm, t *testing.T) {
	resetStore()
	portId, connectionId, client, app := setupChannelOpenUnionTest()
	channelId := store.nextChannelId()
	store.createChannel(channelId, types.Channel{State: types.ChannelStateInit, ConnectionId: connectionId, CounterpartyPortId: types.Bytes("counterparty"), Version: "ics20-1"}, portId)

	ChannelOpenAck(cur, types.NewMsgChannelOpenAck(channelId, "ics20-1", types.ChannelId(123), types.Bytes("proof-try"), 44, "g1msgrelayer"))

	channel := store.getChannel(channelId)
	if channel.State != types.ChannelStateOpen || channel.CounterpartyChannelId != types.ChannelId(123) {
		t.Fatalf("channel: got %+v", channel)
	}
	if len(client.membershipKeys) != 1 {
		t.Fatalf("membership calls: got %d want 1", len(client.membershipKeys))
	}
	if len(app.openAckStates) != 1 || app.openAckStates[0] != types.ChannelStateOpen {
		t.Fatalf("open ack callback state: got %v want [%d]", app.openAckStates, types.ChannelStateOpen)
	}
}

// Converted from Union channel_open_ack_not_found.
// Union reference:
// https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/core/src/tests/channel/ibc_channel.rs#L591-L650
func TestChannelOpenAckNotFound(cur realm, t *testing.T) {
	resetStore()

	uassert.AbortsContains(t, cur, "channel 1 not found", func(cur realm) {
		channelOpenAck(cur, types.NewMsgChannelOpenAck(types.ChannelId(1), "ics20-1", types.ChannelId(123), types.Bytes("proof-try"), 44, "g1msgrelayer"), true)
	})
}

// Local regression: Union MsgChannelOpenAck carries a concrete ChannelId, not
// an Option, so core must not reject zero before proof verification.
func TestChannelOpenAckAllowsZeroCounterpartyChannelId(cur realm, t *testing.T) {
	resetStore()
	portId, connectionId, _, _ := setupChannelOpenUnionTest()
	channelId := store.nextChannelId()
	store.createChannel(channelId, types.Channel{State: types.ChannelStateInit, ConnectionId: connectionId, CounterpartyPortId: types.Bytes("counterparty"), Version: "ics20-1"}, portId)

	channelOpenAck(cur, types.NewMsgChannelOpenAck(channelId, "ics20-1", 0, types.Bytes("proof-try"), 44, "g1msgrelayer"), false)

	channel := store.getChannel(channelId)
	if channel.State != types.ChannelStateOpen || channel.CounterpartyChannelId != 0 {
		t.Fatalf("channel: got %+v", channel)
	}
}

// Converted from Union channel_open_ack_commitment_saved.
// Union reference:
// https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/core/src/tests/channel/ibc_channel.rs#L652-L733
func TestChannelOpenAckCommitmentSaved(cur realm, t *testing.T) {
	resetStore()
	portId, connectionId, _, _ := setupChannelOpenUnionTest()
	channelId := store.nextChannelId()
	store.createChannel(channelId, types.Channel{State: types.ChannelStateInit, ConnectionId: connectionId, CounterpartyPortId: types.Bytes("counterparty"), Version: "ics20-1"}, portId)

	ChannelOpenAck(cur, types.NewMsgChannelOpenAck(channelId, "counterparty-v1", types.ChannelId(123), types.Bytes("proof-try"), 44, "g1msgrelayer"))

	channel := store.getChannel(channelId)
	if channel.State != types.ChannelStateOpen || channel.Version != "counterparty-v1" || channel.CounterpartyChannelId != types.ChannelId(123) {
		t.Fatalf("channel: got %+v", channel)
	}
}

// Converted from Union channel_open_confirm_ok.
// Union reference:
// https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/core/src/tests/channel/ibc_channel.rs#L735-L813
func TestChannelOpenConfirmOK(cur realm, t *testing.T) {
	resetStore()
	portId, connectionId, client, app := setupChannelOpenUnionTest()
	channelId := store.nextChannelId()
	store.createChannel(channelId, types.Channel{State: types.ChannelStateTryOpen, ConnectionId: connectionId, CounterpartyChannelId: types.ChannelId(123), CounterpartyPortId: types.Bytes("counterparty"), Version: "ics20-1"}, portId)

	ChannelOpenConfirm(cur, types.NewMsgChannelOpenConfirm(channelId, types.Bytes("proof-ack"), 44, "g1msgrelayer"))

	channel := store.getChannel(channelId)
	if channel.State != types.ChannelStateOpen {
		t.Fatalf("channel state: got %d want %d", channel.State, types.ChannelStateOpen)
	}
	if len(client.membershipKeys) != 1 {
		t.Fatalf("membership calls: got %d want 1", len(client.membershipKeys))
	}
	if len(app.openConfirmStates) != 1 || app.openConfirmStates[0] != types.ChannelStateOpen {
		t.Fatalf("open confirm callback state: got %v want [%d]", app.openConfirmStates, types.ChannelStateOpen)
	}
}

// Converted from Union channel_open_try_invalid_counterparty.
// Union reference:
// https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/core/src/tests/channel/ibc_channel.rs#L815-L878
func TestChannelOpenTryInvalidCounterparty(cur realm, t *testing.T) {
	resetStore()
	portId, connectionId, _, _ := setupChannelOpenUnionTest()
	msgChannel := types.Channel{
		State:              types.ChannelStateTryOpen,
		ConnectionId:       connectionId,
		CounterpartyPortId: types.Bytes("counterparty"),
		Version:            "ics20-1",
	}

	uassert.AbortsContains(t, cur, "invalid counterparty channel id", func(cur realm) {
		channelOpenTry(cur, types.NewMsgChannelOpenTry(portId, msgChannel, "ics20-1", types.Bytes("proof-init"), 44, "g1msgrelayer"), true)
	})
}

// Converted from Union channel_open_confirm_not_found.
// Union reference:
// https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/core/src/tests/channel/ibc_channel.rs#L879-L938
func TestChannelOpenConfirmNotFound(cur realm, t *testing.T) {
	resetStore()

	uassert.AbortsContains(t, cur, "channel 1 not found", func(cur realm) {
		channelOpenConfirm(cur, types.NewMsgChannelOpenConfirm(types.ChannelId(1), types.Bytes("proof-ack"), 44, "g1msgrelayer"), true)
	})
}

// Local regression for Gno's zero-as-None representation of Union counterparty_channel_id.
func TestChannelOpenConfirmRejectsInvalidCounterpartyChannelId(cur realm, t *testing.T) {
	resetStore()
	portId, connectionId, client, _ := setupChannelOpenUnionTest()
	channelId := store.nextChannelId()
	store.createChannel(channelId, types.Channel{State: types.ChannelStateTryOpen, ConnectionId: connectionId, CounterpartyChannelId: 0, CounterpartyPortId: types.Bytes("counterparty"), Version: "ics20-1"}, portId)

	uassert.AbortsContains(t, cur, "invalid counterparty channel id", func(cur realm) {
		channelOpenConfirm(cur, types.NewMsgChannelOpenConfirm(channelId, types.Bytes("proof-ack"), 44, "g1msgrelayer"), true)
	})
	if len(client.membershipKeys) != 0 {
		t.Fatalf("membership calls: got %d want 0", len(client.membershipKeys))
	}
}

// Converted from Union channel_open_confirm_commitment_saved.
// Union reference:
// https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/core/src/tests/channel/ibc_channel.rs#L940-L1013
func TestChannelOpenConfirmCommitmentSaved(cur realm, t *testing.T) {
	resetStore()
	portId, connectionId, _, _ := setupChannelOpenUnionTest()
	channelId := store.nextChannelId()
	store.createChannel(channelId, types.Channel{State: types.ChannelStateTryOpen, ConnectionId: connectionId, CounterpartyChannelId: types.ChannelId(123), CounterpartyPortId: types.Bytes("counterparty"), Version: "ics20-1"}, portId)

	ChannelOpenConfirm(cur, types.NewMsgChannelOpenConfirm(channelId, types.Bytes("proof-ack"), 44, "g1msgrelayer"))

	channel := store.getChannel(channelId)
	if channel.State != types.ChannelStateOpen {
		t.Fatalf("channel state: got %d want %d", channel.State, types.ChannelStateOpen)
	}
}
