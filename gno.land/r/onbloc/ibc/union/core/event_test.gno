package core

import (
	"strconv"
	"testing"

	"gno.land/p/onbloc/ibc/union/types"
)

var testConnection = types.Connection{
	ClientId:                 types.ClientId(10),
	CounterpartyClientId:     types.ClientId(20),
	CounterpartyConnectionId: types.ConnectionId(30),
}

const fixedEventAttrHalfColumn = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef" +
	"0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef" +
	"0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef" +
	"0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef" +
	"0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef" +
	"0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef" +
	"0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef" +
	"0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"

const fixedEventAttrColumn = fixedEventAttrHalfColumn + fixedEventAttrHalfColumn

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
		"counterparty_port_id", "0x636f756e7465727061727479",
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
		"counterparty_port_id", "0x636f756e7465727061727479",
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
		"counterparty_port_id", "0x636f756e7465727061727479",
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
		"counterparty_port_id", "0x636f756e7465727061727479",
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

func TestPacketEventBaseAttrsSplitPacketData(cur realm, t *testing.T) {
	testCases := []struct {
		name     string
		data     []byte
		wantLens []int
	}{
		{
			name:     "single packet data column",
			data:     []byte("fixed-small-packet"),
			wantLens: []int{38},
		},
		{
			name:     "split packet data columns",
			data:     []byte(fixedEventAttrHalfColumn),
			wantLens: []int{maxEventAttrValueLen, 2},
		},
	}

	for _, tc := range testCases {
		t.Run(tc.name, func(t *testing.T) {
			packet := types.Packet{
				SourceChannelId:      types.ChannelId(1),
				DestinationChannelId: types.ChannelId(2),
				Data:                 tc.data,
				TimeoutTimestamp:     types.Timestamp(3),
			}

			attrs := packetEventBaseAttrs(packet)

			if attrs[0] != "packet_hash" {
				t.Fatalf("first attr key: got %q want packet_hash", attrs[0])
			}
			if attrs[2] != "packet_data_size" {
				t.Fatalf("packet data size attr key: got %q want packet_data_size", attrs[2])
			}
			if attrs[3] != strconv.Itoa(len(hexAttr(tc.data))) {
				t.Fatalf("packet data size attr value: got %q want %d", attrs[3], len(hexAttr(tc.data)))
			}
			assertAttrMissing(t, attrs, "packet_data")
			assertEventAttrColumnLens(t, attrs[4:], "packet_data", hexAttr(tc.data), tc.wantLens)
		})
	}
}

func TestEventAttrColumnsBoundary(cur realm, t *testing.T) {
	testCases := []struct {
		name     string
		value    string
		wantLens []int
	}{
		{
			name:     "empty value",
			value:    "",
			wantLens: []int{0},
		},
		{
			name:     "one column",
			value:    fixedEventAttrColumn,
			wantLens: []int{maxEventAttrValueLen},
		},
		{
			name:     "two columns",
			value:    fixedEventAttrColumn + "2",
			wantLens: []int{maxEventAttrValueLen, 1},
		},
		{
			name:     "three columns",
			value:    fixedEventAttrColumn + fixedEventAttrColumn + "3",
			wantLens: []int{maxEventAttrValueLen, maxEventAttrValueLen, 1},
		},
		{
			name:     "four columns",
			value:    fixedEventAttrColumn + fixedEventAttrColumn + fixedEventAttrColumn + "4",
			wantLens: []int{maxEventAttrValueLen, maxEventAttrValueLen, maxEventAttrValueLen, 1},
		},
	}

	for _, tc := range testCases {
		t.Run(tc.name, func(t *testing.T) {
			attrs := eventAttrColumns("packet_data", tc.value)
			assertEventAttrColumnLens(t, attrs, "packet_data", tc.value, tc.wantLens)
		})
	}
}

func assertEventAttrColumnLens(t *testing.T, attrs []string, key string, value string, wantLens []int) {
	if len(attrs) != len(wantLens)*2 {
		t.Fatalf("attr len: got %d want %d attrs=%v", len(attrs), len(wantLens)*2, attrs)
	}

	rejoined := ""
	for i, wantLen := range wantLens {
		keyIndex := i * 2
		valueIndex := keyIndex + 1
		wantKey := key + "[" + strconv.Itoa(i) + "]"
		if attrs[keyIndex] != wantKey {
			t.Fatalf("attr key[%d]: got %q want %q", i, attrs[keyIndex], wantKey)
		}
		if len(attrs[valueIndex]) != wantLen {
			t.Fatalf("attr value[%d] len: got %d want %d", i, len(attrs[valueIndex]), wantLen)
		}
		if len(attrs[valueIndex]) > maxEventAttrValueLen {
			t.Fatalf("attr value[%d] len exceeds max: got %d want <= %d", i, len(attrs[valueIndex]), maxEventAttrValueLen)
		}
		rejoined += attrs[valueIndex]
	}
	if rejoined != value {
		t.Fatalf("rejoined attr value: got %q want %q", rejoined, value)
	}
}
