package types

import "testing"

func TestNewPacket(t *testing.T) {
	tests := []struct {
		name                 string
		sourceChannelId      ChannelId
		destinationChannelId ChannelId
		data                 []byte
		timeoutTimestamp     Timestamp
		want                 Packet
	}{
		{
			name:                 "packet with all zero values",
			sourceChannelId:      0,
			destinationChannelId: 0,
			data:                 nil,
			timeoutTimestamp:     0,
			want: Packet{
				SourceChannelId:      0,
				DestinationChannelId: 0,
				Data:                 nil,
				TimeoutHeight:        0,
				TimeoutTimestamp:     0,
			},
		},
		{
			name:                 "packet with minimal non-zero values",
			sourceChannelId:      1,
			destinationChannelId: 2,
			data:                 []byte{0x01},
			timeoutTimestamp:     1,
			want: Packet{
				SourceChannelId:      1,
				DestinationChannelId: 2,
				Data:                 []byte{0x01},
				TimeoutHeight:        0,
				TimeoutTimestamp:     1,
			},
		},
		{
			name:                 "packet with typical values",
			sourceChannelId:      42,
			destinationChannelId: 100,
			data:                 []byte{0xaa, 0xbb, 0xcc},
			timeoutTimestamp:     1234567890,
			want: Packet{
				SourceChannelId:      42,
				DestinationChannelId: 100,
				Data:                 []byte{0xaa, 0xbb, 0xcc},
				TimeoutHeight:        0,
				TimeoutTimestamp:     1234567890,
			},
		},
		{
			name:                 "packet with empty data slice",
			sourceChannelId:      5,
			destinationChannelId: 10,
			data:                 []byte{},
			timeoutTimestamp:     999,
			want: Packet{
				SourceChannelId:      5,
				DestinationChannelId: 10,
				Data:                 []byte{},
				TimeoutHeight:        0,
				TimeoutTimestamp:     999,
			},
		},
		{
			name:                 "packet with maximum channel IDs",
			sourceChannelId:      4294967295,
			destinationChannelId: 4294967295,
			data:                 []byte{0xff},
			timeoutTimestamp:     18446744073709551615,
			want: Packet{
				SourceChannelId:      4294967295,
				DestinationChannelId: 4294967295,
				Data:                 []byte{0xff},
				TimeoutHeight:        0,
				TimeoutTimestamp:     18446744073709551615,
			},
		},
		{
			name:                 "packet with large data payload",
			sourceChannelId:      1,
			destinationChannelId: 2,
			data:                 []byte{0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0a},
			timeoutTimestamp:     5000,
			want: Packet{
				SourceChannelId:      1,
				DestinationChannelId: 2,
				Data:                 []byte{0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0a},
				TimeoutHeight:        0,
				TimeoutTimestamp:     5000,
			},
		},
		{
			name:                 "packet with zero source channel ID",
			sourceChannelId:      0,
			destinationChannelId: 255,
			data:                 []byte{0x42},
			timeoutTimestamp:     100,
			want: Packet{
				SourceChannelId:      0,
				DestinationChannelId: 255,
				Data:                 []byte{0x42},
				TimeoutHeight:        0,
				TimeoutTimestamp:     100,
			},
		},
		{
			name:                 "packet with zero destination channel ID",
			sourceChannelId:      255,
			destinationChannelId: 0,
			data:                 []byte{0x42},
			timeoutTimestamp:     100,
			want: Packet{
				SourceChannelId:      255,
				DestinationChannelId: 0,
				Data:                 []byte{0x42},
				TimeoutHeight:        0,
				TimeoutTimestamp:     100,
			},
		},
		{
			name:                 "packet with zero timestamp",
			sourceChannelId:      100,
			destinationChannelId: 200,
			data:                 []byte{0xde, 0xad, 0xbe, 0xef},
			timeoutTimestamp:     0,
			want: Packet{
				SourceChannelId:      100,
				DestinationChannelId: 200,
				Data:                 []byte{0xde, 0xad, 0xbe, 0xef},
				TimeoutHeight:        0,
				TimeoutTimestamp:     0,
			},
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			got := NewPacket(tc.sourceChannelId, tc.destinationChannelId, tc.data, tc.timeoutTimestamp)

			if got.SourceChannelId != tc.want.SourceChannelId {
				t.Errorf("SourceChannelId = %v, want %v", got.SourceChannelId, tc.want.SourceChannelId)
			}
			if got.DestinationChannelId != tc.want.DestinationChannelId {
				t.Errorf("DestinationChannelId = %v, want %v", got.DestinationChannelId, tc.want.DestinationChannelId)
			}
			if got.TimeoutHeight != tc.want.TimeoutHeight {
				t.Errorf("TimeoutHeight = %v, want %v", got.TimeoutHeight, tc.want.TimeoutHeight)
			}
			if got.TimeoutTimestamp != tc.want.TimeoutTimestamp {
				t.Errorf("TimeoutTimestamp = %v, want %v", got.TimeoutTimestamp, tc.want.TimeoutTimestamp)
			}

			// Compare byte slices
			if len(got.Data) != len(tc.want.Data) {
				t.Fatalf("Data length = %d, want %d", len(got.Data), len(tc.want.Data))
			}
			for i := range got.Data {
				if got.Data[i] != tc.want.Data[i] {
					t.Errorf("Data[%d] = %02x, want %02x", i, got.Data[i], tc.want.Data[i])
				}
			}
		})
	}
}

