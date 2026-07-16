package ics20zkgm_adapter

import (
	"testing"

	"gno.land/p/nt/uassert/v0"
)

func TestParseForwardMemoEmptyIsNotAForward(t *testing.T) {
	_, ok := parseForwardMemo("")
	uassert.False(t, ok)
}

func TestParseForwardMemoMalformedJSONIsNotAForward(t *testing.T) {
	_, ok := parseForwardMemo("{not json")
	uassert.False(t, ok)
}

func TestParseForwardMemoUnrelatedJSONIsNotAForward(t *testing.T) {
	_, ok := parseForwardMemo(`{"wasm":{"contract":"g1..."}}`)
	uassert.False(t, ok)
}

func TestParseForwardMemoMissingReceiverIsNotAForward(t *testing.T) {
	_, ok := parseForwardMemo(`{"forward":{"timeout":"10m"}}`)
	uassert.False(t, ok)
}

func TestParseForwardMemoBlankReceiverIsNotAForward(t *testing.T) {
	_, ok := parseForwardMemo(`{"forward":{"receiver":""}}`)
	uassert.False(t, ok)
}

func TestParseForwardMemoMinimal(t *testing.T) {
	memo, ok := parseForwardMemo(`{"forward":{"receiver":"0xabc123"}}`)
	uassert.True(t, ok)
	uassert.Equal(t, "0xabc123", memo.Receiver)
	uassert.Equal(t, "", memo.Timeout)
}

// TestParseForwardMemoFullPFMShape verifies that a memo built with the full
// PFM {"forward": {...}} shape (matching AtomOne-side PFM tooling verbatim)
// parses every field onto the struct, even though only Receiver/Timeout are
// consumed by OnTransferRecv today.
func TestParseForwardMemoFullPFMShape(t *testing.T) {
	memo, ok := parseForwardMemo(`{"forward":{"receiver":"0xabc123","port":"transfer","channel":"channel-1","timeout":"10m","retries":2}}`)
	uassert.True(t, ok)
	uassert.Equal(t, "0xabc123", memo.Receiver)
	uassert.Equal(t, "transfer", memo.Port)
	uassert.Equal(t, "channel-1", memo.Channel)
	uassert.Equal(t, "10m", memo.Timeout)
	uassert.Equal(t, 2, memo.Retries)
}
