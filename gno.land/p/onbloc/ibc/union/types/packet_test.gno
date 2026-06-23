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
		name    string
		packet  Packet
		want    string
		wantErr bool
	}{
		{
			name: "valid packet with all zeros",
			packet: Packet{
				SourceChannelId:      0,
				DestinationChannelId: 0,
				Data:                 nil,
				TimeoutHeight:        0,
				TimeoutTimestamp:     0,
			},
			want: "0000000000000000000000000000000000000000000000000000000000000000" +
				"0000000000000000000000000000000000000000000000000000000000000000" +
				"00000000000000000000000000000000000000000000000000000000000000a0" +
				"0000000000000000000000000000000000000000000000000000000000000000" +
				"0000000000000000000000000000000000000000000000000000000000000000" +
				"0000000000000000000000000000000000000000000000000000000000000000",
			wantErr: false,
		},
		{
			name: "valid packet with basic values",
			packet: Packet{
				SourceChannelId:      1,
				DestinationChannelId: 2,
				Data:                 []byte{0xab, 0xcd},
				TimeoutHeight:        0,
				TimeoutTimestamp:     3,
			},
			want: "0000000000000000000000000000000000000000000000000000000000000001" +
				"0000000000000000000000000000000000000000000000000000000000000002" +
				"00000000000000000000000000000000000000000000000000000000000000a0" +
				"0000000000000000000000000000000000000000000000000000000000000000" +
				"0000000000000000000000000000000000000000000000000000000000000003" +
				"0000000000000000000000000000000000000000000000000000000000000002" +
				"abcd000000000000000000000000000000000000000000000000000000000000",
			wantErr: false,
		},
		{
			name: "valid packet with empty data",
			packet: Packet{
				SourceChannelId:      42,
				DestinationChannelId: 100,
				Data:                 []byte{},
				TimeoutHeight:        0,
				TimeoutTimestamp:     12345,
			},
			want: "000000000000000000000000000000000000000000000000000000000000002a" +
				"0000000000000000000000000000000000000000000000000000000000000064" +
				"00000000000000000000000000000000000000000000000000000000000000a0" +
				"0000000000000000000000000000000000000000000000000000000000000000" +
				"0000000000000000000000000000000000000000000000000000000000003039" +
				"0000000000000000000000000000000000000000000000000000000000000000",
			wantErr: false,
		},
		{
			name: "valid packet with larger data payload",
			packet: Packet{
				SourceChannelId:      5,
				DestinationChannelId: 10,
				Data:                 []byte{0x01, 0x02, 0x03, 0x04, 0x05},
				TimeoutHeight:        0,
				TimeoutTimestamp:     9999,
			},
			want: "0000000000000000000000000000000000000000000000000000000000000005" +
				"000000000000000000000000000000000000000000000000000000000000000a" +
				"00000000000000000000000000000000000000000000000000000000000000a0" +
				"0000000000000000000000000000000000000000000000000000000000000000" +
				"000000000000000000000000000000000000000000000000000000000000270f" +
				"0000000000000000000000000000000000000000000000000000000000000005" +
				"0102030405000000000000000000000000000000000000000000000000000000",
			wantErr: false,
		},
		{
			name: "valid packet with maximum uint32 channel IDs",
			packet: Packet{
				SourceChannelId:      4294967295,
				DestinationChannelId: 4294967294,
				Data:                 []byte{0xff},
				TimeoutHeight:        0,
				TimeoutTimestamp:     0,
			},
			want: "00000000000000000000000000000000000000000000000000000000ffffffff" +
				"00000000000000000000000000000000000000000000000000000000fffffffe" +
				"00000000000000000000000000000000000000000000000000000000000000a0" +
				"0000000000000000000000000000000000000000000000000000000000000000" +
				"0000000000000000000000000000000000000000000000000000000000000000" +
				"0000000000000000000000000000000000000000000000000000000000000001" +
				"ff00000000000000000000000000000000000000000000000000000000000000",
			wantErr: false,
		},
		{
			name: "valid packet with maximum uint64 timestamp",
			packet: Packet{
				SourceChannelId:      0,
				DestinationChannelId: 0,
				Data:                 nil,
				TimeoutHeight:        0,
				TimeoutTimestamp:     18446744073709551615,
			},
			want: "0000000000000000000000000000000000000000000000000000000000000000" +
				"0000000000000000000000000000000000000000000000000000000000000000" +
				"00000000000000000000000000000000000000000000000000000000000000a0" +
				"0000000000000000000000000000000000000000000000000000000000000000" +
				"000000000000000000000000000000000000000000000000ffffffffffffffff" +
				"0000000000000000000000000000000000000000000000000000000000000000",
			wantErr: false,
		},
		{
			name: "verify timeout height is always zero",
			packet: Packet{
				SourceChannelId:      1,
				DestinationChannelId: 1,
				Data:                 []byte{0x01},
				TimeoutHeight:        0,
				TimeoutTimestamp:     1,
			},
			want: "0000000000000000000000000000000000000000000000000000000000000001" +
				"0000000000000000000000000000000000000000000000000000000000000001" +
				"00000000000000000000000000000000000000000000000000000000000000a0" +
				"0000000000000000000000000000000000000000000000000000000000000000" +
				"0000000000000000000000000000000000000000000000000000000000000001" +
				"0000000000000000000000000000000000000000000000000000000000000001" +
				"0100000000000000000000000000000000000000000000000000000000000000",
			wantErr: false,
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			got, err := tc.packet.EncodeABI()

			if tc.wantErr {
				if err == nil {
					t.Fatal("expected error, got nil")
				}
				return
			}

			if err != nil {
				t.Fatalf("unexpected error: %v", err)
			}

			assertHex(t, tc.name, got, tc.want)
		})
	}
}

