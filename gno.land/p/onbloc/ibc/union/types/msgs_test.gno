package types

import "testing"

func TestNewMsgPacketRecv(t *testing.T) {
	tests := []struct {
		name         string
		packets      []Packet
		relayerMsgs  [][]byte
		proof        []byte
		proofHeight  uint64
		wantPackets  int
		wantRelayer  int
		wantProofLen int
		wantHeight   uint64
	}{
		{
			name:         "empty slices",
			packets:      []Packet{},
			relayerMsgs:  [][]byte{},
			proof:        []byte{},
			proofHeight:  0,
			wantPackets:  0,
			wantRelayer:  0,
			wantProofLen: 0,
			wantHeight:   0,
		},
		{
			name: "single element",
			packets: []Packet{
				{SourceChannelId: 1, DestinationChannelId: 2, Data: []byte{0xab}, TimeoutHeight: 0, TimeoutTimestamp: 100},
			},
			relayerMsgs:  [][]byte{{0x01}},
			proof:        []byte{0xde, 0xad},
			proofHeight:  50,
			wantPackets:  1,
			wantRelayer:  1,
			wantProofLen: 2,
			wantHeight:   50,
		},
		{
			name: "multiple elements",
			packets: []Packet{
				{SourceChannelId: 1, DestinationChannelId: 2, Data: []byte{0xab}, TimeoutHeight: 0, TimeoutTimestamp: 100},
				{SourceChannelId: 3, DestinationChannelId: 4, Data: []byte{0xcd}, TimeoutHeight: 0, TimeoutTimestamp: 200},
			},
			relayerMsgs:  [][]byte{{0x01}, {0x02}},
			proof:        []byte{0xde, 0xad, 0xbe, 0xef},
			proofHeight:  100,
			wantPackets:  2,
			wantRelayer:  2,
			wantProofLen: 4,
			wantHeight:   100,
		},
		{
			name:         "nil slices",
			packets:      nil,
			relayerMsgs:  nil,
			proof:        nil,
			proofHeight:  0,
			wantPackets:  0,
			wantRelayer:  0,
			wantProofLen: 0,
			wantHeight:   0,
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			got := NewMsgPacketRecv(tc.packets, tc.relayerMsgs, tc.proof, tc.proofHeight)

			if len(got.Packets) != tc.wantPackets {
				t.Errorf("Packets length: got %d want %d", len(got.Packets), tc.wantPackets)
			}
			if len(got.RelayerMsgs) != tc.wantRelayer {
				t.Errorf("RelayerMsgs length: got %d want %d", len(got.RelayerMsgs), tc.wantRelayer)
			}
			if len(got.Proof) != tc.wantProofLen {
				t.Errorf("Proof length: got %d want %d", len(got.Proof), tc.wantProofLen)
			}
			if got.ProofHeight != tc.wantHeight {
				t.Errorf("ProofHeight: got %d want %d", got.ProofHeight, tc.wantHeight)
			}
		})
	}
}

