package types

import "testing"

func TestNewConnection(t *testing.T) {
	tests := []struct {
		name                     string
		state                    ConnectionState
		clientId                 ClientId
		counterpartyClientId     ClientId
		counterpartyConnectionId ConnectionId
		wantState                ConnectionState
		wantClientId             ClientId
		wantCounterpartyClientId ClientId
		wantCounterpartyConnId   ConnectionId
	}{
		{
			name:                     "connection with all zero values",
			state:                    ConnectionStateUnknown,
			clientId:                 0,
			counterpartyClientId:     0,
			counterpartyConnectionId: 0,
			wantState:                ConnectionStateUnknown,
			wantClientId:             0,
			wantCounterpartyClientId: 0,
			wantCounterpartyConnId:   0,
		},
		{
			name:                     "connection in init state",
			state:                    ConnectionStateInit,
			clientId:                 1,
			counterpartyClientId:     2,
			counterpartyConnectionId: 3,
			wantState:                ConnectionStateInit,
			wantClientId:             1,
			wantCounterpartyClientId: 2,
			wantCounterpartyConnId:   3,
		},
		{
			name:                     "connection in tryopen state",
			state:                    ConnectionStateTryOpen,
			clientId:                 100,
			counterpartyClientId:     200,
			counterpartyConnectionId: 300,
			wantState:                ConnectionStateTryOpen,
			wantClientId:             100,
			wantCounterpartyClientId: 200,
			wantCounterpartyConnId:   300,
		},
		{
			name:                     "connection in open state",
			state:                    ConnectionStateOpen,
			clientId:                 4294967295, // max uint32
			counterpartyClientId:     4294967294,
			counterpartyConnectionId: 4294967293,
			wantState:                ConnectionStateOpen,
			wantClientId:             4294967295,
			wantCounterpartyClientId: 4294967294,
			wantCounterpartyConnId:   4294967293,
		},
		{
			name:                     "connection with mixed zero and non-zero values",
			state:                    ConnectionStateInit,
			clientId:                 0,
			counterpartyClientId:     42,
			counterpartyConnectionId: 0,
			wantState:                ConnectionStateInit,
			wantClientId:             0,
			wantCounterpartyClientId: 42,
			wantCounterpartyConnId:   0,
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			got := NewConnection(tc.state, tc.clientId, tc.counterpartyClientId, tc.counterpartyConnectionId)

			if got.State != tc.wantState {
				t.Errorf("State = %v, want %v", got.State, tc.wantState)
			}
			if got.ClientId != tc.wantClientId {
				t.Errorf("ClientId = %v, want %v", got.ClientId, tc.wantClientId)
			}
			if got.CounterpartyClientId != tc.wantCounterpartyClientId {
				t.Errorf("CounterpartyClientId = %v, want %v", got.CounterpartyClientId, tc.wantCounterpartyClientId)
			}
			if got.CounterpartyConnectionId != tc.wantCounterpartyConnId {
				t.Errorf("CounterpartyConnectionId = %v, want %v", got.CounterpartyConnectionId, tc.wantCounterpartyConnId)
			}
		})
	}
}

