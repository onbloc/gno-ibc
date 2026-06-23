package types

import (
	"bytes"
	"testing"
)

func TestNewMsgCreateClient(t *testing.T) {
	tests := []struct {
		name                string
		clientType          ClientType
		clientStateBytes    []byte
		consensusStateBytes []byte
		wantClientType      ClientType
		wantClientState     []byte
		wantConsensusState  []byte
	}{
		{
			name:                "all zero values",
			clientType:          "",
			clientStateBytes:    nil,
			consensusStateBytes: nil,
			wantClientType:      "",
			wantClientState:     nil,
			wantConsensusState:  nil,
		},
		{
			name:                "with client type",
			clientType:          "cometbls",
			clientStateBytes:    []byte{0x01, 0x02, 0x03},
			consensusStateBytes: []byte{0x04, 0x05, 0x06},
			wantClientType:      "cometbls",
			wantClientState:     []byte{0x01, 0x02, 0x03},
			wantConsensusState:  []byte{0x04, 0x05, 0x06},
		},
		{
			name:                "empty client type with non-empty bytes",
			clientType:          "",
			clientStateBytes:    []byte{0xff},
			consensusStateBytes: []byte{},
			wantClientType:      "",
			wantClientState:     []byte{0xff},
			wantConsensusState:  []byte{},
		},
		{
			name:                "large byte arrays",
			clientType:          "mock",
			clientStateBytes:    make([]byte, 100),
			consensusStateBytes: make([]byte, 200),
			wantClientType:      "mock",
			wantClientState:     make([]byte, 100),
			wantConsensusState:  make([]byte, 200),
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			got := NewMsgCreateClient(tc.clientType, tc.clientStateBytes, tc.consensusStateBytes)

			if got.ClientType != tc.wantClientType {
				t.Errorf("ClientType = %q, want %q", got.ClientType, tc.wantClientType)
			}
			assertBytes(t, "ClientStateBytes", got.ClientStateBytes, tc.wantClientState)
			assertBytes(t, "ConsensusStateBytes", got.ConsensusStateBytes, tc.wantConsensusState)
		})
	}
}

func TestNewMsgUpdateClient(t *testing.T) {
	tests := []struct {
		name          string
		clientId      ClientId
		clientMessage []byte
		wantClientId  ClientId
		wantMessage   []byte
	}{
		{
			name:          "zero values",
			clientId:      0,
			clientMessage: nil,
			wantClientId:  0,
			wantMessage:   nil,
		},
		{
			name:          "non-zero values",
			clientId:      1,
			clientMessage: []byte{0x01, 0x02},
			wantClientId:  1,
			wantMessage:   []byte{0x01, 0x02},
		},
		{
			name:          "max client id",
			clientId:      4294967295,
			clientMessage: []byte{0xff, 0xfe, 0xfd},
			wantClientId:  4294967295,
			wantMessage:   []byte{0xff, 0xfe, 0xfd},
		},
		{
			name:          "empty message",
			clientId:      42,
			clientMessage: []byte{},
			wantClientId:  42,
			wantMessage:   []byte{},
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			got := NewMsgUpdateClient(tc.clientId, tc.clientMessage)

			if got.ClientId != tc.wantClientId {
				t.Errorf("ClientId = %v, want %v", got.ClientId, tc.wantClientId)
			}
			assertBytes(t, "ClientMessage", got.ClientMessage, tc.wantMessage)
		})
	}
}