func TestPacketEncodeABI(t *testing.T) {
	tests := []struct {
		name   string
		packet Packet
		want   string
	}{
		{
			name: "all zeros",
			packet: Packet{
				SourceChannelId:  0,
				DestinationChannelId: 0,
				Data: nil,
				TimeoutHeight: 0,
				TimeoutTimestamp: 0,
			},
			want: "0000000000000000000000000000000000000000000000000000000000000000" +
				"0000000000000000000000000000000000000000000000000000000000000000" +
				"00000000000000000000000000000000000000000000000000000000000000a0" +
				"0000000000000000000000000000000000000000000000000000000000000000" +
				"0000000000000000000000000000000000000000000000000000000000000000" +
				"0000000000000000000000000000000000000000000000000000000000000000",
		},
		{
			name: "basic values",
			packet: Packet{
				SourceChannelId:  1,
				DestinationChannelId: 2,
				Data: []byte{0xab, 0xcd},
				TimeoutHeight: 0,
				TimeoutTimestamp: 3,
			},
			want: "0000000000000000000000000000000000000000000000000000000000000001" +
				"0000000000000000000000000000000000000000000000000000000000000002" +
				"00000000000000000000000000000000000000000000000000000000000000a0" +
				"0000000000000000000000000000000000000000000000000000000000000000" +
				"0000000000000000000000000000000000000000000000000000000000000003" +
				"0000000000000000000000000000000000000000000000000000000000000002" +
				"abcd000000000000000000000000000000000000000000000000000000000000",
		},
		{
			name: "empty data slice",
			packet: Packet{
				SourceChannelId:  42,
				DestinationChannelId: 100,
				Data: []byte{},
				TimeoutHeight: 0,
				TimeoutTimestamp: 12345,
			},
			want: "000000000000000000000000000000000000000000000000000000000000002a" +
				"0000000000000000000000000000000000000000000000000000000000000064" +
				"00000000000000000000000000000000000000000000000000000000000000a0" +
				"0000000000000000000000000000000000000000000000000000000000000000" +
				"0000000000000000000000000000000000000000000000000000000000003039" +
				"0000000000000000000000000000000000000000000000000000000000000000",
		},
		{
			name: "max uint32 channel IDs",
			packet: Packet{
				SourceChannelId:  0xFFFFFFFF,
				DestinationChannelId: 0xFFFFFFFE,
				Data: []byte{0xff},
				TimeoutHeight: 0,
				TimeoutTimestamp: 0,
			},
			want: "00000000000000000000000000000000000000000000000000000000ffffffff" +
				"00000000000000000000000000000000000000000000000000000000fffffffe" +
				"00000000000000000000000000000000000000000000000000000000000000a0" +
				"0000000000000000000000000000000000000000000000000000000000000000" +
				"0000000000000000000000000000000000000000000000000000000000000000" +
				"0000000000000000000000000000000000000000000000000000000000000001" +
				"ff00000000000000000000000000000000000000000000000000000000000000",
		},
		{
			name: "max uint64 timestamp",
			packet: Packet{
				SourceChannelId:  0,
				DestinationChannelId: 0,
				Data: nil,
				TimeoutHeight: 0,
				TimeoutTimestamp: 0xFFFFFFFFFFFFFFFF,
			},
			want: "0000000000000000000000000000000000000000000000000000000000000000" +
				"0000000000000000000000000000000000000000000000000000000000000000" +
				"00000000000000000000000000000000000000000000000000000000000000a0" +
				"0000000000000000000000000000000000000000000000000000000000000000" +
				"000000000000000000000000000000000000000000000000ffffffffffffffff" +
				"0000000000000000000000000000000000000000000000000000000000000000",
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			got, err := tc.packet.EncodeABI()
			if err != nil {
				t.Fatalf("EncodeABI: %v", err)
			}
			assertHex(t, tc.name, got, tc.want)
		})
	}
}

