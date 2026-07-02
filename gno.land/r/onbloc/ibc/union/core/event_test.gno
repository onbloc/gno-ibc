package core

import (
	"testing"

	"gno.land/p/onbloc/ibc/union/types"
)

var testConnection = types.Connection{
	ClientId:                 types.ClientId(10),
	CounterpartyClientId:     types.ClientId(20),
	CounterpartyConnectionId: types.ConnectionId(30),
}

func TestChannelOpenInitEventAttrs(cur realm, t *testing.T) {
	attrs := channelOpenInitEventAttrs(
		types.Bytes("gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm"),
		types.ChannelId(1),
		types.Channel{
			State:                 types.ChannelStateInit,
			ConnectionId:          types.ConnectionId(2),
			CounterpartyChannelId: types.ChannelId(0),
			CounterpartyPortId:    types.Bytes("counterparty"),
			Version:               "ucs03-zkgm-0",
		},
		testConnection,
	)

	assertStringSliceEqual(t, attrs, []string{
		"port_id", "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm",
		"channel_id", "1",
		"counterparty_port_id", "Y291bnRlcnBhcnR5",
		"connection_id", "2",
		"connection_client_id", "10",
		"connection_counterparty_client_id", "20",
		"connection_counterparty_connection_id", "30",
		"version", "ucs03-zkgm-0",
	})
	assertAttrMissing(t, attrs, "counterparty_channel_id")
}

func TestChannelOpenTryEventAttrs(cur realm, t *testing.T) {
	attrs := channelOpenTryEventAttrs(
		types.Bytes("gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm"),
		types.ChannelId(1),
		types.Channel{
			State:                 types.ChannelStateOpen,
			ConnectionId:          types.ConnectionId(2),
			CounterpartyChannelId: types.ChannelId(7),
			CounterpartyPortId:    types.Bytes("counterparty"),
			Version:               "ucs03-zkgm-0",
		},
		"counterparty-v1",
		testConnection,
	)

	assertStringSliceEqual(t, attrs, []string{
		"port_id", "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm",
		"channel_id", "1",
		"counterparty_port_id", "Y291bnRlcnBhcnR5",
		"counterparty_channel_id", "7",
		"connection_id", "2",
		"connection_client_id", "10",
		"connection_counterparty_client_id", "20",
		"connection_counterparty_connection_id", "30",
		"version", "ucs03-zkgm-0",
		"counterparty_version", "counterparty-v1",
	})
}

func TestChannelOpenAckConfirmEventAttrs(cur realm, t *testing.T) {
	attrs := channelOpenAckConfirmEventAttrs(
		types.Bytes("gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm"),
		types.ChannelId(1),
		types.Channel{
			State:                 types.ChannelStateOpen,
			ConnectionId:          types.ConnectionId(2),
			CounterpartyChannelId: types.ChannelId(7),
			CounterpartyPortId:    types.Bytes("counterparty"),
			Version:               "ucs03-zkgm-0",
		},
		testConnection,
	)

	assertStringSliceEqual(t, attrs, []string{
		"port_id", "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm",
		"channel_id", "1",
		"counterparty_port_id", "Y291bnRlcnBhcnR5",
		"counterparty_channel_id", "7",
		"connection_id", "2",
		"connection_client_id", "10",
		"connection_counterparty_client_id", "20",
		"connection_counterparty_connection_id", "30",
		"version", "ucs03-zkgm-0",
	})
}

func TestChannelCloseEventAttrs(cur realm, t *testing.T) {
	attrs := channelCloseEventAttrs(
		types.Bytes("gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm"),
		types.ChannelId(1),
		types.Channel{
			State:                 types.ChannelStateClosed,
			ConnectionId:          types.ConnectionId(2),
			CounterpartyChannelId: types.ChannelId(7),
			CounterpartyPortId:    types.Bytes("counterparty"),
			Version:               "ucs03-zkgm-0",
		},
		testConnection,
	)

	assertStringSliceEqual(t, attrs, []string{
		"port_id", "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm",
		"channel_id", "1",
		"counterparty_port_id", "Y291bnRlcnBhcnR5",
		"counterparty_channel_id", "7",
		"connection_id", "2",
		"connection_client_id", "10",
		"connection_counterparty_client_id", "20",
		"connection_counterparty_connection_id", "30",
		"version", "ucs03-zkgm-0",
	})
}

func TestConnectionOpenEventAttrs(cur realm, t *testing.T) {
	attrs := connectionOpenEventAttrs(
		types.ConnectionId(1),
		types.ClientId(2),
		types.ClientId(3),
		types.ConnectionId(4),
	)

	assertStringSliceEqual(t, attrs, []string{
		"connection_id", "1",
		"client_id", "2",
		"counterparty_client_id", "3",
		"counterparty_connection_id", "4",
	})
}