func TestNewMsgForceUpdateClient(t *testing.T) {
	tests := []struct {
		name                string
		clientId            ClientId
		clientStateBytes    []byte
		consensusStateBytes []byte
		wantClientId        ClientId
		wantClientState     []byte
		wantConsensusState  []byte
	}{
		{
			name:                "zero values",
			clientId:            0,
			clientStateBytes:    nil,
			consensusStateBytes: nil,
			wantClientId:        0,
			wantClientState:     nil,
			wantConsensusState:  nil,
		},
		{
			name:                "non-zero values",
			clientId:            5,
			clientStateBytes:    []byte{0xaa},
			consensusStateBytes: []byte{0xbb},
			wantClientId:        5,
			wantClientState:     []byte{0xaa},
			wantConsensusState:  []byte{0xbb},
		},
		{
			name:                "with empty client state",
			clientId:            100,
			clientStateBytes:    []byte{},
			consensusStateBytes: []byte{0xcc},
			wantClientId:        100,
			wantClientState:     []byte{},
			wantConsensusState:  []byte{0xcc},
		},
		{
			name:                "with empty consensus state",
			clientId:            200,
			clientStateBytes:    []byte{0xdd},
			consensusStateBytes: []byte{},
			wantClientId:        200,
			wantClientState:     []byte{0xdd},
			wantConsensusState:  []byte{},
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			got := NewMsgForceUpdateClient(tc.clientId, tc.clientStateBytes, tc.consensusStateBytes)

			if got.ClientId != tc.wantClientId {
				t.Errorf("ClientId = %v, want %v", got.ClientId, tc.wantClientId)
			}
			assertBytes(t, "ClientStateBytes", got.ClientStateBytes, tc.wantClientState)
			assertBytes(t, "ConsensusStateBytes", got.ConsensusStateBytes, tc.wantConsensusState)
		})
	}
}

func TestNewMsgMisbehaviour(t *testing.T) {
	tests := []struct {
		name          string
		clientId      ClientId
		clientMessage []byte
		relayer       string
		wantClientId  ClientId
		wantMessage   []byte
		wantRelayer   string
	}{
		{
			name:          "zero values",
			clientId:      0,
			clientMessage: nil,
			relayer:       "",
			wantClientId:  0,
			wantMessage:   nil,
			wantRelayer:   "",
		},
		{
			name:          "with relayer",
			clientId:      1,
			clientMessage: []byte{0x01},
			relayer:       "relayer1",
			wantClientId:  1,
			wantMessage:   []byte{0x01},
			wantRelayer:   "relayer1",
		},
		{
			name:          "empty relayer",
			clientId:      2,
			clientMessage: []byte{0x02, 0x03},
			relayer:       "",
			wantClientId:  2,
			wantMessage:   []byte{0x02, 0x03},
			wantRelayer:   "",
		},
		{
			name:          "non-empty message with empty relayer",
			clientId:      999,
			clientMessage: []byte{0xde, 0xad, 0xbe, 0xef},
			relayer:       "",
			wantClientId:  999,
			wantMessage:   []byte{0xde, 0xad, 0xbe, 0xef},
			wantRelayer:   "",
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			got := NewMsgMisbehaviour(tc.clientId, tc.clientMessage, tc.relayer)

			if got.ClientId != tc.wantClientId {
				t.Errorf("ClientId = %v, want %v", got.ClientId, tc.wantClientId)
			}
			assertBytes(t, "ClientMessage", got.ClientMessage, tc.wantMessage)
			if got.Relayer != tc.wantRelayer {
				t.Errorf("Relayer = %q, want %q", got.Relayer, tc.wantRelayer)
			}
		})
	}
}

func TestNewMsgConnectionOpenInit(t *testing.T) {
	tests := []struct {
		name                 string
		clientId             ClientId
		counterpartyClientId ClientId
		wantClientId         ClientId
		wantCounterpartyId   ClientId
	}{
		{
			name:                 "both zero",
			clientId:             0,
			counterpartyClientId: 0,
			wantClientId:         0,
			wantCounterpartyId:   0,
		},
		{
			name:                 "non-zero values",
			clientId:             1,
			counterpartyClientId: 2,
			wantClientId:         1,
			wantCounterpartyId:   2,
		},
		{
			name:                 "max values",
			clientId:             4294967295,
			counterpartyClientId: 4294967294,
			wantClientId:         4294967295,
			wantCounterpartyId:   4294967294,
		},
		{
			name:                 "mixed zero and non-zero",
			clientId:             0,
			counterpartyClientId: 42,
			wantClientId:         0,
			wantCounterpartyId:   42,
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			got := NewMsgConnectionOpenInit(tc.clientId, tc.counterpartyClientId)

			if got.ClientId != tc.wantClientId {
				t.Errorf("ClientId = %v, want %v", got.ClientId, tc.wantClientId)
			}
			if got.CounterpartyClientId != tc.wantCounterpartyId {
				t.Errorf("CounterpartyClientId = %v, want %v", got.CounterpartyClientId, tc.wantCounterpartyId)
			}
		})
	}
}

