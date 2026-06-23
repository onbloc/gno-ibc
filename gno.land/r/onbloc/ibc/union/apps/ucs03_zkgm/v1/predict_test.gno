package impl

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
		Implementation: []byte("grc20"),
		Initializer:    []byte("init"),
	}
	ref := MetadataImage(meta)

	uassert.True(t, ref == MetadataImage(meta))
	uassert.False(t, ref == MetadataImage(z.TokenMetadata{
		Implementation: []byte("grc20"),
		Initializer:    []byte("init-2"),
	}))
	uassert.True(t, z.MetadataImage(meta) == ref)
}

func TestU256FromBytes32(t *testing.T) {
	cases := []struct {
		name string
		bz   [32]byte
		want string
	}{
		{"zero", [32]byte{}, "0"},
		{"low byte", [32]byte{31: 0x2A}, "42"},
		{"big endian", [32]byte{30: 0x01, 31: 0x00}, "256"},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			uassert.Equal(t, tc.want, u256FromBytes32(tc.bz).ToString())
		})
	}
}

// PredictWrappedToken is a pure keccak derivation: deterministic, ibc-prefixed,
// and distinct for any change of path, channel, or base token. A nil path must
// normalise to zero so callers cannot derive two denoms for the same order.
func TestPredictWrappedToken(t *testing.T) {
	ref := PredictWrappedToken(u256.Zero(), 1, []byte("uatom"))

	uassert.True(t, strings.HasPrefix(ref, ibcDenomPrefix))
	uassert.Equal(t, ref, PredictWrappedToken(u256.Zero(), 1, []byte("uatom")))
	uassert.Equal(t, ref, PredictWrappedToken(nil, 1, []byte("uatom"))) // nil path == zero path

	cases := []struct {
		name  string
		denom string
	}{
		{"different path", PredictWrappedToken(u256.NewUint(1), 1, []byte("uatom"))},
		{"different channel", PredictWrappedToken(u256.Zero(), 2, []byte("uatom"))},
		{"different base token", PredictWrappedToken(u256.Zero(), 1, []byte("uosmo"))},
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
	ref := PredictWrappedTokenV2(u256.Zero(), 1, []byte("uatom"), [32]byte{})

	uassert.True(t, strings.HasPrefix(ref, ibcDenomPrefix))
	uassert.Equal(t, ref, PredictWrappedTokenV2(nil, 1, []byte("uatom"), [32]byte{}))
	uassert.NotEqual(t, ref, PredictWrappedToken(u256.Zero(), 1, []byte("uatom")))

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
