package impl

import (
	"testing"

	"gno.land/p/nt/uassert/v0"
)

func TestSanitizeGRC20Symbol(t *testing.T) {
	ibcDenom := ibcDenomPrefix + "abcdef123456"

	tests := []struct {
		name      string
		candidate string
		want      string
	}{
		{
			name:      "valid ascii passes through",
			candidate: "USDC",
			want:      "USDC",
		},
		{
			name:      "truncated to 11 chars",
			candidate: "ABCDEFGHIJKLMNOP",
			want:      "ABCDEFGHIJK",
		},
		{
			name:      "invalid chars stripped",
			candidate: "US@D#C!",
			want:      "USDC",
		},
		{
			name:      "truncation after stripping mixed valid and invalid",
			candidate: "AB@CD#EF$GH%IJ^KL",
			want:      "ABCDEFGHIJK",
		},
		{
			name:      "all invalid chars falls back to ibcDenom suffix",
			candidate: "@#$%^&*()",
			want:      "abcdef12345",
		},
		{
			name:      "empty string falls back to ibcDenom suffix",
			candidate: "",
			want:      "abcdef12345",
		},
		{
			name:      "underscore and dash are valid",
			candidate: "my_token-v2",
			want:      "my_token-v2",
		},
		{
			name:      "unicode multi-byte chars are filtered (bytes ≥ 128 never match ASCII ranges)",
			candidate: "USD€coin",
			want:      "USDcoin",
		},
		{
			name:      "unicode-only input falls back to ibcDenom suffix",
			candidate: "한글심볼",
			want:      "abcdef12345",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := sanitizeGRC20Symbol(tt.candidate, ibcDenom)
			uassert.Equal(t, tt.want, got)
		})
	}
}