func TestNewMsgConnectionOpenTry(t *testing.T) {
	tests := []struct {
		name                     string
		clientId                 ClientId
		counterpartyClientId     ClientId
		counterpartyConnectionId ConnectionId
		proofInit                []byte
		proofHeight              uint64
		wantClientId             ClientId
		wantCounterpartyId       ClientId
		wantCounterpartyConnId   ConnectionId
		wantProofInit            []byte
		wantProofHeight          uint64
	}{
		{
			name:                     "zero values",
			clientId:                 0,
			counterpartyClientId:     0,
			counterpartyConnectionId: 0,
			proofInit:                nil,
			proofHeight:              0,
			wantClientId:             0,
			wantCounterpartyId:       0,
			wantCounterpartyConnId:   0,
			wantProofInit:            nil,
			wantProofHeight:          0,
		},
		{
			name:                     "non-zero values",
			clientId:                 1,
			counterpartyClientId:     2,
			counterpartyConnectionId: 3,
			proofInit:                []byte{0x01},
			proofHeight:              100,
			wantClientId:             1,
			wantCounterpartyId:       2,
			wantCounterpartyConnId:   3,
			wantProofInit:            []byte{0x01},
			wantProofHeight:          100,
		},
		{
			name:                     "max uint64 proof height",
			clientId:                 10,
			counterpartyClientId:     20,
			counterpartyConnectionId: 30,
			proofInit:                []byte{0xaa, 0xbb},
			proofHeight:              18446744073709551615,
			wantClientId:             10,
			wantCounterpartyId:       20,
			wantCounterpartyConnId:   30,
			wantProofInit:            []byte{0xaa, 0xbb},
			wantProofHeight:          18446744073709551615,
		},
		{
			name:                     "empty proof",
			clientId:                 5,
			counterpartyClientId:     6,
			counterpartyConnectionId: 7,
			proofInit:                []byte{},
			proofHeight:              1,
			wantClientId:             5,
			wantCounterpartyId:       6,
			wantCounterpartyConnId:   7,
			wantProofInit:            []byte{},
			wantProofHeight:          1,
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			got := NewMsgConnectionOpenTry(tc.clientId, tc.counterpartyClientId, tc.counterpartyConnectionId, tc.proofInit, tc.proofHeight)

			if got.ClientId != tc.wantClientId {
				t.Errorf("ClientId = %v, want %v", got.ClientId, tc.wantClientId)
			}
			if got.CounterpartyClientId != tc.wantCounterpartyId {
				t.Errorf("CounterpartyClientId = %v, want %v", got.CounterpartyClientId, tc.wantCounterpartyId)
			}
			if got.CounterpartyConnectionId != tc.wantCounterpartyConnId {
				t.Errorf("CounterpartyConnectionId = %v, want %v", got.CounterpartyConnectionId, tc.wantCounterpartyConnId)
			}
			assertBytes(t, "ProofInit", got.ProofInit, tc.wantProofInit)
			if got.ProofHeight != tc.wantProofHeight {
				t.Errorf("ProofHeight = %v, want %v", got.ProofHeight, tc.wantProofHeight)
			}
		})
	}
}

func TestNewMsgConnectionOpenAck(t *testing.T) {
	tests := []struct {
		name                     string
		connectionId             ConnectionId
		counterpartyConnectionId ConnectionId
		proofTry                 []byte
		proofHeight              uint64
		wantConnectionId         ConnectionId
		wantCounterpartyConnId   ConnectionId
		wantProofTry             []byte
		wantProofHeight          uint64
	}{
		{
			name:                     "zero values",
			connectionId:             0,
			counterpartyConnectionId: 0,
			proofTry:                 nil,
			proofHeight:              0,
			wantConnectionId:         0,
			wantCounterpartyConnId:   0,
			wantProofTry:             nil,
			wantProofHeight:          0,
		},
		{
			name:                     "non-zero values",
			connectionId:             1,
			counterpartyConnectionId: 2,
			proofTry:                 []byte{0x01},
			proofHeight:              50,
			wantConnectionId:         1,
			wantCounterpartyConnId:   2,
			wantProofTry:             []byte{0x01},
			wantProofHeight:          50,
		},
		{
			name:                     "large values",
			connectionId:             1000,
			counterpartyConnectionId: 2000,
			proofTry:                 make([]byte, 50),
			proofHeight:              1000000,
			wantConnectionId:         1000,
			wantCounterpartyConnId:   2000,
			wantProofTry:             make([]byte, 50),
			wantProofHeight:          1000000,
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			got := NewMsgConnectionOpenAck(tc.connectionId, tc.counterpartyConnectionId, tc.proofTry, tc.proofHeight)

			if got.ConnectionId != tc.wantConnectionId {
				t.Errorf("ConnectionId = %v, want %v", got.ConnectionId, tc.wantConnectionId)
			}
			if got.CounterpartyConnectionId != tc.wantCounterpartyConnId {
				t.Errorf("CounterpartyConnectionId = %v, want %v", got.CounterpartyConnectionId, tc.wantCounterpartyConnId)
			}
			assertBytes(t, "ProofTry", got.ProofTry, tc.wantProofTry)
			if got.ProofHeight != tc.wantProofHeight {
				t.Errorf("ProofHeight = %v, want %v", got.ProofHeight, tc.wantProofHeight)
			}
		})
	}
}

