package v1

import (
	"strings"
	"testing"

	types "gno.land/p/onbloc/ibc/union/types"

	u256 "gno.land/p/gnoswap/uint256"
	"gno.land/p/nt/uassert/v0"
	z "gno.land/p/onbloc/ibc/union/zkgm"
)

func TestMetadataImage(t *testing.T) {
	meta := z.TokenMetadata{
		Implementation: []byte("\xaf\x73\x9f\x34\xdd\xf9\x51\xcb\xc2\x4f\xdb\xba\x4f\x76\x21\x36\x88\xe1\x36\x27"),
		Initializer:    []byte("init"),
	}
	ref := z.MetadataImage(meta)

	uassert.True(t, ref == z.MetadataImage(meta))
	uassert.False(t, ref == z.MetadataImage(z.TokenMetadata{
		Implementation: []byte("\xaf\x73\x9f\x34\xdd\xf9\x51\xcb\xc2\x4f\xdb\xba\x4f\x76\x21\x36\x88\xe1\x36\x27"),
		Initializer:    []byte("init-2"),
	}))
}

// PredictWrappedToken is a pure keccak derivation: deterministic, ibc-prefixed,
// and distinct for any change of path, channel, or base token. A nil path must
// normalise to zero so callers cannot derive two denoms for the same order.
func TestPredictWrappedToken(t *testing.T) {
	ref := z.PredictWrappedToken(u256.Zero(), 1, []byte("uatom"))

	uassert.True(t, strings.HasPrefix(ref, ibcDenomPrefix))
	uassert.Equal(t, ref, z.PredictWrappedToken(u256.Zero(), 1, []byte("uatom")))
	uassert.Equal(t, ref, z.PredictWrappedToken(nil, 1, []byte("uatom"))) // nil path == zero path

	cases := []struct {
		name  string
		denom string
	}{
		{"different path", z.PredictWrappedToken(u256.NewUint(1), 1, []byte("uatom"))},
		{"different channel", z.PredictWrappedToken(u256.Zero(), 2, []byte("uatom"))},
		{"different base token", z.PredictWrappedToken(u256.Zero(), 1, []byte("uosmo"))},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			uassert.NotEqual(t, ref, tc.denom)
		})
	}
}

// PredictWrappedTokenV2 additionally binds the metadata image and must differ
// from the legacy derivation for the same order.
func TestPredictWrappedTokenV2(t *testing.T) {
	ref := z.PredictWrappedTokenV2(u256.Zero(), 1, []byte("uatom"), [32]byte{})

	uassert.True(t, strings.HasPrefix(ref, ibcDenomPrefix))
	uassert.Equal(t, ref, z.PredictWrappedTokenV2(nil, 1, []byte("uatom"), [32]byte{}))
	uassert.NotEqual(t, ref, z.PredictWrappedToken(u256.Zero(), 1, []byte("uatom")))

	cases := []struct {
		name  string
		denom string
	}{
		{"different image", z.PredictWrappedTokenV2(u256.Zero(), 1, []byte("uatom"), [32]byte{0x01})},
		{"different path", z.PredictWrappedTokenV2(u256.NewUint(1), 1, []byte("uatom"), [32]byte{})},
		{"different channel", z.PredictWrappedTokenV2(u256.Zero(), 2, []byte("uatom"), [32]byte{})},
		{"different base token", z.PredictWrappedTokenV2(u256.Zero(), 1, []byte("uosmo"), [32]byte{})},
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
	ref := z.PredictCallProxyAccount(u256.NewUint(9), types.ChannelId(8), []byte("sender"))

	uassert.True(t, strings.HasPrefix(ref, "zkgm1"))
	uassert.Equal(t, ref, z.PredictCallProxyAccount(u256.NewUint(9), types.ChannelId(8), []byte("sender")))

	cases := []struct {
		name string
		acct string
	}{
		{"different path", z.PredictCallProxyAccount(u256.NewUint(10), types.ChannelId(8), []byte("sender"))},
		{"different channel", z.PredictCallProxyAccount(u256.NewUint(9), types.ChannelId(7), []byte("sender"))},
		{"different sender", z.PredictCallProxyAccount(u256.NewUint(9), types.ChannelId(8), []byte("sender-b"))},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			uassert.NotEqual(t, ref, tc.acct)
		})
	}
}
