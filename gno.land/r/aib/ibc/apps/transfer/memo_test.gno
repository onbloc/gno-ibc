package transfer

import (
	"testing"

	"gno.land/p/nt/uassert/v0"
)

func TestParseForwardMemo(t *testing.T) {
	validMemo := `{"forward":{"channel":5,"receiver":"0xabc","quote_token":"0xdef","metadata":{"implementation":"0x01","initializer":"0x02"}}}`

	cases := []struct {
		name   string
		memo   string
		wantOK bool
	}{
		{"empty memo", "", false},
		{"not json", "not json", false},
		{"no forward key", `{"other":"value"}`, false},
		{"missing receiver", `{"forward":{"channel":5,"quote_token":"0xdef","metadata":{"implementation":"0x01","initializer":"0x02"}}}`, false},
		{"missing channel", `{"forward":{"receiver":"0xabc","quote_token":"0xdef","metadata":{"implementation":"0x01","initializer":"0x02"}}}`, false},
		{"missing quote_token", `{"forward":{"channel":5,"receiver":"0xabc","metadata":{"implementation":"0x01","initializer":"0x02"}}}`, false},
		{"missing metadata", `{"forward":{"channel":5,"receiver":"0xabc","quote_token":"0xdef"}}`, false},
		{"missing metadata.initializer", `{"forward":{"channel":5,"receiver":"0xabc","quote_token":"0xdef","metadata":{"implementation":"0x01"}}}`, false},
		{"valid minimal", validMemo, true},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			_, ok := parseForwardMemo(tc.memo)
			uassert.Equal(t, tc.wantOK, ok)
		})
	}
}

func TestParseForwardMemoFields(t *testing.T) {
	memo, ok := parseForwardMemo(`{"forward":{"channel":7,"receiver":"0xabc","quote_token":"0xdef","kind":2,"timeout_timestamp":123456789,"metadata":{"implementation":"0x01","initializer":"0x02"}}}`)

	uassert.True(t, ok)
	uassert.Equal(t, uint32(7), memo.Channel)
	uassert.Equal(t, "0xabc", memo.Receiver)
	uassert.Equal(t, "0xdef", memo.QuoteToken)
	uassert.Equal(t, uint8(2), memo.Kind)
	uassert.Equal(t, uint64(123456789), memo.TimeoutTimestamp)
	uassert.Equal(t, "0x01", memo.Metadata.Implementation)
	uassert.Equal(t, "0x02", memo.Metadata.Initializer)
}

func TestParseForwardMemoDefaultKind(t *testing.T) {
	memo, ok := parseForwardMemo(`{"forward":{"channel":7,"receiver":"0xabc","quote_token":"0xdef","metadata":{"implementation":"0x01","initializer":"0x02"}}}`)

	uassert.True(t, ok)
	uassert.Equal(t, uint8(0), memo.Kind) // TOKEN_ORDER_KIND_INITIALIZE
}
