package voyager

import (
	"errors"
	"testing"
)

func TestDecodeStateResponseRejectsMalformedOutput(t *testing.T) {
	for _, tc := range []struct {
		input string
		want  error
	}{
		{`not-json`, ErrMalformedResponse},
		{`{}`, ErrMalformedResponse},
		{`{"state":null}`, ErrNotFound},
	} {
		_, err := decodeStateResponse([]byte(tc.input))
		if !errors.Is(err, tc.want) {
			t.Fatalf("decodeStateResponse(%q) error = %v, want %v", tc.input, err, tc.want)
		}
	}
}

func TestJSONIDRejectsMalformedOutput(t *testing.T) {
	for _, input := range []string{`"nope"`, `-1`, `{}`} {
		var id jsonID
		if err := id.UnmarshalJSON([]byte(input)); !errors.Is(err, ErrMalformedResponse) {
			t.Fatalf("UnmarshalJSON(%q) error = %v", input, err)
		}
	}
}
