package core

import (
	"testing"

	"gno.land/p/onbloc/ibc/union/types"
)

func TestCoreConstructorsWrapTypes(cur realm, t *testing.T) {
	packet := NewPacket(1, 2, []byte("data"), 10)
	channel := NewChannel(types.ChannelStateInit, 3, 4, []byte("counterparty"), "ics20-1")

	cases := []struct {
		name string
		run  func()
	}{
		{"NewChannel", func() {
			got := channel
			if got.State != types.ChannelStateInit || got.ConnectionId != 3 || got.CounterpartyChannelId != 4 || string(got.CounterpartyPortId) != "counterparty" || got.Version != "ics20-1" {
				t.Fatalf("NewChannel returned unexpected channel: %#v", got)
			}
		}},
		{"NewConnection", func() {
			got := NewConnection(types.ConnectionStateOpen, 1, 2, 3)
			if got.State != types.ConnectionStateOpen || got.ClientId != 1 || got.CounterpartyClientId != 2 || got.CounterpartyConnectionId != 3 {
				t.Fatalf("NewConnection returned unexpected connection: %#v", got)
			}
		}},
		{"NewPacket", func() {
			got := packet
			if got.SourceChannelId != 1 || got.DestinationChannelId != 2 || string(got.Data) != "data" || got.TimeoutTimestamp != 10 {
				t.Fatalf("NewPacket returned unexpected packet: %#v", got)
			}
		}},
		{"NewRecvPacketResult", func() {
			got := NewRecvPacketResult(types.PacketStatusSuccess, []byte("ack"))
			if got.Status != types.PacketStatusSuccess || string(got.Acknowledgement) != "ack" {
				t.Fatalf("NewRecvPacketResult returned unexpected result: %#v", got)
			}
		}},
		{"NewMsgChannelOpenTry", func() {
			got := NewMsgChannelOpenTry([]byte("port"), channel, "cp-v1", []byte("proof"), 7, "g1relayer")
			if string(got.PortId) != "port" || got.Channel.ConnectionId != 3 || got.CounterpartyVersion != "cp-v1" || string(got.ProofInit) != "proof" || got.ProofHeight != 7 || got.Relayer != "g1relayer" {
				t.Fatalf("NewMsgChannelOpenTry returned unexpected msg: %#v", got)
			}
		}},
		{"NewMsgCreateClient", func() {
			got := NewMsgCreateClient(mockType, []byte("cs"), []byte("cons"))
			if got.ClientType != mockType || string(got.ClientStateBytes) != "cs" || string(got.ConsensusStateBytes) != "cons" {
				t.Fatalf("NewMsgCreateClient returned unexpected msg: %#v", got)
			}
		}},
		{"NewMsgConnectionOpenInit", func() {
			got := NewMsgConnectionOpenInit(1, 2)
			if got.ClientId != 1 || got.CounterpartyClientId != 2 {
				t.Fatalf("NewMsgConnectionOpenInit returned unexpected msg: %#v", got)
			}
		}},
		{"NewMsgConnectionOpenAck", func() {
			got := NewMsgConnectionOpenAck(1, 2, []byte("proof"), 7)
			if got.ConnectionId != 1 || got.CounterpartyConnectionId != 2 || string(got.ProofTry) != "proof" || got.ProofHeight != 7 {
				t.Fatalf("NewMsgConnectionOpenAck returned unexpected msg: %#v", got)
			}
		}},
		{"NewMsgChannelOpenInit", func() {
			got := NewMsgChannelOpenInit([]byte("port"), []byte("cp"), 3, "ics20-1", "g1relayer")
			if string(got.PortId) != "port" || string(got.CounterpartyPortId) != "cp" || got.ConnectionId != 3 || got.Version != "ics20-1" || got.Relayer != "g1relayer" {
				t.Fatalf("NewMsgChannelOpenInit returned unexpected msg: %#v", got)
			}
		}},
		{"NewMsgChannelOpenAck", func() {
			got := NewMsgChannelOpenAck(1, "cp-v1", 2, []byte("proof"), 7, "g1relayer")
			if got.ChannelId != 1 || got.CounterpartyVersion != "cp-v1" || got.CounterpartyChannelId != 2 || string(got.ProofTry) != "proof" || got.ProofHeight != 7 || got.Relayer != "g1relayer" {
				t.Fatalf("NewMsgChannelOpenAck returned unexpected msg: %#v", got)
			}
		}},
		{"NewMsgPacketRecv", func() {
			got := NewMsgPacketRecv([]types.Packet{packet}, [][]byte{[]byte("relayer-msg")}, []byte("proof"), 7)
			if len(got.Packets) != 1 || string(got.RelayerMsgs[0]) != "relayer-msg" || string(got.Proof) != "proof" || got.ProofHeight != 7 {
				t.Fatalf("NewMsgPacketRecv returned unexpected msg: %#v", got)
			}
		}},
		{"NewMsgPacketAcknowledgement", func() {
			got := NewMsgPacketAcknowledgement([]types.Packet{packet}, [][]byte{[]byte("ack")}, []byte("proof"), 7)
			if len(got.Packets) != 1 || string(got.Acknowledgements[0]) != "ack" || string(got.Proof) != "proof" || got.ProofHeight != 7 {
				t.Fatalf("NewMsgPacketAcknowledgement returned unexpected msg: %#v", got)
			}
		}},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			tc.run()
		})
	}
}
