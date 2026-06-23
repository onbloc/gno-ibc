package core

import (
	"testing"

	"gno.land/p/onbloc/ibc/union/types"
)

func TestCommitPacketHash(cur realm, t *testing.T) {
	cases := []struct {
		name   string
		packet types.Packet
	}{
		{
			"empty data",
			types.Packet{SourceChannelId: 1, DestinationChannelId: 2, TimeoutTimestamp: 1000},
		},
		{
			"payload data",
			types.Packet{SourceChannelId: 1, DestinationChannelId: 2, Data: types.Bytes("payload"), TimeoutTimestamp: 1000},
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			want := types.MustCommit(types.CommitPacket(tc.packet))
			if got := commitPacketHash(tc.packet); got != want {
				t.Errorf("commitPacketHash: got %s want %s", got.String(), want.String())
			}
		})
	}
}

func TestCommitPacketsHash(cur realm, t *testing.T) {
	packets := []types.Packet{
		{SourceChannelId: 1, DestinationChannelId: 2, Data: types.Bytes("a"), TimeoutTimestamp: 1000},
		{SourceChannelId: 1, DestinationChannelId: 2, Data: types.Bytes("b"), TimeoutTimestamp: 1000},
	}
	want := types.MustCommit(types.CommitPackets(packets))
	if got := commitPacketsHash(packets); got != want {
		t.Errorf("commitPacketsHash: got %s want %s", got.String(), want.String())
	}
}

func TestPacketCommitmentPath(cur realm, t *testing.T) {
	p1 := types.Packet{SourceChannelId: 1, DestinationChannelId: 2, TimeoutTimestamp: 1000}
	p2 := types.Packet{SourceChannelId: 1, DestinationChannelId: 2, Data: types.Bytes("different"), TimeoutTimestamp: 1000}
	if packetCommitmentPath(p1) == packetCommitmentPath(p2) {
		t.Error("packets with different Union payloads must have different commitment paths")
	}
}

func TestPacketAcknowledgementPath(cur realm, t *testing.T) {
	packet := types.Packet{SourceChannelId: 1, DestinationChannelId: 2, TimeoutTimestamp: 1000}
	batchHash := commitPacketHash(packet)
	if packetAcknowledgementPath(packet) != types.BatchReceiptsPath(batchHash) {
		t.Error("packet acknowledgement path must use Union batch receipts path")
	}
}

func TestChannelValue(cur realm, t *testing.T) {
	cases := []struct {
		name    string
		channel types.Channel
		want    string
	}{
		{
			"distinct state open",
			types.Channel{State: types.ChannelStateOpen, ConnectionId: 1, CounterpartyChannelId: 2, Version: "v1"},
			"",
		},
		{
			"union integration vector",
			types.Channel{
				State:                 types.ChannelStateInit,
				ConnectionId:          3,
				CounterpartyChannelId: 0,
				CounterpartyPortId:    types.Bytes(mustHex("5fbe74a283f7954f10aa04c2edf55578811aeb03")),
				Version:               "ucs03-zkgm-0",
			},
			"0x00781657f014fd25772f10edb002612aa3839e958adf1aa1d2c0f7a44758da26",
		},
	}

	openValue := channelValue(cases[0].channel)
	closedValue := channelValue(types.Channel{State: types.ChannelStateClosed, ConnectionId: 1, CounterpartyChannelId: 2, Version: "v1"})
	if openValue == closedValue {
		t.Error("different channel states must encode differently")
	}
	assertH256Hex(t, cases[1].name, channelValue(cases[1].channel), cases[1].want)
}

func TestConnectionValue(cur realm, t *testing.T) {
	open := types.Connection{State: types.ConnectionStateOpen, ClientId: 1, CounterpartyClientId: 2, CounterpartyConnectionId: 3}
	init := types.Connection{State: types.ConnectionStateInit, ClientId: 1, CounterpartyClientId: 2, CounterpartyConnectionId: 3}
	if connectionValue(open) == connectionValue(init) {
		t.Error("different connection states must encode differently")
	}
}

func TestH256Bytes(cur realm, t *testing.T) {
	h := types.H256{0x01, 0x02, 0x03}
	got := h256Bytes(h)
	if hexString(got) != "0x0102030000000000000000000000000000000000000000000000000000000000" {
		t.Errorf("h256Bytes: got %s", hexString(got))
	}
	got[0] = 0xff
	if h[0] != 0x01 {
		t.Fatal("h256Bytes must not alias input array")
	}
}

func TestCloneChannel(cur realm, t *testing.T) {
	in := types.Channel{
		State:              types.ChannelStateOpen,
		ConnectionId:       1,
		CounterpartyPortId: types.Bytes{1, 2, 3},
		Version:            "v1",
	}
	got := cloneChannel(in)
	got.CounterpartyPortId[0] = 9
	if in.CounterpartyPortId[0] == 9 {
		t.Fatal("cloneChannel must not alias CounterpartyPortId")
	}
}

func TestCloneBytes(cur realm, t *testing.T) {
	cases := []struct {
		name string
		in   []byte
	}{
		{"nil", nil},
		{"empty", []byte{}},
		{"value", []byte{1, 2, 3}},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got := cloneBytes(tc.in)
			if len(got) != len(tc.in) {
				t.Fatalf("len: got %d want %d", len(got), len(tc.in))
			}
			if tc.in == nil && got != nil {
				t.Fatal("nil input must remain nil")
			}
			if len(got) > 0 {
				got[0] = 9
				if tc.in[0] == 9 {
					t.Fatal("clone must not alias input")
				}
			}
		})
	}
}

func TestHexString(cur realm, t *testing.T) {
	cases := []struct {
		name string
		in   []byte
		want string
	}{
		{"empty", []byte{}, "0x"},
		{"binary", []byte{0, 15, 255}, "0x000fff"},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			if got := hexString(tc.in); got != tc.want {
				t.Errorf("hexString: got %q want %q", got, tc.want)
			}
		})
	}
}

func TestHexAttr(cur realm, t *testing.T) {
	cases := []struct {
		name string
		in   []byte
		want string
	}{
		{"empty", []byte{}, "0x"},
		{"binary", []byte{0, 15, 255}, "0x000fff"},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			if got := hexAttr(tc.in); got != tc.want {
				t.Errorf("hexAttr: got %q want %q", got, tc.want)
			}
		})
	}
}

func TestH256String(cur realm, t *testing.T) {
	h := types.H256{0x01, 0x02, 0x03}
	if got, want := h256String(h), "0x0102030000000000000000000000000000000000000000000000000000000000"; got != want {
		t.Errorf("h256String: got %q want %q", got, want)
	}
}
