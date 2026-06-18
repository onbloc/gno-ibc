package impl

import (
	"testing"

	types "gno.land/p/onbloc/ibc/union/types"

	u256 "gno.land/p/gnoswap/uint256"
	"gno.land/p/nt/uassert/v0"
)

func TestPredictWrappedTokenV1Deterministic(t *testing.T) {
	a := PredictWrappedTokenV1(u256.Zero(), 1, []byte("uatom"))
	b := PredictWrappedTokenV1(u256.Zero(), 1, []byte("uatom"))
	uassert.Equal(t, a, b)
	uassert.Equal(t, ibcDenomPrefix, a[:len(ibcDenomPrefix)])
}

func TestPredictWrappedTokenV1DiffersByChannel(t *testing.T) {
	a := PredictWrappedTokenV1(u256.Zero(), 1, []byte("uatom"))
	b := PredictWrappedTokenV1(u256.Zero(), 2, []byte("uatom"))
	uassert.True(t, a != b)
}

func TestPredictWrappedTokenV1DiffersByBaseToken(t *testing.T) {
	a := PredictWrappedTokenV1(u256.Zero(), 1, []byte("uatom"))
	b := PredictWrappedTokenV1(u256.Zero(), 1, []byte("uosmo"))
	uassert.True(t, a != b)
}

func TestPredictWrappedTokenV2DiffersByImage(t *testing.T) {
	a := PredictWrappedTokenV2(u256.Zero(), 1, []byte("uatom"), [32]byte{})
	b := PredictWrappedTokenV2(u256.Zero(), 1, []byte("uatom"), [32]byte{0x01})
	uassert.True(t, a != b)
}

func TestPredictWrappedTokenV1AndV2Differ(t *testing.T) {
	v1 := PredictWrappedTokenV1(u256.Zero(), 1, []byte("uatom"))
	v2 := PredictWrappedTokenV2(u256.Zero(), 1, []byte("uatom"), [32]byte{})
	uassert.True(t, v1 != v2)
}

func TestPredictCallProxyAccountDeterministic(t *testing.T) {
	a := PredictCallProxyAccount(u256.NewUint(9), types.ChannelId(8), []byte("sender"))
	b := PredictCallProxyAccount(u256.NewUint(9), types.ChannelId(8), []byte("sender"))
	uassert.Equal(t, a, b)
	uassert.Equal(t, "zkgm1", a[:5])
}

func TestPredictCallProxyAccountDiffersBySender(t *testing.T) {
	a := PredictCallProxyAccount(u256.NewUint(9), types.ChannelId(8), []byte("sender-a"))
	b := PredictCallProxyAccount(u256.NewUint(9), types.ChannelId(8), []byte("sender-b"))
	uassert.True(t, a != b)
}

func TestPredictCallProxyAccountDiffersByChannel(t *testing.T) {
	a := PredictCallProxyAccount(u256.NewUint(9), types.ChannelId(8), []byte("sender"))
	b := PredictCallProxyAccount(u256.NewUint(9), types.ChannelId(7), []byte("sender"))
	uassert.True(t, a != b)
}
