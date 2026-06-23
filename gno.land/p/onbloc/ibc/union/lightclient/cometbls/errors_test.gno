package cometbls

import "testing"

func TestMakeError(t *testing.T) {
	cases := []struct {
		name string
		msgs []string
		want string
	}{
		{
			name: "single message",
			msgs: []string{"error occurred"},
			want: "error occurred",
		},
		{
			name: "two messages",
			msgs: []string{"first", "second"},
			want: "first, second",
		},
		{
			name: "multiple messages",
			msgs: []string{"a", "b", "c", "d"},
			want: "a, b, c, d",
		},
		{
			name: "empty message",
			msgs: []string{""},
			want: "",
		},
		{
			name: "empty string among messages",
			msgs: []string{"start", "", "end"},
			want: "start, , end",
		},
		{
			name: "messages with comma",
			msgs: []string{"value: 1,2", "separator"},
			want: "value: 1,2, separator",
		},
		{
			name: "special characters",
			msgs: []string{"error: \n\t", "end"},
			want: "error: \n\t, end",
		},
		{
			name: "numeric values",
			msgs: []string{"height", "100"},
			want: "height, 100",
		},
		{
			name: "long message",
			msgs: []string{"a very long error message that contains many words and details"},
			want: "a very long error message that contains many words and details",
		},
		{
			name: "unicode characters",
			msgs: []string{"error: 日本語", "test"},
			want: "error: 日本語, test",
		},
		{
			name: "messages with spaces",
			msgs: []string{"  leading", "trailing  ", "  both  "},
			want: "  leading, trailing  ,   both  ",
		},
		{
			name: "all empty strings",
			msgs: []string{"", "", ""},
			want: ", , ",
		},
		{
			name: "single character messages",
			msgs: []string{"a", "b", "c"},
			want: "a, b, c",
		},
		{
			name: "messages with colon",
			msgs: []string{"field: value", "key: val"},
			want: "field: value, key: val",
		},
		{
			name: "mixed types",
			msgs: []string{"height", "12345", "invalid"},
			want: "height, 12345, invalid",
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got := makeError(tc.msgs...)
			if got == nil {
				t.Fatalf("makeError(%v): got nil, want error", tc.msgs)
			}
			if got.Error() != tc.want {
				t.Fatalf("makeError(%v): got %q want %q", tc.msgs, got.Error(), tc.want)
			}
		})
	}
}

func TestMakeErrorEmpty(t *testing.T) {
	cases := []struct {
		name string
		msgs []string
	}{
		{
			name: "no arguments",
			msgs: []string{},
		},
		{
			name: "nil slice",
			msgs: nil,
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got := makeError(tc.msgs...)
			if got == nil {
				t.Fatalf("makeError(%v): got nil, want error", tc.msgs)
			}
			// Empty slice/nil produces empty string join
			want := ""
			if got.Error() != want {
				t.Fatalf("makeError(%v): got %q want %q", tc.msgs, got.Error(), want)
			}
		})
	}
}

func TestMakeErrorWithSentinelConstants(t *testing.T) {
	// Verify makeError works with all declared sentinel error constants
	cases := []struct {
		name string
		msg  string
	}{
		{ErrInvalidChainID, "invalid chain-id"},
		{ErrInvalidHeight, "invalid height"},
		{ErrInvalidProof, "invalid proof"},
		{ErrInvalidConsensus, "invalid consensus state"},
		{ErrInvalidNextValidatorsHash, "invalid next validators hash"},
		{ErrInvalidTrustingPeriod, "invalid trusting period"},
		{ErrInvalidUnbondingPeriod, "invalid unbonding period"},
		{ErrInvalidHeaderHeight, "invalid header height"},
		{ErrInvalidMisbehaviour, "invalid misbehaviour"},
		{ErrInvalidHeader, "invalid header"},
		{ErrInvalidMaxClockDrift, "invalid max clock drift"},
		{ErrProcessedTimeNotFound, "processed time not found"},
		{ErrProcessedHeightNotFound, "processed height not found"},
		{ErrDelayPeriodNotPassed, "packet-specified delay period has not been reached"},
		{ErrTrustingPeriodExpired, "time since latest trusted state has passed the trusting period"},
		{ErrUnbondingPeriodExpired, "time since latest trusted state has passed the unbonding period"},
		{ErrInvalidProofSpecs, "invalid proof specs"},
		{ErrInvalidValidatorSet, "invalid validator set"},
		{ErrInvalidHeaderTimestamp, "invalid header timestamp"},
		{ErrInvalidMisbehaviourHeaderSequence, "invalid misbehaviour header sequence"},
		{ErrMathOverflow, "math operation with overflow"},
		{ErrMisbehaviourNotFound, "misbehaviour not found"},
	}

	for _, tc := range cases {
		t.Run(tc.msg, func(t *testing.T) {
			got := makeError(tc.msg)
			if got == nil {
				t.Fatalf("makeError(%q): got nil, want error", tc.msg)
			}
			if got.Error() != tc.msg {
				t.Fatalf("makeError(%q): got %q want %q", tc.msg, got.Error(), tc.msg)
			}
		})
	}
}

func TestMakeErrorWithSentinelAndContext(t *testing.T) {
	cases := []struct {
		name     string
		sentinel string
		context  []string
		want     string
	}{
		{
			name:     "chain ID with value",
			sentinel: ErrInvalidChainID,
			context:  []string{"got: test-chain"},
			want:     "invalid chain-id, got: test-chain",
		},
		{
			name:     "height with values",
			sentinel: ErrInvalidHeight,
			context:  []string{"got: 100", "want: 101"},
			want:     "invalid height, got: 100, want: 101",
		},
		{
			name:     "proof with context",
			sentinel: ErrInvalidProof,
			context:  []string{"proof operation failed"},
			want:     "invalid proof, proof operation failed",
		},
		{
			name:     "overflow with context",
			sentinel: ErrMathOverflow,
			context:  []string{"addition exceeded uint64"},
			want:     "math operation with overflow, addition exceeded uint64",
		},
		{
			name:     "timestamp not found with key",
			sentinel: ErrProcessedTimeNotFound,
			context:  []string{"connection-id-1"},
			want:     "processed time not found, connection-id-1",
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			msgs := append([]string{tc.sentinel}, tc.context...)
			got := makeError(msgs...)
			if got == nil {
				t.Fatalf("makeError(%v): got nil, want error", msgs)
			}
			if got.Error() != tc.want {
				t.Fatalf("makeError(%v): got %q want %q", msgs, got.Error(), tc.want)
			}
		})
	}
}