func TestNewMsgPacketAcknowledgement(t *testing.T) {
	tests := []struct {
		name                 string
		packets              []Packet
		acknowledgements     [][]byte
		proof                []byte
		proofHeight          uint64
		wantPackets          int
		wantAcknowledgements int
		wantProofLen         int
		wantHeight           uint64
	}{
		{
			name:                 "empty slices",
			packets:              []Packet{},
			acknowledgements:     [][]byte{},
			proof:                []byte{},
			proofHeight:          0,
			wantPackets:          0,
			wantAcknowledgements: 0,
			wantProofLen:         0,
			wantHeight:           0,
		},
		{
			name: "single element",
			packets: []Packet{
				{SourceChannelId: 1, DestinationChannelId: 2, Data: []byte{0xab}, TimeoutHeight: 0, TimeoutTimestamp: 100},
			},
			acknowledgements:     [][]byte{{0xaa}},
			proof:                []byte{0xde, 0xad},
			proofHeight:          50,
			wantPackets:          1,
			wantAcknowledgements: 1,
			wantProofLen:         2,
			wantHeight:           50,
		},
		{
			name: "multiple elements",
			packets: []Packet{
				{SourceChannelId: 1, DestinationChannelId: 2, Data: []byte{0xab}, TimeoutHeight: 0, TimeoutTimestamp: 100},
				{SourceChannelId: 3, DestinationChannelId: 4, Data: []byte{0xcd}, TimeoutHeight: 0, TimeoutTimestamp: 200},
			},
			acknowledgements:     [][]byte{{0xaa}, {0xbb}},
			proof:                []byte{0xde, 0xad, 0xbe, 0xef},
			proofHeight:          100,
			wantPackets:          2,
			wantAcknowledgements: 2,
			wantProofLen:         4,
			wantHeight:           100,
		},
		{
			name:                 "nil slices",
			packets:              nil,
			acknowledgements:     nil,
			proof:                nil,
			proofHeight:          0,
			wantPackets:          0,
			wantAcknowledgements: 0,
			wantProofLen:         0,
			wantHeight:           0,
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			got := NewMsgPacketAcknowledgement(tc.packets, tc.acknowledgements, tc.proof, tc.proofHeight)

			if len(got.Packets) != tc.wantPackets {
				t.Errorf("Packets length: got %d want %d", len(got.Packets), tc.wantPackets)
			}
			if len(got.Acknowledgements) != tc.wantAcknowledgements {
				t.Errorf("Acknowledgements length: got %d want %d", len(got.Acknowledgements), tc.wantAcknowledgements)
			}
			if len(got.Proof) != tc.wantProofLen {
				t.Errorf("Proof length: got %d want %d", len(got.Proof), tc.wantProofLen)
			}
			if got.ProofHeight != tc.wantHeight {
				t.Errorf("ProofHeight: got %d want %d", got.ProofHeight, tc.wantHeight)
			}
		})
	}
}

func TestNewMsgPacketTimeout(t *testing.T) {
	tests := []struct {
		name        string
		packet      Packet
		proof       []byte
		proofHeight uint64
		wantData    []byte
		wantProof   []byte
		wantHeight  uint64
	}{
		{
			name: "basic packet",
			packet: Packet{
				SourceChannelId:      1,
				DestinationChannelId: 2,
				Data:                 []byte{0xab, 0xcd},
				TimeoutHeight:        0,
				TimeoutTimestamp:     100,
			},
			proof:       []byte{0xde},
			proofHeight: 50,
			wantData:    []byte{0xab, 0xcd},
			wantProof:   []byte{0xde},
			wantHeight:  50,
		},
		{
			name: "empty data packet",
			packet: Packet{
				SourceChannelId:      0,
				DestinationChannelId: 1,
				Data:                 []byte{},
				TimeoutHeight:        0,
				TimeoutTimestamp:     0,
			},
			proof:       []byte{},
			proofHeight: 0,
			wantData:    []byte{},
			wantProof:   []byte{},
			wantHeight:  0,
		},
		{
			name: "nil proof",
			packet: Packet{
				SourceChannelId:      5,
				DestinationChannelId: 10,
				Data:                 []byte{0x01, 0x02, 0x03},
				TimeoutHeight:        0,
				TimeoutTimestamp:     999,
			},
			proof:       nil,
			proofHeight: 100,
			wantData:    []byte{0x01, 0x02, 0x03},
			wantProof:   nil,
			wantHeight:  100,
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			got := NewMsgPacketTimeout(tc.packet, tc.proof, tc.proofHeight)

			if string(got.Packet.Data) != string(tc.wantData) {
				t.Errorf("Packet.Data: got %x want %x", got.Packet.Data, tc.wantData)
			}
			if string(got.Proof) != string(tc.wantProof) {
				t.Errorf("Proof: got %x want %x", got.Proof, tc.wantProof)
			}
			if got.ProofHeight != tc.wantHeight {
				t.Errorf("ProofHeight: got %d want %d", got.ProofHeight, tc.wantHeight)
			}
		})
	}
}