func TestNewMsgConnectionOpenConfirm(t *testing.T) {
	tests := []struct {
		name         string
		connectionId ConnectionId
		proofAck     []byte
		proofHeight  uint64
		wantConnId   ConnectionId
		wantProofAck []byte
		wantProofH   uint64
	}{
		{
			name:         "zero values",
			connectionId: 0,
			proofAck:     nil,
			proofHeight:  0,
			wantConnId:   0,
			wantProofAck: nil,
			wantProofH:   0,
		},
		{
			name:         "non-zero values",
			connectionId: 5,
			proofAck:     []byte{0xaa},
			proofHeight:  75,
			wantConnId:   5,
			wantProofAck: []byte{0xaa},
			wantProofH:   75,
		},
		{
			name:         "empty proof",
			connectionId: 10,
			proofAck:     []byte{},
			proofHeight:  1,
			wantConnId:   10,
			wantProofAck: []byte{},
			wantProofH:   1,
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			got := NewMsgConnectionOpenConfirm(tc.connectionId, tc.proofAck, tc.proofHeight)

			if got.ConnectionId != tc.wantConnId {
				t.Errorf("ConnectionId = %v, want %v", got.ConnectionId, tc.wantConnId)
			}
			assertBytes(t, "ProofAck", got.ProofAck, tc.wantProofAck)
			if got.ProofHeight != tc.wantProofH {
				t.Errorf("ProofHeight = %v, want %v", got.ProofHeight, tc.wantProofH)
			}
		})
	}
}

func TestNewMsgChannelOpenInit(t *testing.T) {
	tests := []struct {
		name                 string
		portId               []byte
		counterpartyPortId   []byte
		connectionId         ConnectionId
		version              string
		relayer              string
		wantPortId           []byte
		wantCounterpartyPort []byte
		wantConnId           ConnectionId
		wantVersion          string
		wantRelayer          string
	}{
		{
			name:                 "zero values",
			portId:               nil,
			counterpartyPortId:   nil,
			connectionId:         0,
			version:              "",
			relayer:              "",
			wantPortId:           nil,
			wantCounterpartyPort: nil,
			wantConnId:           0,
			wantVersion:          "",
			wantRelayer:          "",
		},
		{
			name:                 "non-zero values",
			portId:               []byte("portA"),
			counterpartyPortId:   []byte("portB"),
			connectionId:         1,
			version:              "1.0",
			relayer:              "relayer1",
			wantPortId:           []byte("portA"),
			wantCounterpartyPort: []byte("portB"),
			wantConnId:           1,
			wantVersion:          "1.0",
			wantRelayer:          "relayer1",
		},
		{
			name:                 "empty version and relayer",
			portId:               []byte{0x01},
			counterpartyPortId:   []byte{0x02},
			connectionId:         42,
			version:              "",
			relayer:              "",
			wantPortId:           []byte{0x01},
			wantCounterpartyPort: []byte{0x02},
			wantConnId:           42,
			wantVersion:          "",
			wantRelayer:          "",
		},
		{
			name:                 "empty port ids",
			portId:               []byte{},
			counterpartyPortId:   []byte{},
			connectionId:         0,
			version:              "ics20-1",
			relayer:              "gno:1abc",
			wantPortId:           []byte{},
			wantCounterpartyPort: []byte{},
			wantConnId:           0,
			wantVersion:          "ics20-1",
			wantRelayer:          "gno:1abc",
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			got := NewMsgChannelOpenInit(tc.portId, tc.counterpartyPortId, tc.connectionId, tc.version, tc.relayer)

			assertBytes(t, "PortId", got.PortId, tc.wantPortId)
			assertBytes(t, "CounterpartyPortId", got.CounterpartyPortId, tc.wantCounterpartyPort)
			if got.ConnectionId != tc.wantConnId {
				t.Errorf("ConnectionId = %v, want %v", got.ConnectionId, tc.wantConnId)
			}
			if got.Version != tc.wantVersion {
				t.Errorf("Version = %q, want %q", got.Version, tc.wantVersion)
			}
			if got.Relayer != tc.wantRelayer {
				t.Errorf("Relayer = %q, want %q", got.Relayer, tc.wantRelayer)
			}
		})
	}
}

