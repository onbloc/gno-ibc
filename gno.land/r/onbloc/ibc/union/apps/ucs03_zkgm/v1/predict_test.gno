package impl

import (
	"strings"
	"testing"

	types "gno.land/p/onbloc/ibc/union/types"

	u256 "gno.land/p/gnoswap/uint256"
	"gno.land/p/nt/uassert/v0"
)

// PredictWrappedTokenV1 is a pure keccak derivation: deterministic, ibc-prefixed,
// and distinct for any change of path, channel, or base token. A nil path must
// normalise to zero so callers cannot derive two denoms for the same order.
func TestPredictWrappedTokenV1(t *testing.T) {
	ref := PredictWrappedTokenV1(u256.Zero(), 1, []byte("uatom"))

	uassert.True(t, strings.HasPrefix(ref, ibcDenomPrefix))
	uassert.Equal(t, ref, PredictWrappedTokenV1(u256.Zero(), 1, []byte("uatom")))
	uassert.Equal(t, ref, PredictWrappedTokenV1(nil, 1, []byte("uatom"))) // nil path == zero path

	cases := []struct {
		name  string
		denom string
	}{
		{"different path", PredictWrappedTokenV1(u256.NewUint(1), 1, []byte("uatom"))},
		{"different channel", PredictWrappedTokenV1(u256.Zero(), 2, []byte("uatom"))},
		{"different base token", PredictWrappedTokenV1(u256.Zero(), 1, []byte("uosmo"))},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			uassert.NotEqual(t, ref, tc.denom)
		})
	}
}

// PredictWrappedTokenV2 additionally binds the metadata image and must differ
// from the V1 derivation for the same order.
func TestPredictWrappedTokenV2(t *testing.T) {
	ref := PredictWrappedTokenV2(u256.Zero(), 1, []byte("uatom"), [32]byte{})

	uassert.True(t, strings.HasPrefix(ref, ibcDenomPrefix))
	uassert.Equal(t, ref, PredictWrappedTokenV2(nil, 1, []byte("uatom"), [32]byte{}))
	uassert.NotEqual(t, ref, PredictWrappedTokenV1(u256.Zero(), 1, []byte("uatom")))

	cases := []struct {
		name  string
		denom string
	}{
		{"different image", PredictWrappedTokenV2(u256.Zero(), 1, []byte("uatom"), [32]byte{0x01})},
		{"different path", PredictWrappedTokenV2(u256.NewUint(1), 1, []byte("uatom"), [32]byte{})},
		{"different channel", PredictWrappedTokenV2(u256.Zero(), 2, []byte("uatom"), [32]byte{})},
		{"different base token", PredictWrappedTokenV2(u256.Zero(), 1, []byte("uosmo"), [32]byte{})},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			uassert.NotEqual(t, ref, tc.denom)
		})
	}
}

// PredictCallProxyAccount derives the synthetic zkgm1 account from (path,
// channel, sender); a change in any component yields a distinct account.
func TestPredictCallProxyAccount(t *testing.T) {
	ref := PredictCallProxyAccount(u256.NewUint(9), types.ChannelId(8), []byte("sender"))

	uassert.True(t, strings.HasPrefix(ref, "zkgm1"))
	uassert.Equal(t, ref, PredictCallProxyAccount(u256.NewUint(9), types.ChannelId(8), []byte("sender")))

	cases := []struct {
		name string
		acct string
	}{
		{"different path", PredictCallProxyAccount(u256.NewUint(10), types.ChannelId(8), []byte("sender"))},
		{"different channel", PredictCallProxyAccount(u256.NewUint(9), types.ChannelId(7), []byte("sender"))},
		{"different sender", PredictCallProxyAccount(u256.NewUint(9), types.ChannelId(8), []byte("sender-b"))},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			uassert.NotEqual(t, ref, tc.acct)
		})
	}
}