func TestNewMsgCommitMembershipProof(t *testing.T) {
	tests := []struct {
		name        string
		clientId    ClientId
		proofHeight uint64
		proof       []byte
		path        []byte
		value       []byte
		wantClient  ClientId
		wantHeight  uint64
		wantProof   int
		wantPath    int
		wantValue   int
	}{
		{
			name:        "all zeros",
			clientId:    0,
			proofHeight: 0,
			proof:       []byte{},
			path:        []byte{},
			value:       []byte{},
			wantClient:  0,
			wantHeight:  0,
			wantProof:   0,
			wantPath:    0,
			wantValue:   0,
		},
		{
			name:        "with values",
			clientId:    5,
			proofHeight: 100,
			proof:       []byte{0x01},
			path:        []byte{0x02, 0x03},
			value:       []byte{0x04, 0x05, 0x06},
			wantClient:  5,
			wantHeight:  100,
			wantProof:   1,
			wantPath:    2,
			wantValue:   3,
		},
		{
			name:        "nil slices",
			clientId:    10,
			proofHeight: 200,
			proof:       nil,
			path:        nil,
			value:       nil,
			wantClient:  10,
			wantHeight:  200,
			wantProof:   0,
			wantPath:    0,
			wantValue:   0,
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			got := NewMsgCommitMembershipProof(tc.clientId, tc.proofHeight, tc.proof, tc.path, tc.value)

			if got.ClientId != tc.wantClient {
				t.Errorf("ClientId: got %d want %d", got.ClientId, tc.wantClient)
			}
			if got.ProofHeight != tc.wantHeight {
				t.Errorf("ProofHeight: got %d want %d", got.ProofHeight, tc.wantHeight)
			}
			if len(got.Proof) != tc.wantProof {
				t.Errorf("Proof length: got %d want %d", len(got.Proof), tc.wantProof)
			}
			if len(got.Path) != tc.wantPath {
				t.Errorf("Path length: got %d want %d", len(got.Path), tc.wantPath)
			}
			if len(got.Value) != tc.wantValue {
				t.Errorf("Value length: got %d want %d", len(got.Value), tc.wantValue)
			}
		})
	}
}

func TestNewMsgCommitNonMembershipProof(t *testing.T) {
	tests := []struct {
		name        string
		clientId    ClientId
		proofHeight uint64
		proof       []byte
		path        []byte
		wantClient  ClientId
		wantHeight  uint64
		wantProof   int
		wantPath    int
	}{
		{
			name:        "all zeros",
			clientId:    0,
			proofHeight: 0,
			proof:       []byte{},
			path:        []byte{},
			wantClient:  0,
			wantHeight:  0,
			wantProof:   0,
			wantPath:    0,
		},
		{
			name:        "with values",
			clientId:    7,
			proofHeight: 150,
			proof:       []byte{0xaa, 0xbb},
			path:        []byte{0xcc, 0xdd, 0xee},
			wantClient:  7,
			wantHeight:  150,
			wantProof:   2,
			wantPath:    3,
		},
		{
			name:        "nil slices",
			clientId:    20,
			proofHeight: 300,
			proof:       nil,
			path:        nil,
			wantClient:  20,
			wantHeight:  300,
			wantProof:   0,
			wantPath:    0,
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			got := NewMsgCommitNonMembershipProof(tc.clientId, tc.proofHeight, tc.proof, tc.path)

			if got.ClientId != tc.wantClient {
				t.Errorf("ClientId: got %d want %d", got.ClientId, tc.wantClient)
			}
			if got.ProofHeight != tc.wantHeight {
				t.Errorf("ProofHeight: got %d want %d", got.ProofHeight, tc.wantHeight)
			}
			if len(got.Proof) != tc.wantProof {
				t.Errorf("Proof length: got %d want %d", len(got.Proof), tc.wantProof)
			}
			if len(got.Path) != tc.wantPath {
				t.Errorf("Path length: got %d want %d", len(got.Path), tc.wantPath)
			}
		})
	}
}