func TestNewMsgChannelOpenTry(t *testing.T) {
	channel := NewChannel(ChannelStateInit, 1, 2, Bytes([]byte("counterport")), "1.0")

	tests := []struct {
		name                string
		portId              []byte
		channel             Channel
		counterpartyVersion string
		proofInit           []byte
		proofHeight         uint64
		relayer             string
		wantPortId          []byte
		wantVersion         string
		wantProofInit       []byte
		wantProofHeight     uint64
		wantRelayer         string
	}{
		{
			name:                "zero values",
			portId:              nil,
			channel:             Channel{},
			counterpartyVersion: "",
			proofInit:           nil,
			proofHeight:         0,
			relayer:             "",
			wantPortId:          nil,
			wantVersion:         "",
			wantProofInit:       nil,
			wantProofHeight:     0,
			wantRelayer:         "",
		},
		{
			name:                "non-zero values",
			portId:              []byte("transfer"),
			channel:             channel,
			counterpartyVersion: "ics20-1",
			proofInit:           []byte{0x01},
			proofHeight:         100,
			relayer:             "relayer",
			wantPortId:          []byte("transfer"),
			wantVersion:         "ics20-1",
			wantProofInit:       []byte{0x01},
			wantProofHeight:     100,
			wantRelayer:         "relayer",
		},
		{
			name:                "empty version",
			portId:              []byte{0xff},
			channel:             NewChannel(ChannelStateTryOpen, 10, 20, Bytes([]byte{}), ""),
			counterpartyVersion: "",
			proofInit:           []byte{0xaa},
			proofHeight:         1,
			relayer:             "",
			wantPortId:          []byte{0xff},
			wantVersion:         "",
			wantProofInit:       []byte{0xaa},
			wantProofHeight:     1,
			wantRelayer:         "",
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			got := NewMsgChannelOpenTry(tc.portId, tc.channel, tc.counterpartyVersion, tc.proofInit, tc.proofHeight, tc.relayer)

			assertBytes(t, "PortId", got.PortId, tc.wantPortId)
			if got.Channel.State != tc.channel.State ||
				got.Channel.ConnectionId != tc.channel.ConnectionId ||
				got.Channel.CounterpartyChannelId != tc.channel.CounterpartyChannelId ||
				got.Channel.Version != tc.channel.Version {
				t.Errorf("Channel mismatch")
			}
			assertBytes(t, "CounterpartyPortId", got.Channel.CounterpartyPortId, tc.channel.CounterpartyPortId)
			if got.CounterpartyVersion != tc.wantVersion {
				t.Errorf("CounterpartyVersion = %q, want %q", got.CounterpartyVersion, tc.wantVersion)
			}
			assertBytes(t, "ProofInit", got.ProofInit, tc.wantProofInit)
			if got.ProofHeight != tc.wantProofHeight {
				t.Errorf("ProofHeight = %v, want %v", got.ProofHeight, tc.wantProofHeight)
			}
			if got.Relayer != tc.wantRelayer {
				t.Errorf("Relayer = %q, want %q", got.Relayer, tc.wantRelayer)
			}
		})
	}
}