func TestConnectionEncodeABI(t *testing.T) {
	tests := []struct {
		name    string
		conn    Connection
		want    string
		wantErr error
	}{
		{
			name: "valid connection with all zeros",
			conn: Connection{
				State:                    ConnectionStateUnknown,
				ClientId:                 0,
				CounterpartyClientId:     0,
				CounterpartyConnectionId: 0,
			},
			want: "0000000000000000000000000000000000000000000000000000000000000000" +
				"0000000000000000000000000000000000000000000000000000000000000000" +
				"0000000000000000000000000000000000000000000000000000000000000000" +
				"0000000000000000000000000000000000000000000000000000000000000000",
			wantErr: nil,
		},
		{
			name: "valid connection with all fields set",
			conn: Connection{
				State:                    ConnectionStateOpen,
				ClientId:                 1,
				CounterpartyClientId:     2,
				CounterpartyConnectionId: 3,
			},
			want: "0000000000000000000000000000000000000000000000000000000000000003" +
				"0000000000000000000000000000000000000000000000000000000000000001" +
				"0000000000000000000000000000000000000000000000000000000000000002" +
				"0000000000000000000000000000000000000000000000000000000000000003",
			wantErr: nil,
		},
		{
			name: "valid connection with init state",
			conn: Connection{
				State:                    ConnectionStateInit,
				ClientId:                 42,
				CounterpartyClientId:     100,
				CounterpartyConnectionId: 200,
			},
			want: "0000000000000000000000000000000000000000000000000000000000000001" +
				"000000000000000000000000000000000000000000000000000000000000002a" +
				"0000000000000000000000000000000000000000000000000000000000000064" +
				"00000000000000000000000000000000000000000000000000000000000000c8",
			wantErr: nil,
		},
		{
			name: "valid connection with tryopen state",
			conn: Connection{
				State:                    ConnectionStateTryOpen,
				ClientId:                 4294967295, // max uint32
				CounterpartyClientId:     0,
				CounterpartyConnectionId: 1,
			},
			want: "0000000000000000000000000000000000000000000000000000000000000002" +
				"00000000000000000000000000000000000000000000000000000000ffffffff" +
				"0000000000000000000000000000000000000000000000000000000000000000" +
				"0000000000000000000000000000000000000000000000000000000000000001",
			wantErr: nil,
		},
		{
			name: "valid connection with maximum values",
			conn: Connection{
				State:                    ConnectionStateOpen,
				ClientId:                 4294967295,
				CounterpartyClientId:     4294967295,
				CounterpartyConnectionId: 4294967295,
			},
			want: "0000000000000000000000000000000000000000000000000000000000000003" +
				"00000000000000000000000000000000000000000000000000000000ffffffff" +
				"00000000000000000000000000000000000000000000000000000000ffffffff" +
				"00000000000000000000000000000000000000000000000000000000ffffffff",
			wantErr: nil,
		},
		{
			name: "valid connection with unknown state",
			conn: Connection{
				State:                    ConnectionStateUnknown,
				ClientId:                 123,
				CounterpartyClientId:     456,
				CounterpartyConnectionId: 789,
			},
			want: "0000000000000000000000000000000000000000000000000000000000000000" +
				"000000000000000000000000000000000000000000000000000000000000007b" +
				"00000000000000000000000000000000000000000000000000000000000001c8" +
				"0000000000000000000000000000000000000000000000000000000000000315",
			wantErr: nil,
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			got, err := tc.conn.EncodeABI()

			if tc.wantErr != nil {
				if err != tc.wantErr {
					t.Errorf("error = %v, wantErr %v", err, tc.wantErr)
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

func TestConnectionEncodeABI_ErrorHandling(t *testing.T) {
	tests := []struct {
		name    string
		conn    Connection
		wantErr string
	}{
		{
			name: "valid connection - no error",
			conn: Connection{
				State:                    ConnectionStateInit,
				ClientId:                 1,
				CounterpartyClientId:     2,
				CounterpartyConnectionId: 3,
			},
			wantErr: "",
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			_, err := tc.conn.EncodeABI()

			if tc.wantErr != "" {
				if err == nil {
					t.Fatal("expected error, got nil")
				}
				if err.Error() != tc.wantErr {
					t.Errorf("error = %q, want %q", err.Error(), tc.wantErr)
				}
			} else if err != nil {
				t.Fatalf("unexpected error: %v", err)
			}
		})
	}
}

func TestConnectionEncodeABI_FieldEncoding(t *testing.T) {
	tests := []struct {
		name         string
		state        ConnectionState
		clientId     ClientId
		counterparty ClientId
		connId       ConnectionId
		wantStateHex string
		wantClient   string
		wantCounter  string
		wantConnId   string
	}{
		{
			name:         "verify state field encoding",
			state:        ConnectionStateOpen,
			clientId:     0,
			counterparty: 0,
			connId:       0,
			wantStateHex: "0000000000000000000000000000000000000000000000000000000000000003",
			wantClient:   "0000000000000000000000000000000000000000000000000000000000000000",
			wantCounter:  "0000000000000000000000000000000000000000000000000000000000000000",
			wantConnId:   "0000000000000000000000000000000000000000000000000000000000000000",
		},
		{
			name:         "verify client ID field encoding",
			state:        ConnectionStateInit,
			clientId:     255,
			counterparty: 0,
			connId:       0,
			wantStateHex: "0000000000000000000000000000000000000000000000000000000000000001",
			wantClient:   "00000000000000000000000000000000000000000000000000000000000000ff",
			wantCounter:  "0000000000000000000000000000000000000000000000000000000000000000",
			wantConnId:   "0000000000000000000000000000000000000000000000000000000000000000",
		},
		{
			name:         "verify counterparty client ID field encoding",
			state:        ConnectionStateTryOpen,
			clientId:     0,
			counterparty: 256,
			connId:       0,
			wantStateHex: "0000000000000000000000000000000000000000000000000000000000000002",
			wantClient:   "0000000000000000000000000000000000000000000000000000000000000000",
			wantCounter:  "0000000000000000000000000000000000000000000000000000000000000100",
			wantConnId:   "0000000000000000000000000000000000000000000000000000000000000000",
		},
		{
			name:         "verify connection ID field encoding",
			state:        ConnectionStateOpen,
			clientId:     0,
			counterparty: 0,
			connId:       65535,
			wantStateHex: "0000000000000000000000000000000000000000000000000000000000000003",
			wantClient:   "0000000000000000000000000000000000000000000000000000000000000000",
			wantCounter:  "0000000000000000000000000000000000000000000000000000000000000000",
			wantConnId:   "000000000000000000000000000000000000000000000000000000000000ffff",
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			conn := NewConnection(tc.state, tc.clientId, tc.counterparty, tc.connId)
			got, err := conn.EncodeABI()

			if err != nil {
				t.Fatalf("unexpected error: %v", err)
			}

			if len(got) != 128 { // 4 fields * 32 bytes
				t.Errorf("encoded length = %d, want 128", len(got))
			}

			stateField := got[0:32]
			clientField := got[32:64]
			counterpartyField := got[64:96]
			connIdField := got[96:128]

			assertHex(t, "state field", stateField, tc.wantStateHex)
			assertHex(t, "client ID field", clientField, tc.wantClient)
			assertHex(t, "counterparty client ID field", counterpartyField, tc.wantCounter)
			assertHex(t, "connection ID field", connIdField, tc.wantConnId)
		})
	}
}

func TestConnectionStateValues(t *testing.T) {
	tests := []struct {
		name          string
		state         ConnectionState
		expectedValue uint8
	}{
		{
			name:          "ConnectionStateUnknown value",
			state:         ConnectionStateUnknown,
			expectedValue: 0,
		},
		{
			name:          "ConnectionStateInit value",
			state:         ConnectionStateInit,
			expectedValue: 1,
		},
		{
			name:          "ConnectionStateTryOpen value",
			state:         ConnectionStateTryOpen,
			expectedValue: 2,
		},
		{
			name:          "ConnectionStateOpen value",
			state:         ConnectionStateOpen,
			expectedValue: 3,
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			if uint8(tc.state) != tc.expectedValue {
				t.Errorf("State value = %d, want %d", uint8(tc.state), tc.expectedValue)
			}

			conn := NewConnection(tc.state, 0, 0, 0)
			if conn.State != tc.state {
				t.Errorf("NewConnection preserved State = %v, want %v", conn.State, tc.state)
			}
		})
	}
}

func TestConnectionEncodeABI_Schema(t *testing.T) {
	tests := []struct {
		name       string
		fieldCount int
	}{
		{
			name:       "schema has 4 fields",
			fieldCount: 4,
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			conn := Connection{
				State:                    ConnectionStateInit,
				ClientId:                 1,
				CounterpartyClientId:     2,
				CounterpartyConnectionId: 3,
			}

			encoded, err := conn.EncodeABI()
			if err != nil {
				t.Fatalf("unexpected error: %v", err)
			}

			expectedLength := tc.fieldCount * 32 // 4 fields, 32 bytes each
			if len(encoded) != expectedLength {
				t.Errorf("encoded length = %d, want %d", len(encoded), expectedLength)
			}
		})
	}
}