func TestPacketEncodeABI_FieldEncoding(t *testing.T) {
	tests := []struct {
		name                    string
		sourceChannelId         ChannelId
		destinationChannelId    ChannelId
		data                    []byte
		timeoutTimestamp        Timestamp
		wantSourceChannelHex    string
		wantDestChannelHex      string
		wantDataOffsetHex       string
		wantTimeoutHeightHex    string
		wantTimeoutTimestampHex string
		wantDataLenHex          string
		wantDataPayloadHex      string
	}{
		{
			name:                    "verify source channel ID field encoding",
			sourceChannelId:         255,
			destinationChannelId:    0,
			data:                    nil,
			timeoutTimestamp:        0,
			wantSourceChannelHex:    "00000000000000000000000000000000000000000000000000000000000000ff",
			wantDestChannelHex:      "0000000000000000000000000000000000000000000000000000000000000000",
			wantDataOffsetHex:       "00000000000000000000000000000000000000000000000000000000000000a0",
			wantTimeoutHeightHex:    "0000000000000000000000000000000000000000000000000000000000000000",
			wantTimeoutTimestampHex: "0000000000000000000000000000000000000000000000000000000000000000",
			wantDataLenHex:          "0000000000000000000000000000000000000000000000000000000000000000",
			wantDataPayloadHex:      "0000000000000000000000000000000000000000000000000000000000000000",
		},
		{
			name:                    "verify destination channel ID field encoding",
			sourceChannelId:         0,
			destinationChannelId:    65535,
			data:                    nil,
			timeoutTimestamp:        0,
			wantSourceChannelHex:    "0000000000000000000000000000000000000000000000000000000000000000",
			wantDestChannelHex:      "000000000000000000000000000000000000000000000000000000000000ffff",
			wantDataOffsetHex:       "00000000000000000000000000000000000000000000000000000000000000a0",
			wantTimeoutHeightHex:    "0000000000000000000000000000000000000000000000000000000000000000",
			wantTimeoutTimestampHex: "0000000000000000000000000000000000000000000000000000000000000000",
			wantDataLenHex:          "0000000000000000000000000000000000000000000000000000000000000000",
			wantDataPayloadHex:      "0000000000000000000000000000000000000000000000000000000000000000",
		},
		{
			name:                    "verify data field with single byte",
			sourceChannelId:         0,
			destinationChannelId:    0,
			data:                    []byte{0xde},
			timeoutTimestamp:        0,
			wantSourceChannelHex:    "0000000000000000000000000000000000000000000000000000000000000000",
			wantDestChannelHex:      "0000000000000000000000000000000000000000000000000000000000000000",
			wantDataOffsetHex:       "00000000000000000000000000000000000000000000000000000000000000a0",
			wantTimeoutHeightHex:    "0000000000000000000000000000000000000000000000000000000000000000",
			wantTimeoutTimestampHex: "0000000000000000000000000000000000000000000000000000000000000000",
			wantDataLenHex:          "0000000000000000000000000000000000000000000000000000000000000001",
			wantDataPayloadHex:      "de00000000000000000000000000000000000000000000000000000000000000",
		},
		{
			name:                    "verify data field with multiple bytes",
			sourceChannelId:         0,
			destinationChannelId:    0,
			data:                    []byte{0x01, 0x02, 0x03},
			timeoutTimestamp:        0,
			wantSourceChannelHex:    "0000000000000000000000000000000000000000000000000000000000000000",
			wantDestChannelHex:      "0000000000000000000000000000000000000000000000000000000000000000",
			wantDataOffsetHex:       "00000000000000000000000000000000000000000000000000000000000000a0",
			wantTimeoutHeightHex:    "0000000000000000000000000000000000000000000000000000000000000000",
			wantTimeoutTimestampHex: "0000000000000000000000000000000000000000000000000000000000000000",
			wantDataLenHex:          "0000000000000000000000000000000000000000000000000000000000000003",
			wantDataPayloadHex:      "0102030000000000000000000000000000000000000000000000000000000000",
		},
		{
			name:                    "verify timeout height is always zero",
			sourceChannelId:         0,
			destinationChannelId:    0,
			data:                    nil,
			timeoutTimestamp:        0,
			wantSourceChannelHex:    "0000000000000000000000000000000000000000000000000000000000000000",
			wantDestChannelHex:      "0000000000000000000000000000000000000000000000000000000000000000",
			wantDataOffsetHex:       "00000000000000000000000000000000000000000000000000000000000000a0",
			wantTimeoutHeightHex:    "0000000000000000000000000000000000000000000000000000000000000000",
			wantTimeoutTimestampHex: "0000000000000000000000000000000000000000000000000000000000000000",
			wantDataLenHex:          "0000000000000000000000000000000000000000000000000000000000000000",
			wantDataPayloadHex:      "0000000000000000000000000000000000000000000000000000000000000000",
		},
		{
			name:                    "verify timeout timestamp field encoding",
			sourceChannelId:         0,
			destinationChannelId:    0,
			data:                    nil,
			timeoutTimestamp:        1000,
			wantSourceChannelHex:    "0000000000000000000000000000000000000000000000000000000000000000",
			wantDestChannelHex:      "0000000000000000000000000000000000000000000000000000000000000000",
			wantDataOffsetHex:       "00000000000000000000000000000000000000000000000000000000000000a0",
			wantTimeoutHeightHex:    "0000000000000000000000000000000000000000000000000000000000000000",
			wantTimeoutTimestampHex: "00000000000000000000000000000000000000000000000000000000000003e8",
			wantDataLenHex:          "0000000000000000000000000000000000000000000000000000000000000000",
			wantDataPayloadHex:      "0000000000000000000000000000000000000000000000000000000000000000",
		},
		{
			name:                    "verify large timeout timestamp encoding",
			sourceChannelId:         0,
			destinationChannelId:    0,
			data:                    nil,
			timeoutTimestamp:        4294967295,
			wantSourceChannelHex:    "0000000000000000000000000000000000000000000000000000000000000000",
			wantDestChannelHex:      "0000000000000000000000000000000000000000000000000000000000000000",
			wantDataOffsetHex:       "00000000000000000000000000000000000000000000000000000000000000a0",
			wantTimeoutHeightHex:    "0000000000000000000000000000000000000000000000000000000000000000",
			wantTimeoutTimestampHex: "00000000000000000000000000000000000000000000000000000000ffffffff",
			wantDataLenHex:          "0000000000000000000000000000000000000000000000000000000000000000",
			wantDataPayloadHex:      "0000000000000000000000000000000000000000000000000000000000000000",
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			packet := NewPacket(tc.sourceChannelId, tc.destinationChannelId, tc.data, tc.timeoutTimestamp)
			encoded, err := packet.EncodeABI()
			if err != nil {
				t.Fatalf("unexpected error: %v", err)
			}

			// Verify encoding has at least 5 fixed fields worth of data
			// Each ABI field is 32 bytes
			if len(encoded) < 160 { // minimum 5 * 32 fixed fields
				t.Errorf("encoded length = %d, want at least 160", len(encoded))
			}

			// Extract fields for verification
			// Fields: [sourceChannelId][destinationChannelId][dataOffset][timeoutHeight][timeoutTimestamp][dataLen][dataPayload...]
			offset := 0

			// Source channel ID (32 bytes)
			sourceChannelField := encoded[offset : offset+32]
			offset += 32

			// Destination channel ID (32 bytes)
			destChannelField := encoded[offset : offset+32]
			offset += 32

			// Data offset (32 bytes) - points to data tail section
			dataOffsetField := encoded[offset : offset+32]
			offset += 32

			// Timeout height (32 bytes)
			timeoutHeightField := encoded[offset : offset+32]
			offset += 32

			// Timeout timestamp (32 bytes)
			timeoutTimestampField := encoded[offset : offset+32]
			offset += 32

			// Data length (32 bytes) - start of data tail
			dataLenField := encoded[offset : offset+32]

			// Verify each field
			assertHex(t, "source channel ID field", sourceChannelField, tc.wantSourceChannelHex)
			assertHex(t, "destination channel ID field", destChannelField, tc.wantDestChannelHex)
			assertHex(t, "data offset field", dataOffsetField, tc.wantDataOffsetHex)
			assertHex(t, "timeout height field", timeoutHeightField, tc.wantTimeoutHeightHex)
			assertHex(t, "timeout timestamp field", timeoutTimestampField, tc.wantTimeoutTimestampHex)
			assertHex(t, "data length field", dataLenField, tc.wantDataLenHex)

			// Only verify data payload if data is non-nil/non-empty
			if len(tc.data) > 0 {
				offset += 32
				dataPayloadField := encoded[offset : offset+32]
				assertHex(t, "data payload field", dataPayloadField, tc.wantDataPayloadHex)
			}
		})
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

func TestPacketEncodeABI_Schema(t *testing.T) {
	tests := []struct {
		name       string
		fieldCount int
	}{
		{
			name:       "schema has 5 fields",
			fieldCount: 5,
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			packet := NewPacket(1, 2, []byte{0x01}, 100)

			encoded, err := packet.EncodeABI()
			if err != nil {
				t.Fatalf("unexpected error: %v", err)
			}

			// Verify minimum encoding length (5 fixed-width fields at 32 bytes each)
			// Note: Data field is dynamic, so total length varies
			if len(encoded) < tc.fieldCount*32 {
				t.Errorf("encoded length = %d, want at least %d", len(encoded), tc.fieldCount*32)
			}
		})
	}
}