func TestNewMsgChannelOpenAck(t *testing.T) {
	tests := []struct {
		name                  string
		channelId             ChannelId
		counterpartyVersion   string
		counterpartyChannelId ChannelId
		proofTry              []byte
		proofHeight           uint64
		relayer               string
		wantChannelId         ChannelId
		wantVersion           string
		wantCounterpartyId    ChannelId
		wantProofTry          []byte
		wantProofHeight       uint64
		wantRelayer           string
	}{
		{
			name:                  "zero values",
			channelId:             0,
			counterpartyVersion:   "",
			counterpartyChannelId: 0,
			proofTry:              nil,
			proofHeight:           0,
			relayer:               "",
			wantChannelId:         0,
			wantVersion:           "",
			wantCounterpartyId:    0,
			wantProofTry:          nil,
			wantProofHeight:       0,
			wantRelayer:           "",
		},
		{
			name:                  "non-zero values",
			channelId:             1,
			counterpartyVersion:   "ics20-1",
			counterpartyChannelId: 2,
			proofTry:              []byte{0x01},
			proofHeight:           150,
			relayer:               "relayer1",
			wantChannelId:         1,
			wantVersion:           "ics20-1",
			wantCounterpartyId:    2,
			wantProofTry:          []byte{0x01},
			wantProofHeight:       150,
			wantRelayer:           "relayer1",
		},
		{
			name:                  "max channel ids",
			channelId:             4294967295,
			counterpartyVersion:   "v2",
			counterpartyChannelId: 4294967294,
			proofTry:              []byte{0xff},
			proofHeight:           999,
			relayer:               "",
			wantChannelId:         4294967295,
			wantVersion:           "v2",
			wantCounterpartyId:    4294967294,
			wantProofTry:          []byte{0xff},
			wantProofHeight:       999,
			wantRelayer:           "",
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			got := NewMsgChannelOpenAck(tc.channelId, tc.counterpartyVersion, tc.counterpartyChannelId, tc.proofTry, tc.proofHeight, tc.relayer)

			if got.ChannelId != tc.wantChannelId {
				t.Errorf("ChannelId = %v, want %v", got.ChannelId, tc.wantChannelId)
			}
			if got.CounterpartyVersion != tc.wantVersion {
				t.Errorf("CounterpartyVersion = %q, want %q", got.CounterpartyVersion, tc.wantVersion)
			}
			if got.CounterpartyChannelId != tc.wantCounterpartyId {
				t.Errorf("CounterpartyChannelId = %v, want %v", got.CounterpartyChannelId, tc.wantCounterpartyId)
			}
			assertBytes(t, "ProofTry", got.ProofTry, tc.wantProofTry)
			if got.ProofHeight != tc.wantProofHeight {
				t.Errorf("ProofHeight = %v, want %v", got.ProofHeight, tc.wantProofHeight)
			}
			if got.Relayer != tc.wantRelayer {
				t.Errorf("Relayer = %q, want %q", got.Relayer, tc.wantRelayer)
			}
		})
	}
}

func TestNewMsgChannelOpenConfirm(t *testing.T) {
	tests := []struct {
		name          string
		channelId     ChannelId
		proofAck      []byte
		proofHeight   uint64
		relayer       string
		wantChannelId ChannelId
		wantProofAck  []byte
		wantProofH    uint64
		wantRelayer   string
	}{
		{
			name:          "zero values",
			channelId:     0,
			proofAck:      nil,
			proofHeight:   0,
			relayer:       "",
			wantChannelId: 0,
			wantProofAck:  nil,
			wantProofH:    0,
			wantRelayer:   "",
		},
		{
			name:          "non-zero values",
			channelId:     10,
			proofAck:      []byte{0xaa},
			proofHeight:   200,
			relayer:       "relayer",
			wantChannelId: 10,
			wantProofAck:  []byte{0xaa},
			wantProofH:    200,
			wantRelayer:   "relayer",
		},
		{
			name:          "empty proof",
			channelId:     5,
			proofAck:      []byte{},
			proofHeight:   1,
			relayer:       "",
			wantChannelId: 5,
			wantProofAck:  []byte{},
			wantProofH:    1,
			wantRelayer:   "",
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			got := NewMsgChannelOpenConfirm(tc.channelId, tc.proofAck, tc.proofHeight, tc.relayer)

			if got.ChannelId != tc.wantChannelId {
				t.Errorf("ChannelId = %v, want %v", got.ChannelId, tc.wantChannelId)
			}
			assertBytes(t, "ProofAck", got.ProofAck, tc.wantProofAck)
			if got.ProofHeight != tc.wantProofH {
				t.Errorf("ProofHeight = %v, want %v", got.ProofHeight, tc.wantProofH)
			}
			if got.Relayer != tc.wantRelayer {
				t.Errorf("Relayer = %q, want %q", got.Relayer, tc.wantRelayer)
			}
		})
	}
}

