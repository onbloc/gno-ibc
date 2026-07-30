package ics20zkgmadapter

import (
	"encoding/hex"
	"testing"
)

func TestParseZkgmMemo(t *testing.T) {
	const valid = `{"forward":{"receiver":"0xaabbccdd","channel":"1","quote_token":"0x11223344","metadata":{"implementation":"0x01","initializer":"0x02"}}}`

	tests := []struct {
		name    string
		raw     string
		wantErr bool
	}{
		{"valid", valid, false},
		{"empty", "", true},
		{"not json", "not-json", true},
		{"no forward key", `{"other":{}}`, true},
		{"missing receiver", `{"forward":{"channel":"1","quote_token":"0x01","metadata":{"implementation":"0x01","initializer":"0x02"}}}`, true},
		{"missing channel", `{"forward":{"receiver":"0x01","quote_token":"0x01","metadata":{"implementation":"0x01","initializer":"0x02"}}}`, true},
		{"missing quote_token", `{"forward":{"receiver":"0x01","channel":"1","metadata":{"implementation":"0x01","initializer":"0x02"}}}`, true},
		{"missing metadata", `{"forward":{"receiver":"0x01","channel":"1","quote_token":"0x01"}}`, true},
		{"invalid receiver hex", `{"forward":{"receiver":"0xzz","channel":"1","quote_token":"0x01","metadata":{"implementation":"0x01","initializer":"0x02"}}}`, true},
		{"wrong direction (no quote_token, ics20-shaped)", `{"forward":{"receiver":"atone1receiver","channel":"07-tendermint-1"}}`, true},
	}
	for _, tt := range tests {
		_, err := parseZkgmMemo(tt.raw)
		if (err != nil) != tt.wantErr {
			t.Errorf("%s: parseZkgmMemo err = %v, wantErr %t", tt.name, err, tt.wantErr)
		}
	}
}

func TestParseICS20Memo(t *testing.T) {
	const valid = `{"forward":{"receiver":"atone1receiver","channel":"07-tendermint-1"}}`

	tests := []struct {
		name    string
		raw     string
		wantErr bool
	}{
		{"valid", valid, false},
		{"missing channel", `{"forward":{"receiver":"atone1receiver"}}`, true},
		{"empty receiver", `{"forward":{"receiver":"","channel":"07-tendermint-1"}}`, true},
		{"wrong direction (has quote_token, zkgm-shaped)", `{"forward":{"receiver":"0xaabbccdd","channel":"1","quote_token":"0x11223344","metadata":{"implementation":"0x01","initializer":"0x01"}}}`, true},
	}
	for _, tt := range tests {
		_, err := parseICS20Memo(tt.raw)
		if (err != nil) != tt.wantErr {
			t.Errorf("%s: parseICS20Memo err = %v, wantErr %t", tt.name, err, tt.wantErr)
		}
	}
}

func TestParseICS20ForwardMemoFields(t *testing.T) {
	const raw = `{"forward":{"receiver":"atone1receiver","channel":"07-tendermint-1","memo":"hello","timeout":1234}}`
	m, err := parseICS20Memo(raw)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if m.Channel != "07-tendermint-1" {
		t.Errorf("channel = %q, want 07-tendermint-1", m.Channel)
	}
	if m.Receiver != "atone1receiver" {
		t.Errorf("receiver = %q, want atone1receiver", m.Receiver)
	}
	if m.Memo != "hello" {
		t.Errorf("memo = %q, want hello", m.Memo)
	}
	if m.Timeout != 1234 {
		t.Errorf("timeout = %d, want 1234", m.Timeout)
	}
}

func TestParseZkgmForwardMemoFields(t *testing.T) {
	const raw = `{"forward":{"receiver":"0xaabbccdd","channel":"7","quote_token":"0x11223344","metadata":{"implementation":"0x0102","initializer":"0x0304"},"timeout":1234}}`
	m, err := parseZkgmMemo(raw)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if m.Channel != "7" {
		t.Errorf("channel = %q, want 7", m.Channel)
	}
	if m.Receiver != "aabbccdd" {
		t.Errorf("receiver = %q, want aabbccdd", m.Receiver)
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
	if m.Timeout != 1234 {
		t.Errorf("timeout = %d, want 1234", m.Timeout)
	}
}

func TestParsePFMCoreOptionalFields(t *testing.T) {
	const raw = `{"forward":{"receiver":"atone1receiver","channel":"07-tendermint-1","port":"custom-port","retries":3}}`
	m, err := parseICS20Memo(raw)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if m.Port != "custom-port" {
		t.Errorf("port = %q, want custom-port", m.Port)
	}
	if m.Retries != 3 {
		t.Errorf("retries = %d, want 3", m.Retries)
	}
}
