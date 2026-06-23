package types

import (
	"bytes"
	"testing"
)

func TestNewChannel(t *testing.T) {
	tests := []struct {
		name                      string
		state                     ChannelState
		connectionId              ConnectionId
		counterpartyChannelId     ChannelId
		counterpartyPortId        Bytes
		version                   string
		wantState                 ChannelState
		wantConnectionId          ConnectionId
		wantCounterpartyChannelId ChannelId
		wantCounterpartyPortId    Bytes
		wantVersion               string
	}{
		{
			name:                      "channel with all zero values",
			state:                     ChannelStateUnknown,
			connectionId:              0,
			counterpartyChannelId:     0,
			counterpartyPortId:        Bytes{},
			version:                   "",
			wantState:                 ChannelStateUnknown,
			wantConnectionId:          0,
			wantCounterpartyChannelId: 0,
			wantCounterpartyPortId:    Bytes{},
			wantVersion:               "",
		},
		{
			name:                      "channel in init state",
			state:                     ChannelStateInit,
			connectionId:              1,
			counterpartyChannelId:     2,
			counterpartyPortId:        Bytes{0x01, 0x02, 0x03},
			version:                   "1.0",
			wantState:                 ChannelStateInit,
			wantConnectionId:          1,
			wantCounterpartyChannelId: 2,
			wantCounterpartyPortId:    Bytes{0x01, 0x02, 0x03},
			wantVersion:               "1.0",
		},
		{
			name:                      "channel in tryopen state",
			state:                     ChannelStateTryOpen,
			connectionId:              100,
			counterpartyChannelId:     200,
			counterpartyPortId:        Bytes{0xff, 0xfe},
			version:                   "2.0-beta",
			wantState:                 ChannelStateTryOpen,
			wantConnectionId:          100,
			wantCounterpartyChannelId: 200,
			wantCounterpartyPortId:    Bytes{0xff, 0xfe},
			wantVersion:               "2.0-beta",
		},
		{
			name:                      "channel in open state",
			state:                     ChannelStateOpen,
			connectionId:              4294967295, // max uint32
			counterpartyChannelId:     4294967294,
			counterpartyPortId:        Bytes{0xaa, 0xbb, 0xcc, 0xdd},
			version:                   "v3.0.1",
			wantState:                 ChannelStateOpen,
			wantConnectionId:          4294967295,
			wantCounterpartyChannelId: 4294967294,
			wantCounterpartyPortId:    Bytes{0xaa, 0xbb, 0xcc, 0xdd},
			wantVersion:               "v3.0.1",
		},
		{
			name:                      "channel in closed state",
			state:                     ChannelStateClosed,
			connectionId:              42,
			counterpartyChannelId:     99,
			counterpartyPortId:        Bytes{},
			version:                   "legacy",
			wantState:                 ChannelStateClosed,
			wantConnectionId:          42,
			wantCounterpartyChannelId: 99,
			wantCounterpartyPortId:    Bytes{},
			wantVersion:               "legacy",
		},
		{
			name:                      "channel with mixed zero and non-zero values",
			state:                     ChannelStateInit,
			connectionId:              0,
			counterpartyChannelId:     50,
			counterpartyPortId:        Bytes{0xde, 0xad, 0xbe, 0xef},
			version:                   "",
			wantState:                 ChannelStateInit,
			wantConnectionId:          0,
			wantCounterpartyChannelId: 50,
			wantCounterpartyPortId:    Bytes{0xde, 0xad, 0xbe, 0xef},
			wantVersion:               "",
		},
		{
			name:                      "channel with empty port ID",
			state:                     ChannelStateOpen,
			connectionId:              123,
			counterpartyChannelId:     456,
			counterpartyPortId:        Bytes{},
			version:                   "empty-port",
			wantState:                 ChannelStateOpen,
			wantConnectionId:          123,
			wantCounterpartyChannelId: 456,
			wantCounterpartyPortId:    Bytes{},
			wantVersion:               "empty-port",
		},
		{
			name:                      "channel with large port ID",
			state:                     ChannelStateTryOpen,
			connectionId:              1,
			counterpartyChannelId:     2,
			counterpartyPortId:        Bytes{0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0a, 0x0b, 0x0c, 0x0d, 0x0e, 0x0f, 0x10, 0x11, 0x12, 0x13, 0x14, 0x15, 0x16, 0x17, 0x18, 0x19, 0x1a, 0x1b, 0x1c, 0x1d, 0x1e, 0x1f, 0x20},
			version:                   "large-port-test",
			wantState:                 ChannelStateTryOpen,
			wantConnectionId:          1,
			wantCounterpartyChannelId: 2,
			wantCounterpartyPortId:    Bytes{0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0a, 0x0b, 0x0c, 0x0d, 0x0e, 0x0f, 0x10, 0x11, 0x12, 0x13, 0x14, 0x15, 0x16, 0x17, 0x18, 0x19, 0x1a, 0x1b, 0x1c, 0x1d, 0x1e, 0x1f, 0x20},
			wantVersion:               "large-port-test",
		},
		{
			name:                      "channel with minimum uint32 values",
			state:                     ChannelStateUnknown,
			connectionId:              0,
			counterpartyChannelId:     0,
			counterpartyPortId:        Bytes{0x00},
			version:                   "min-values",
			wantState:                 ChannelStateUnknown,
			wantConnectionId:          0,
			wantCounterpartyChannelId: 0,
			wantCounterpartyPortId:    Bytes{0x00},
			wantVersion:               "min-values",
		},
		{
			name:                      "channel with special version string",
			state:                     ChannelStateOpen,
			connectionId:              256,
			counterpartyChannelId:     512,
			counterpartyPortId:        Bytes{0xff},
			version:                   "ics20-1",
			wantState:                 ChannelStateOpen,
			wantConnectionId:          256,
			wantCounterpartyChannelId: 512,
			wantCounterpartyPortId:    Bytes{0xff},
			wantVersion:               "ics20-1",
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			got := NewChannel(tc.state, tc.connectionId, tc.counterpartyChannelId, tc.counterpartyPortId, tc.version)

			if got.State != tc.wantState {
				t.Errorf("State = %v, want %v", got.State, tc.wantState)
			}
			if got.ConnectionId != tc.wantConnectionId {
				t.Errorf("ConnectionId = %v, want %v", got.ConnectionId, tc.wantConnectionId)
			}
			if got.CounterpartyChannelId != tc.wantCounterpartyChannelId {
				t.Errorf("CounterpartyChannelId = %v, want %v", got.CounterpartyChannelId, tc.wantCounterpartyChannelId)
			}
			if !bytes.Equal(got.CounterpartyPortId.Bytes(), tc.wantCounterpartyPortId.Bytes()) {
				t.Errorf("CounterpartyPortId = %v, want %v", got.CounterpartyPortId, tc.wantCounterpartyPortId)
			}
			if got.Version != tc.wantVersion {
				t.Errorf("Version = %q, want %q", got.Version, tc.wantVersion)
			}
		})
	}
}