func TestMustBeZeroString(t *testing.T) {
	var mz MustBeZero
	if got := mz.String(); got != "0" {
		t.Errorf("String() = %q, want %q", got, "0")
	}

	// All values return "0" regardless of underlying value
	mz2 := MustBeZero(999)
	if got := mz2.String(); got != "0" {
		t.Errorf("String() = %q, want %q", got, "0")
	}
}

func TestPacketStatusValues(t *testing.T) {
	tests := []struct {
		name          string
		status        PacketStatus
		expectedValue uint8
	}{
		{
			name:          "PacketStatusUnknown value",
			status:        PacketStatusUnknown,
			expectedValue: 0,
		},
		{
			name:          "PacketStatusSuccess value",
			status:        PacketStatusSuccess,
			expectedValue: 1,
		},
		{
			name:          "PacketStatusFailure value",
			status:        PacketStatusFailure,
			expectedValue: 2,
		},
		{
			name:          "PacketStatusAsync value",
			status:        PacketStatusAsync,
			expectedValue: 3,
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			if uint8(tc.status) != tc.expectedValue {
				t.Errorf("PacketStatus value = %d, want %d", uint8(tc.status), tc.expectedValue)
			}
		})
	}
}

func TestNewRecvPacketResult(t *testing.T) {
	tests := []struct {
		name            string
		status          PacketStatus
		acknowledgement []byte
		wantStatus      PacketStatus
		wantAck         []byte
	}{
		{
			name:            "result with unknown status and nil ack",
			status:          PacketStatusUnknown,
			acknowledgement: nil,
			wantStatus:      PacketStatusUnknown,
			wantAck:         nil,
		},
		{
			name:            "result with success status and ack bytes",
			status:          PacketStatusSuccess,
			acknowledgement: []byte{0x01, 0x02, 0x03},
			wantStatus:      PacketStatusSuccess,
			wantAck:         []byte{0x01, 0x02, 0x03},
		},
		{
			name:            "result with failure status and empty ack",
			status:          PacketStatusFailure,
			acknowledgement: []byte{},
			wantStatus:      PacketStatusFailure,
			wantAck:         []byte{},
		},
		{
			name:            "result with async status and nil ack",
			status:          PacketStatusAsync,
			acknowledgement: nil,
			wantStatus:      PacketStatusAsync,
			wantAck:         nil,
		},
		{
			name:            "result with success status and large ack",
			status:          PacketStatusSuccess,
			acknowledgement: []byte{0xaa, 0xbb, 0xcc, 0xdd, 0xee, 0xff},
			wantStatus:      PacketStatusSuccess,
			wantAck:         []byte{0xaa, 0xbb, 0xcc, 0xdd, 0xee, 0xff},
		},
		{
			name:            "result with unknown status and ack bytes",
			status:          PacketStatusUnknown,
			acknowledgement: []byte{0xff},
			wantStatus:      PacketStatusUnknown,
			wantAck:         []byte{0xff},
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			got := NewRecvPacketResult(tc.status, tc.acknowledgement)

			if got.Status != tc.wantStatus {
				t.Errorf("Status = %v, want %v", got.Status, tc.wantStatus)
			}

			// Compare acknowledgement byte slices
			if len(got.Acknowledgement) != len(tc.wantAck) {
				t.Fatalf("Acknowledgement length = %d, want %d", len(got.Acknowledgement), len(tc.wantAck))
			}
			for i := range got.Acknowledgement {
				if got.Acknowledgement[i] != tc.wantAck[i] {
					t.Errorf("Acknowledgement[%d] = %02x, want %02x", i, got.Acknowledgement[i], tc.wantAck[i])
				}
			}
		})
	}
}
