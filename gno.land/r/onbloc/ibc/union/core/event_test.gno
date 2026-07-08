package core

import (
	"strconv"
	"testing"

	"gno.land/p/nt/uassert/v0"
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

func TestPacketSendEventAttrsSplitPacketData(cur realm, t *testing.T) {
	resetEventConfigForTest()

	maxLen := int(GetEventConfig().MaxEventAttrValueLen)
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
			wantLens: []int{maxLen, 2},
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

			attrs := packetSendEventAttrs(packet, types.Channel{}, types.Connection{})

			if attrs[0] != "packet_hash" {
				t.Fatalf("first attr key: got %q want packet_hash", attrs[0])
			}

			// packet_data is always the trailing segment: "packet_data_size"
			// pair followed by len(wantLens) indexed columns.
			packetDataAttrs := attrs[len(attrs)-(2+2*len(tc.wantLens)):]
			if packetDataAttrs[0] != "packet_data_size" {
				t.Fatalf("packet data size attr key: got %q want packet_data_size", packetDataAttrs[0])
			}
			if packetDataAttrs[1] != strconv.Itoa(len(hexAttr(tc.data))) {
				t.Fatalf("packet data size attr value: got %q want %d", packetDataAttrs[1], len(hexAttr(tc.data)))
			}
			assertAttrMissing(t, attrs, "packet_data")
			assertEventAttrColumnLens(t, packetDataAttrs[2:], "packet_data", hexAttr(tc.data), tc.wantLens, maxLen)
		})
	}
}

func TestPacketSendEventAttrs(cur realm, t *testing.T) {
	resetEventConfigForTest()

	packet := types.Packet{
		SourceChannelId:      types.ChannelId(1),
		DestinationChannelId: types.ChannelId(2),
		Data:                 []byte{0, 1, 2, 3},
		TimeoutTimestamp:     types.Timestamp(4),
	}
	sourceChannel := types.Channel{
		ConnectionId: types.ConnectionId(3),
		Version:      "ucs03-zkgm-0",
	}

	attrs := packetSendEventAttrs(packet, sourceChannel, testConnection)

	assertStringSliceEqual(t, attrs, []string{
		"packet_hash", commitPacketHash(packet).String(),
		"source_channel_id", "1",
		"source_channel_version", "ucs03-zkgm-0",
		"source_connection_id", "3",
		"source_connection_client_id", "10",
		"destination_channel_id", "2",
		"destination_connection_id", "30",
		"destination_connection_client_id", "20",
		"timeout_timestamp", "4",
		"packet_data_size", strconv.Itoa(len(hexAttr(packet.Data))),
		"packet_data[0]", hexAttr(packet.Data),
	})
}

func TestPacketRecvEventAttrs(cur realm, t *testing.T) {
	resetEventConfigForTest()

	packet := types.Packet{
		SourceChannelId:      types.ChannelId(1),
		DestinationChannelId: types.ChannelId(2),
		Data:                 []byte{0, 1, 2, 3},
		TimeoutTimestamp:     types.Timestamp(4),
	}
	destinationChannel := types.Channel{
		ConnectionId: types.ConnectionId(3),
		Version:      "ucs03-zkgm-0",
	}
	makerMsg := []byte{8, 9}

	attrs := packetRecvEventAttrs(packet, destinationChannel, testConnection, makerMsg)

	assertStringSliceEqual(t, attrs, []string{
		"packet_hash", commitPacketHash(packet).String(),
		"source_channel_id", "1",
		"source_connection_id", "30",
		"source_connection_client_id", "20",
		"destination_channel_id", "2",
		"destination_channel_version", "ucs03-zkgm-0",
		"destination_connection_id", "3",
		"destination_connection_client_id", "10",
		"timeout_timestamp", "4",
		"packet_data_size", strconv.Itoa(len(hexAttr(packet.Data))),
		"packet_data[0]", hexAttr(packet.Data),
		"maker_msg_size", strconv.Itoa(len(hexAttr(makerMsg))),
		"maker_msg[0]", hexAttr(makerMsg),
	})
}

func TestWriteAckEventAttrs(cur realm, t *testing.T) {
	resetEventConfigForTest()

	packet := types.Packet{
		SourceChannelId:      types.ChannelId(1),
		DestinationChannelId: types.ChannelId(2),
		Data:                 []byte{0, 1, 2, 3},
		TimeoutTimestamp:     types.Timestamp(4),
	}
	destinationChannel := types.Channel{
		ConnectionId: types.ConnectionId(3),
		Version:      "ucs03-zkgm-0",
	}
	acknowledgement := []byte{4, 5, 6, 7}

	attrs := writeAckEventAttrs(packet, destinationChannel, testConnection, acknowledgement)

	assertStringSliceEqual(t, attrs, []string{
		"packet_hash", commitPacketHash(packet).String(),
		"source_channel_id", "1",
		"source_connection_id", "30",
		"source_connection_client_id", "20",
		"destination_channel_id", "2",
		"destination_channel_version", "ucs03-zkgm-0",
		"destination_connection_id", "3",
		"destination_connection_client_id", "10",
		"timeout_timestamp", "4",
		"packet_data_size", strconv.Itoa(len(hexAttr(packet.Data))),
		"packet_data[0]", hexAttr(packet.Data),
		"acknowledgement_size", strconv.Itoa(len(hexAttr(acknowledgement))),
		"acknowledgement[0]", hexAttr(acknowledgement),
	})
}