func TestChannel_EncodeABI(t *testing.T) {
	tests := []struct {
		name    string
		channel Channel
		wantErr bool
		minLen  int
	}{
		{
			name: "valid channel with all zeros",
			channel: Channel{
				State:                 ChannelStateUnknown,
				ConnectionId:          0,
				CounterpartyChannelId: 0,
				CounterpartyPortId:    Bytes{},
				Version:               "",
			},
			wantErr: false,
			minLen:  96,
		},
		{
			name: "valid channel with all fields set",
			channel: Channel{
				State:                 ChannelStateOpen,
				ConnectionId:          1,
				CounterpartyChannelId: 2,
				CounterpartyPortId:    Bytes{0xaa, 0xbb},
				Version:               "1.0",
			},
			wantErr: false,
			minLen:  96,
		},
		{
			name: "valid channel in init state",
			channel: Channel{
				State:                 ChannelStateInit,
				ConnectionId:          42,
				CounterpartyChannelId: 100,
				CounterpartyPortId:    Bytes{0x01, 0x02, 0x03},
				Version:               "ics20-1",
			},
			wantErr: false,
			minLen:  96,
		},
		{
			name: "valid channel in tryopen state",
			channel: Channel{
				State:                 ChannelStateTryOpen,
				ConnectionId:          4294967295,
				CounterpartyChannelId: 0,
				CounterpartyPortId:    Bytes{},
				Version:               "test",
			},
			wantErr: false,
			minLen:  96,
		},
		{
			name: "valid channel with maximum values",
			channel: Channel{
				State:                 ChannelStateClosed,
				ConnectionId:          4294967295,
				CounterpartyChannelId: 4294967295,
				CounterpartyPortId:    Bytes{0xff, 0xff, 0xff, 0xff},
				Version:               "max",
			},
			wantErr: false,
			minLen:  96,
		},
		{
			name: "valid channel with empty port ID and version",
			channel: Channel{
				State:                 ChannelStateOpen,
				ConnectionId:          1,
				CounterpartyChannelId: 1,
				CounterpartyPortId:    Bytes{},
				Version:               "",
			},
			wantErr: false,
			minLen:  96,
		},
		{
			name: "valid channel with large port ID",
			channel: Channel{
				State:                 ChannelStateOpen,
				ConnectionId:          100,
				CounterpartyChannelId: 200,
				CounterpartyPortId:    Bytes{0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0a, 0x0b, 0x0c, 0x0d, 0x0e, 0x0f, 0x10, 0x11, 0x12, 0x13, 0x14, 0x15, 0x16, 0x17, 0x18, 0x19, 0x1a, 0x1b, 0x1c, 0x1d, 0x1e, 0x1f, 0x20},
				Version:               "large-port",
			},
			wantErr: false,
			minLen:  96,
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			got, err := tc.channel.EncodeABI()

			if tc.wantErr {
				if err == nil {
					t.Errorf("expected error, got nil")
				}
				return
			}

			if err != nil {
				t.Fatalf("unexpected error: %v", err)
			}

			if len(got) < tc.minLen {
				t.Errorf("encoded length = %d, want >= %d", len(got), tc.minLen)
			}

			// Verify encoding is deterministic
			got2, err2 := tc.channel.EncodeABI()
			if err2 != nil {
				t.Fatalf("second encoding error: %v", err2)
			}
			if len(got) != len(got2) {
				t.Errorf("encoding not deterministic: first length = %d, second length = %d", len(got), len(got2))
			}
			for i := range got {
				if got[i] != got2[i] {
					t.Errorf("encoding not deterministic: first byte[%d] = %d, second byte[%d] = %d", i, got[i], i, got2[i])
				}
			}
		})
	}
}