func TestNewMsgIntentPacketRecv(t *testing.T) {
	tests := []struct {
		name                string
		packets             []Packet
		marketMakerMessages [][]byte
		wantPackets         int
		wantMessages        int
	}{
		{
			name:                "empty slices",
			packets:             []Packet{},
			marketMakerMessages: [][]byte{},
			wantPackets:         0,
			wantMessages:        0,
		},
		{
			name: "single element",
			packets: []Packet{
				{SourceChannelId: 1, DestinationChannelId: 2, Data: []byte{0xab}, TimeoutHeight: 0, TimeoutTimestamp: 100},
			},
			marketMakerMessages: [][]byte{{0x01}},
			wantPackets:         1,
			wantMessages:        1,
		},
		{
			name: "multiple elements",
			packets: []Packet{
				{SourceChannelId: 1, DestinationChannelId: 2, Data: []byte{0xab}, TimeoutHeight: 0, TimeoutTimestamp: 100},
				{SourceChannelId: 3, DestinationChannelId: 4, Data: []byte{0xcd}, TimeoutHeight: 0, TimeoutTimestamp: 200},
			},
			marketMakerMessages: [][]byte{{0x01}, {0x02}, {0x03}},
			wantPackets:         2,
			wantMessages:        3,
		},
		{
			name:                "nil slices",
			packets:             nil,
			marketMakerMessages: nil,
			wantPackets:         0,
			wantMessages:        0,
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			got := NewMsgIntentPacketRecv(tc.packets, tc.marketMakerMessages)

			if len(got.Packets) != tc.wantPackets {
				t.Errorf("Packets length: got %d want %d", len(got.Packets), tc.wantPackets)
			}
			if len(got.MarketMakerMessages) != tc.wantMessages {
				t.Errorf("MarketMakerMessages length: got %d want %d", len(got.MarketMakerMessages), tc.wantMessages)
			}
		})
	}
}

func TestNewMsgBatchSend(t *testing.T) {
	tests := []struct {
		name        string
		packets     []Packet
		wantPackets int
	}{
		{
			name:        "empty slice",
			packets:     []Packet{},
			wantPackets: 0,
		},
		{
			name: "single element",
			packets: []Packet{
				{SourceChannelId: 1, DestinationChannelId: 2, Data: []byte{0xab}, TimeoutHeight: 0, TimeoutTimestamp: 100},
			},
			wantPackets: 1,
		},
		{
			name: "multiple elements",
			packets: []Packet{
				{SourceChannelId: 1, DestinationChannelId: 2, Data: []byte{0xab}, TimeoutHeight: 0, TimeoutTimestamp: 100},
				{SourceChannelId: 3, DestinationChannelId: 4, Data: []byte{0xcd}, TimeoutHeight: 0, TimeoutTimestamp: 200},
				{SourceChannelId: 5, DestinationChannelId: 6, Data: []byte{0xef}, TimeoutHeight: 0, TimeoutTimestamp: 300},
			},
			wantPackets: 3,
		},
		{
			name:        "nil slice",
			packets:     nil,
			wantPackets: 0,
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			got := NewMsgBatchSend(tc.packets)

			if len(got.Packets) != tc.wantPackets {
				t.Errorf("Packets length: got %d want %d", len(got.Packets), tc.wantPackets)
			}
		})
	}
}

