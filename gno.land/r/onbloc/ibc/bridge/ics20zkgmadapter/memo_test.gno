package ics20zkgmadapter

import (
	"encoding/hex"
	"testing"
)

func TestParseZkgmForwardMemo(t *testing.T) {
	const valid = `{"forward":{"channel":1,"receiver":"0xaabbccdd","quote_token":"0x11223344","metadata":{"implementation":"0x01","initializer":"0x02"}}}`

	tests := []struct {
		name    string
		raw     string
		wantErr bool
	}{
		{"valid", valid, false},
		{"empty", "", true},
		{"not json", "not-json", true},
		{"no forward key", `{"other":{}}`, true},
		{"missing receiver", `{"forward":{"channel":1,"quote_token":"0x01","metadata":{"implementation":"0x01","initializer":"0x02"}}}`, true},
		{"missing channel", `{"forward":{"receiver":"0x01","quote_token":"0x01","metadata":{"implementation":"0x01","initializer":"0x02"}}}`, true},
		{"missing quote_token", `{"forward":{"channel":1,"receiver":"0x01","metadata":{"implementation":"0x01","initializer":"0x02"}}}`, true},
		{"missing metadata", `{"forward":{"channel":1,"receiver":"0x01","quote_token":"0x01"}}`, true},
		{"invalid receiver hex", `{"forward":{"channel":1,"receiver":"0xzz","quote_token":"0x01","metadata":{"implementation":"0x01","initializer":"0x02"}}}`, true},
	}
	for _, tt := range tests {
		_, err := parseForwardMemo(tt.raw)
		if (err != nil) != tt.wantErr {
			t.Errorf("%s: parseForwardMemo err = %v, wantErr %t", tt.name, err, tt.wantErr)
		}
	}
}

func TestParseICS20ForwardMemo(t *testing.T) {
	const valid = `{"forward":{"destination_client":"07-tendermint-1","atomone_receiver":"atone1receiver"}}`

	tests := []struct {
		name    string
		raw     string
		wantErr bool
	}{
		{"valid", valid, false},
		{"missing atomone_receiver", `{"forward":{"destination_client":"07-tendermint-1"}}`, true},
		{"empty destination_client", `{"forward":{"destination_client":"","atomone_receiver":"atone1receiver"}}`, true},
	}
	for _, tt := range tests {
		_, err := parseForwardMemo(tt.raw)
		if (err != nil) != tt.wantErr {
			t.Errorf("%s: parseForwardMemo err = %v, wantErr %t", tt.name, err, tt.wantErr)
		}
	}
}

func TestParseICS20ForwardMemoFields(t *testing.T) {
	const raw = `{"forward":{"destination_client":"07-tendermint-1","atomone_receiver":"atone1receiver","memo":"hello","timeout_timestamp":1234}}`
	m, err := parseForwardMemo(raw)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if m.DestinationClient != "07-tendermint-1" {
		t.Errorf("destination_client = %q, want 07-tendermint-1", m.DestinationClient)
	}
	if m.AtomoneReceiver != "atone1receiver" {
		t.Errorf("atomone_receiver = %q, want atone1receiver", m.AtomoneReceiver)
	}
	if m.Memo != "hello" {
		t.Errorf("memo = %q, want hello", m.Memo)
	}
	if m.TimeoutTimestamp != 1234 {
		t.Errorf("timeout_timestamp = %d, want 1234", m.TimeoutTimestamp)
	}
}

func TestParseZkgmForwardMemoFields(t *testing.T) {
	const raw = `{"forward":{"channel":7,"receiver":"0xaabbccdd","quote_token":"0x11223344","metadata":{"implementation":"0x0102","initializer":"0x0304"},"timeout_timestamp":1234}}`
	m, err := parseForwardMemo(raw)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if m.Channel != 7 {
		t.Errorf("channel = %d, want 7", m.Channel)
	}
	if got := hex.EncodeToString(m.Receiver); got != "aabbccdd" {
		t.Errorf("receiver = %q, want aabbccdd", got)
	}
	if got := hex.EncodeToString(m.QuoteToken); got != "11223344" {
		t.Errorf("quote_token = %q, want 11223344", got)
	}
	if got := hex.EncodeToString(m.Metadata.Implementation); got != "0102" {
		t.Errorf("metadata.implementation = %q, want 0102", got)
	}
	if got := hex.EncodeToString(m.Metadata.Initializer); got != "0304" {
		t.Errorf("metadata.initializer = %q, want 0304", got)
	}
	if m.TimeoutTimestamp != 1234 {
		t.Errorf("timeout_timestamp = %d, want 1234", m.TimeoutTimestamp)
	}
}