func TestNewMsgChannelCloseInit(t *testing.T) {
	tests := []struct {
		name          string
		channelId     ChannelId
		relayer       string
		wantChannelId ChannelId
		wantRelayer   string
	}{
		{
			name:          "zero values",
			channelId:     0,
			relayer:       "",
			wantChannelId: 0,
			wantRelayer:   "",
		},
		{
			name:          "non-zero values",
			channelId:     1,
			relayer:       "relayer1",
			wantChannelId: 1,
			wantRelayer:   "relayer1",
		},
		{
			name:          "max channel id",
			channelId:     4294967295,
			relayer:       "gno:1abc",
			wantChannelId: 4294967295,
			wantRelayer:   "gno:1abc",
		},
		{
			name:          "empty relayer",
			channelId:     100,
			relayer:       "",
			wantChannelId: 100,
			wantRelayer:   "",
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			got := NewMsgChannelCloseInit(tc.channelId, tc.relayer)

			if got.ChannelId != tc.wantChannelId {
				t.Errorf("ChannelId = %v, want %v", got.ChannelId, tc.wantChannelId)
			}
			if got.Relayer != tc.wantRelayer {
				t.Errorf("Relayer = %q, want %q", got.Relayer, tc.wantRelayer)
			}
		})
	}
}

func TestNewMsgChannelCloseConfirm(t *testing.T) {
	tests := []struct {
		name          string
		channelId     ChannelId
		proofInit     []byte
		proofHeight   uint64
		relayer       string
		wantChannelId ChannelId
		wantProofInit []byte
		wantProofH    uint64
		wantRelayer   string
	}{
		{
			name:          "zero values",
			channelId:     0,
			proofInit:     nil,
			proofHeight:   0,
			relayer:       "",
			wantChannelId: 0,
			wantProofInit: nil,
			wantProofH:    0,
			wantRelayer:   "",
		},
		{
			name:          "non-zero values",
			channelId:     5,
			proofInit:     []byte{0xcc},
			proofHeight:   250,
			relayer:       "relayer",
			wantChannelId: 5,
			wantProofInit: []byte{0xcc},
			wantProofH:    250,
			wantRelayer:   "relayer",
		},
		{
			name:          "empty proof",
			channelId:     10,
			proofInit:     []byte{},
			proofHeight:   1,
			relayer:       "",
			wantChannelId: 10,
			wantProofInit: []byte{},
			wantProofH:    1,
			wantRelayer:   "",
		},
		{
			name:          "large proof height",
			channelId:     999,
			proofInit:     []byte{0xdd, 0xee, 0xff},
			proofHeight:   18446744073709551615,
			relayer:       "gno:1xyz",
			wantChannelId: 999,
			wantProofInit: []byte{0xdd, 0xee, 0xff},
			wantProofH:    18446744073709551615,
			wantRelayer:   "gno:1xyz",
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			got := NewMsgChannelCloseConfirm(tc.channelId, tc.proofInit, tc.proofHeight, tc.relayer)

			if got.ChannelId != tc.wantChannelId {
				t.Errorf("ChannelId = %v, want %v", got.ChannelId, tc.wantChannelId)
			}
			assertBytes(t, "ProofInit", got.ProofInit, tc.wantProofInit)
			if got.ProofHeight != tc.wantProofH {
				t.Errorf("ProofHeight = %v, want %v", got.ProofHeight, tc.wantProofH)
			}
			if got.Relayer != tc.wantRelayer {
				t.Errorf("Relayer = %q, want %q", got.Relayer, tc.wantRelayer)
			}
		})
	}
}

func assertBytes(t *testing.T, name string, got, want []byte) {
	t.Helper()
	if !bytes.Equal(got, want) {
		t.Fatalf("%s: mismatch, got %v want %v", name, got, want)
	}
}