func TestPacketAckEventAttrs(cur realm, t *testing.T) {
	resetEventConfigForTest()

	packet := types.Packet{
		SourceChannelId:      types.ChannelId(1),
		DestinationChannelId: types.ChannelId(2),
		Data:                 []byte{0, 1, 2, 3},
		TimeoutTimestamp:     types.Timestamp(4),
	}
	sourceChannel := types.Channel{
		ConnectionId: types.ConnectionId(3),
	}
	acknowledgement := []byte{4, 5, 6, 7}

	attrs := packetAckEventAttrs(packet, sourceChannel, testConnection, acknowledgement)

	assertStringSliceEqual(t, attrs, []string{
		"packet_hash", commitPacketHash(packet).String(),
		"source_channel_id", "1",
		"source_connection_id", "3",
		"source_connection_client_id", "10",
		"destination_channel_id", "2",
		"destination_connection_id", "30",
		"destination_connection_client_id", "20",
		"timeout_timestamp", "4",
		"packet_data_size", strconv.Itoa(len(hexAttr(packet.Data))),
		"packet_data[0]", hexAttr(packet.Data),
		"acknowledgement_size", strconv.Itoa(len(hexAttr(acknowledgement))),
		"acknowledgement[0]", hexAttr(acknowledgement),
	})
}

func TestPacketTimeoutEventAttrs(cur realm, t *testing.T) {
	resetEventConfigForTest()

	packet := types.Packet{
		SourceChannelId:      types.ChannelId(1),
		DestinationChannelId: types.ChannelId(2),
		Data:                 []byte{0, 1, 2, 3},
		TimeoutTimestamp:     types.Timestamp(4),
	}
	sourceChannel := types.Channel{
		ConnectionId: types.ConnectionId(3),
		Version:      "ucs03-zkgm-0",
	}

	attrs := packetTimeoutEventAttrs(packet, sourceChannel, testConnection)

	assertStringSliceEqual(t, attrs, []string{
		"packet_hash", commitPacketHash(packet).String(),
		"source_channel_id", "1",
		"source_channel_version", "ucs03-zkgm-0",
		"source_connection_id", "3",
		"source_connection_client_id", "10",
		"destination_channel_id", "2",
		"destination_connection_id", "30",
		"destination_connection_client_id", "20",
		"timeout_timestamp", "4",
		"packet_data_size", strconv.Itoa(len(hexAttr(packet.Data))),
		"packet_data[0]", hexAttr(packet.Data),
	})
}

func TestEventAttrColumnsBoundary(cur realm, t *testing.T) {
	resetEventConfigForTest()

	maxLen := int(GetEventConfig().MaxEventAttrValueLen)
	if maxLen != 1024 {
		t.Fatalf("configured max event attr value len = %d, want 1024", maxLen)
	}
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
			name:     "1023 bytes stays in one column",
			value:    fixedEventAttrColumn[:maxLen-1],
			wantLens: []int{maxLen - 1},
		},
		{
			name:     "1024 bytes stays in one full column",
			value:    fixedEventAttrColumn,
			wantLens: []int{maxLen},
		},
		{
			name:     "1025 bytes splits into full column and remainder",
			value:    fixedEventAttrColumn + "2",
			wantLens: []int{maxLen, 1},
		},
		{
			name:     "three columns",
			value:    fixedEventAttrColumn + fixedEventAttrColumn + "3",
			wantLens: []int{maxLen, maxLen, 1},
		},
		{
			name:     "four columns",
			value:    fixedEventAttrColumn + fixedEventAttrColumn + fixedEventAttrColumn + "4",
			wantLens: []int{maxLen, maxLen, maxLen, 1},
		},
	}

	for _, tc := range testCases {
		t.Run(tc.name, func(t *testing.T) {
			attrs := eventAttrColumns("packet_data", tc.value, maxLen)
			assertEventAttrColumnLens(t, attrs, "packet_data", tc.value, tc.wantLens, maxLen)
		})
	}
}

func TestEventAttrColumnsRejectsInvalidMaxValueLen(cur realm, t *testing.T) {
	testCases := []struct {
		name        string
		maxValueLen int
	}{
		{"negative max value len", -1},
		{"zero max value len", 0},
	}

	for _, tc := range testCases {
		t.Run(tc.name, func(t *testing.T) {
			uassert.AbortsContains(t, cur, "max event attr value len must be positive", func(cur realm) {
				eventAttrColumns("packet_data", "0x00", tc.maxValueLen)
			})
		})
	}
}

func assertEventAttrColumnLens(t *testing.T, attrs []string, key string, value string, wantLens []int, maxLen int) {
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
		if len(attrs[valueIndex]) > maxLen {
			t.Fatalf("attr value[%d] len exceeds max: got %d want <= %d", i, len(attrs[valueIndex]), maxLen)
		}
		rejoined += attrs[valueIndex]
	}
	if rejoined != value {
		t.Fatalf("rejoined attr value: got %q want %q", rejoined, value)
	}
}