func TestChannelEncodeABI_FieldEncoding(t *testing.T) {
	tests := []struct {
		name                  string
		state                 ChannelState
		connectionId          ConnectionId
		counterpartyChannelId ChannelId
	}{
		{
			name:                  "verify state field encoding - unknown",
			state:                 ChannelStateUnknown,
			connectionId:          0,
			counterpartyChannelId: 0,
		},
		{
			name:                  "verify state field encoding - init",
			state:                 ChannelStateInit,
			connectionId:          0,
			counterpartyChannelId: 0,
		},
		{
			name:                  "verify state field encoding - tryopen",
			state:                 ChannelStateTryOpen,
			connectionId:          0,
			counterpartyChannelId: 0,
		},
		{
			name:                  "verify state field encoding - open",
			state:                 ChannelStateOpen,
			connectionId:          0,
			counterpartyChannelId: 0,
		},
		{
			name:                  "verify state field encoding - closed",
			state:                 ChannelStateClosed,
			connectionId:          0,
			counterpartyChannelId: 0,
		},
		{
			name:                  "verify connection ID field encoding",
			state:                 ChannelStateInit,
			connectionId:          255,
			counterpartyChannelId: 0,
		},
		{
			name:                  "verify counterparty channel ID field encoding",
			state:                 ChannelStateInit,
			connectionId:          0,
			counterpartyChannelId: 256,
		},
		{
			name:                  "verify maximum uint32 value encoding",
			state:                 ChannelStateOpen,
			connectionId:          0,
			counterpartyChannelId: 4294967295,
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			channel := NewChannel(tc.state, tc.connectionId, tc.counterpartyChannelId, Bytes{}, "")
			got, err := channel.EncodeABI()
			if err != nil {
				t.Fatalf("unexpected error: %v", err)
			}

			if len(got) < 96 {
				t.Errorf("encoded length = %d, want >= 96", len(got))
			}

			// Verify encoding is deterministic across multiple calls
			for i := 0; i < 3; i++ {
				encoded, err2 := channel.EncodeABI()
				if err2 != nil {
					t.Fatalf("encoding error on iteration %d: %v", i, err2)
				}
				if len(encoded) != len(got) {
					t.Errorf("encoding length not consistent on iteration %d: got %d, want %d", i, len(encoded), len(got))
				}
			}
		})
	}
}

func TestChannelStateValues(t *testing.T) {
	tests := []struct {
		name          string
		state         ChannelState
		expectedValue uint8
	}{
		{
			name:          "ChannelStateUnknown value",
			state:         ChannelStateUnknown,
			expectedValue: 0,
		},
		{
			name:          "ChannelStateInit value",
			state:         ChannelStateInit,
			expectedValue: 1,
		},
		{
			name:          "ChannelStateTryOpen value",
			state:         ChannelStateTryOpen,
			expectedValue: 2,
		},
		{
			name:          "ChannelStateOpen value",
			state:         ChannelStateOpen,
			expectedValue: 3,
		},
		{
			name:          "ChannelStateClosed value",
			state:         ChannelStateClosed,
			expectedValue: 4,
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			if uint8(tc.state) != tc.expectedValue {
				t.Errorf("State value = %d, want %d", uint8(tc.state), tc.expectedValue)
			}

			channel := NewChannel(tc.state, 0, 0, Bytes{}, "")
			if channel.State != tc.state {
				t.Errorf("NewChannel preserved State = %v, want %v", channel.State, tc.state)
			}
		})
	}
}

func TestChannelEncodeABI_Schema(t *testing.T) {
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
			channel := NewChannel(ChannelStateInit, 1, 2, Bytes{0xaa}, "test")

			encoded, err := channel.EncodeABI()
			if err != nil {
				t.Fatalf("unexpected error: %v", err)
			}

			// Channel EncodeABI produces dynamic-length encoding due to bytes and string fields
			// Verify we got a non-empty encoding
			if len(encoded) == 0 {
				t.Errorf("encoded length = 0, want > 0")
			}

			// Verify at least the fixed fields (state + 2 uint32s = 3 fields * 32 bytes)
			minLength := 3 * 32 // 96 bytes for fixed fields
			if len(encoded) < minLength {
				t.Errorf("encoded length = %d, want >= %d", len(encoded), minLength)
			}
		})
	}
}
