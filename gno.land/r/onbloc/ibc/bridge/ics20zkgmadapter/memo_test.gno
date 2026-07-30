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
		{"channel not numeric (PFM channel-N form)", `{"forward":{"receiver":"0xaabbccdd","channel":"channel-1","quote_token":"0x11223344","metadata":{"implementation":"0x01","initializer":"0x02"}}}`, true},
		{"port not valid for this leg", `{"forward":{"receiver":"0xaabbccdd","channel":"1","port":"transfer","quote_token":"0x11223344","metadata":{"implementation":"0x01","initializer":"0x02"}}}`, true},
		{"port wrong type", `{"forward":{"receiver":"0xaabbccdd","channel":"1","port":123,"quote_token":"0x11223344","metadata":{"implementation":"0x01","initializer":"0x02"}}}`, true},
		{"retries wrong type", `{"forward":{"receiver":"0xaabbccdd","channel":"1","retries":"2","quote_token":"0x11223344","metadata":{"implementation":"0x01","initializer":"0x02"}}}`, true},
		{"retries negative", `{"forward":{"receiver":"0xaabbccdd","channel":"1","retries":-1,"quote_token":"0x11223344","metadata":{"implementation":"0x01","initializer":"0x02"}}}`, true},
		{"retries non-integer", `{"forward":{"receiver":"0xaabbccdd","channel":"1","retries":1.5,"quote_token":"0x11223344","metadata":{"implementation":"0x01","initializer":"0x02"}}}`, true},
		{"retries unsupported (retry-on-timeout not implemented)", `{"forward":{"receiver":"0xaabbccdd","channel":"1","retries":2,"quote_token":"0x11223344","metadata":{"implementation":"0x01","initializer":"0x02"}}}`, true},
		{"valid with retries 0", `{"forward":{"receiver":"0xaabbccdd","channel":"1","retries":0,"quote_token":"0x11223344","metadata":{"implementation":"0x01","initializer":"0x02"}}}`, false},
		{"timeout wrong type (numeric, not duration string)", `{"forward":{"receiver":"0xaabbccdd","channel":"1","timeout":10,"quote_token":"0x11223344","metadata":{"implementation":"0x01","initializer":"0x02"}}}`, true},
		{"timeout not a valid duration", `{"forward":{"receiver":"0xaabbccdd","channel":"1","timeout":"bad","quote_token":"0x11223344","metadata":{"implementation":"0x01","initializer":"0x02"}}}`, true},
		{"timeout non-positive", `{"forward":{"receiver":"0xaabbccdd","channel":"1","timeout":"0s","quote_token":"0x11223344","metadata":{"implementation":"0x01","initializer":"0x02"}}}`, true},
		{"valid with timeout duration", `{"forward":{"receiver":"0xaabbccdd","channel":"1","timeout":"10m","quote_token":"0x11223344","metadata":{"implementation":"0x01","initializer":"0x02"}}}`, false},
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
		{"port matches the fixed transfer port", `{"forward":{"receiver":"atone1receiver","channel":"07-tendermint-1","port":"transfer"}}`, false},
		{"port does not match", `{"forward":{"receiver":"atone1receiver","channel":"07-tendermint-1","port":"custom-port"}}`, true},
		{"port wrong type", `{"forward":{"receiver":"atone1receiver","channel":"07-tendermint-1","port":123}}`, true},
		{"timeout wrong type", `{"forward":{"receiver":"atone1receiver","channel":"07-tendermint-1","timeout":10}}`, true},
		{"timeout not a valid duration", `{"forward":{"receiver":"atone1receiver","channel":"07-tendermint-1","timeout":"bad"}}`, true},
		{"timeout too close to now (aib requires strictly after now, in whole seconds)", `{"forward":{"receiver":"atone1receiver","channel":"07-tendermint-1","timeout":"500ms"}}`, true},
		{"timeout exceeds aib core's max delta", `{"forward":{"receiver":"atone1receiver","channel":"07-tendermint-1","timeout":"48h"}}`, true},
		{"valid timeout within aib core's bounds", `{"forward":{"receiver":"atone1receiver","channel":"07-tendermint-1","timeout":"1h"}}`, false},
		{"retries wrong type", `{"forward":{"receiver":"atone1receiver","channel":"07-tendermint-1","retries":"2"}}`, true},
		{"retries non-integer", `{"forward":{"receiver":"atone1receiver","channel":"07-tendermint-1","retries":1.5}}`, true},
		{"retries unsupported (retry-on-timeout not implemented)", `{"forward":{"receiver":"atone1receiver","channel":"07-tendermint-1","retries":1}}`, true},
		{"next wrong type (number)", `{"forward":{"receiver":"atone1receiver","channel":"07-tendermint-1","next":123}}`, true},
	}
	for _, tt := range tests {
		_, err := parseICS20Memo(tt.raw)
		if (err != nil) != tt.wantErr {
			t.Errorf("%s: parseICS20Memo err = %v, wantErr %t", tt.name, err, tt.wantErr)
		}
	}
}

func TestParseICS20ForwardMemoFields(t *testing.T) {
	const raw = `{"forward":{"receiver":"atone1receiver","channel":"07-tendermint-1","next":"hello","timeout":"10m"}}`
	m, err := parseICS20Memo(raw)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if m.Core.Channel != "07-tendermint-1" {
		t.Errorf("channel = %q, want 07-tendermint-1", m.Core.Channel)
	}
	if m.Core.Receiver != "atone1receiver" {
		t.Errorf("receiver = %q, want atone1receiver", m.Core.Receiver)
	}
	if m.Next != "hello" {
		t.Errorf("next = %q, want hello", m.Next)
	}
	if m.Core.Timeout == 0 {
		t.Errorf("timeout = 0, want a resolved future UnixNano deadline")
	}
}

func TestParseICS20ForwardMemoNextObjectForm(t *testing.T) {
	const raw = `{"forward":{"receiver":"atone1receiver","channel":"07-tendermint-1","next":{"forward":{"receiver":"atone1nexthop","channel":"07-tendermint-2"}}}}`
	m, err := parseICS20Memo(raw)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if m.Next == "" {
		t.Fatal("next = empty, want the re-marshaled nested object")
	}
	// The re-marshaled next must itself parse back as a forward memo.
	nested, err := parseICS20Memo(m.Next)
	if err != nil {
		t.Fatalf("next did not round-trip as a forward memo: %v", err)
	}
	if nested.Core.Receiver != "atone1nexthop" {
		t.Errorf("nested receiver = %q, want atone1nexthop", nested.Core.Receiver)
	}
}

func TestParseZkgmForwardMemoFields(t *testing.T) {
	const raw = `{"forward":{"receiver":"0xaabbccdd","channel":"7","quote_token":"0x11223344","metadata":{"implementation":"0x0102","initializer":"0x0304"},"timeout":"5m"}}`
	m, err := parseZkgmMemo(raw)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if m.Core.Channel != "7" {
		t.Errorf("channel = %q, want 7", m.Core.Channel)
	}
	if m.ChannelID != 7 {
		t.Errorf("channelID = %d, want 7", m.ChannelID)
	}
	if m.Core.Receiver != "aabbccdd" {
		t.Errorf("receiver = %q, want aabbccdd", m.Core.Receiver)
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
	if m.Core.Timeout == 0 {
		t.Errorf("timeout = 0, want a resolved future UnixNano deadline")
	}
}
