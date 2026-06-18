package zkgm

import (
	"strings"
	"testing"

	u256 "gno.land/p/gnoswap/uint256"
	types "gno.land/p/onbloc/ibc/union/types"
)

func TestPredictWrappedTokenNilPathMatchesZero(t *testing.T) {
	base := []byte("ugnot")
	image := MetadataImage(TokenMetadata{
		Implementation: []byte("grc20"),
		Initializer:    []byte("init"),
	})

	v1Nil := PredictWrappedToken(nil, 7, base)
	v1Zero := PredictWrappedToken(u256.Zero(), 7, base)
	if v1Nil != v1Zero {
		t.Fatalf("PredictWrappedToken nil path: got %q want %q", v1Nil, v1Zero)
	}

	v2Nil := PredictWrappedTokenV2(nil, 7, base, image)
	v2Zero := PredictWrappedTokenV2(u256.Zero(), 7, base, image)
	if v2Nil != v2Zero {
		t.Fatalf("PredictWrappedTokenV2 nil path: got %q want %q", v2Nil, v2Zero)
	}
	assertIBCDenom(t, v1Nil)
	assertIBCDenom(t, v2Nil)
}

func TestMetadataImageChangesWithMetadata(t *testing.T) {
	a := MetadataImage(TokenMetadata{
		Implementation: []byte("grc20"),
		Initializer:    []byte("init-a"),
	})
	b := MetadataImage(TokenMetadata{
		Implementation: []byte("grc20"),
		Initializer:    []byte("init-b"),
	})
	if a == b {
		t.Fatal("MetadataImage did not change when metadata changed")
	}
}

func TestPredictCallProxyAccountDeterministic(t *testing.T) {
	path := u256.NewUint(5)
	a := PredictCallProxyAccount(path, types.ChannelId(8), []byte("sender"))
	b := PredictCallProxyAccount(path, types.ChannelId(8), []byte("sender"))
	c := PredictCallProxyAccount(path, types.ChannelId(9), []byte("sender"))

	if a != b {
		t.Fatalf("PredictCallProxyAccount not deterministic: %q != %q", a, b)
	}
	if a == c {
		t.Fatal("PredictCallProxyAccount did not change when channel changed")
	}
	if !strings.HasPrefix(a, "zkgm1") || len(a) != len("zkgm1")+40 {
		t.Fatalf("PredictCallProxyAccount: unexpected address %q", a)
	}
}

func assertIBCDenom(t *testing.T, got string) {
	t.Helper()

	if !strings.HasPrefix(got, "ibc/") || len(got) != len("ibc/")+40 {
		t.Fatalf("predicted denom: got %q, want ibc/<20-byte-hex>", got)
	}
}