func TestNewMsgBatchAcks(t *testing.T) {
	tests := []struct {
		name        string
		packets     []Packet
		acks        [][]byte
		wantPackets int
		wantAcks    int
	}{
		{
			name:        "empty slices",
			packets:     []Packet{},
			acks:        [][]byte{},
			wantPackets: 0,
			wantAcks:    0,
		},
		{
			name: "single element",
			packets: []Packet{
				{SourceChannelId: 1, DestinationChannelId: 2, Data: []byte{0xab}, TimeoutHeight: 0, TimeoutTimestamp: 100},
			},
			acks:        [][]byte{{0xaa}},
			wantPackets: 1,
			wantAcks:    1,
		},
		{
			name: "multiple elements",
			packets: []Packet{
				{SourceChannelId: 1, DestinationChannelId: 2, Data: []byte{0xab}, TimeoutHeight: 0, TimeoutTimestamp: 100},
				{SourceChannelId: 3, DestinationChannelId: 4, Data: []byte{0xcd}, TimeoutHeight: 0, TimeoutTimestamp: 200},
			},
			acks:        [][]byte{{0xaa}, {0xbb}, {0xcc}},
			wantPackets: 2,
			wantAcks:    3,
		},
		{
			name:        "nil slices",
			packets:     nil,
			acks:        nil,
			wantPackets: 0,
			wantAcks:    0,
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			got := NewMsgBatchAcks(tc.packets, tc.acks)

			if len(got.Packets) != tc.wantPackets {
				t.Errorf("Packets length: got %d want %d", len(got.Packets), tc.wantPackets)
			}
			if len(got.Acks) != tc.wantAcks {
				t.Errorf("Acks length: got %d want %d", len(got.Acks), tc.wantAcks)
			}
		})
	}
}

func TestNewMsgWriteAcknowledgement(t *testing.T) {
	tests := []struct {
		name            string
		packet          Packet
		acknowledgement []byte
		wantData        []byte
		wantAck         []byte
	}{
		{
			name: "basic packet and ack",
			packet: Packet{
				SourceChannelId:      1,
				DestinationChannelId: 2,
				Data:                 []byte{0xab, 0xcd},
				TimeoutHeight:        0,
				TimeoutTimestamp:     100,
			},
			acknowledgement: []byte{0x01},
			wantData:        []byte{0xab, 0xcd},
			wantAck:         []byte{0x01},
		},
		{
			name: "empty data and ack",
			packet: Packet{
				SourceChannelId:      0,
				DestinationChannelId: 1,
				Data:                 []byte{},
				TimeoutHeight:        0,
				TimeoutTimestamp:     0,
			},
			acknowledgement: []byte{},
			wantData:        []byte{},
			wantAck:         []byte{},
		},
		{
			name: "nil ack",
			packet: Packet{
				SourceChannelId:      5,
				DestinationChannelId: 10,
				Data:                 []byte{0x01, 0x02, 0x03},
				TimeoutHeight:        0,
				TimeoutTimestamp:     999,
			},
			acknowledgement: nil,
			wantData:        []byte{0x01, 0x02, 0x03},
			wantAck:         nil,
		},
		{
			name: "large ack",
			packet: Packet{
				SourceChannelId:      3,
				DestinationChannelId: 7,
				Data:                 []byte{0xff},
				TimeoutHeight:        0,
				TimeoutTimestamp:     500,
			},
			acknowledgement: []byte{0xaa, 0xbb, 0xcc, 0xdd, 0xee},
			wantData:        []byte{0xff},
			wantAck:         []byte{0xaa, 0xbb, 0xcc, 0xdd, 0xee},
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			got := NewMsgWriteAcknowledgement(tc.packet, tc.acknowledgement)

			if string(got.Packet.Data) != string(tc.wantData) {
				t.Errorf("Packet.Data: got %x want %x", got.Packet.Data, tc.wantData)
			}
			if string(got.Acknowledgement) != string(tc.wantAck) {
				t.Errorf("Acknowledgement: got %x want %x", got.Acknowledgement, tc.wantAck)
			}
		})
	}
}
