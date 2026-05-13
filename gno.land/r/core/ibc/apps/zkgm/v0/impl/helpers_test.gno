package impl

import (
	"testing"

	"gno.land/p/nt/uassert/v0"

	z "gno.land/p/gnoswap/ibc/zkgm"
	u256 "gno.land/p/gnoswap/uint256"
)

func TestPredictWrappedTokenV2IncludesMetadataImage(t *testing.T) {
	metaA := MetadataImage(z.TokenMetadata{Implementation: []byte("impl-a"), Initializer: []byte("init")})
	metaB := MetadataImage(z.TokenMetadata{Implementation: []byte("impl-b"), Initializer: []byte("init")})

	wrappedA := PredictWrappedTokenV2(u256.Zero(), 0, []byte("ugnot"), metaA)
	wrappedB := PredictWrappedTokenV2(u256.Zero(), 0, []byte("ugnot"), metaB)

	uassert.True(t, len(wrappedA) > len("ibc/"))
	uassert.True(t, wrappedA != wrappedB)
}

func TestChannelBalanceKeyV2Stable(t *testing.T) {
	key := ChannelBalanceKeyV2("client-0", u256.NewUint(7), []byte("ugnot"), []byte("ibc/abc"))

	uassert.Equal(t, "client-0/7/75676e6f74/6962632f616263", key)
}

func TestParseCoinsRoundTripString(t *testing.T) {
	coins := parseCoins("12ugnot,3uatom")

	uassert.Equal(t, int64(12), coins.AmountOf("ugnot"))
	uassert.Equal(t, int64(3), coins.AmountOf("uatom"))
}

func TestPredictCallProxyAccountDeterministic(t *testing.T) {
	got := PredictCallProxyAccount(u256.NewUint(7), "client-b", []byte("sender"))
	again := PredictCallProxyAccount(u256.NewUint(7), "client-b", []byte("sender"))

	uassert.Equal(t, got, again)
	uassert.True(t, len(got) == len("zkgm1")+40)
}

func TestPredictCallProxyAccountInputSensitivity(t *testing.T) {
	base := PredictCallProxyAccount(u256.NewUint(7), "client-b", []byte("sender"))

	uassert.True(t, base != PredictCallProxyAccount(u256.NewUint(8), "client-b", []byte("sender")))
	uassert.True(t, base != PredictCallProxyAccount(u256.NewUint(7), "client-c", []byte("sender")))
	uassert.True(t, base != PredictCallProxyAccount(u256.NewUint(7), "client-b", []byte("other")))
}
