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

func TestMetadataImageEmptyFieldsDeterministic(t *testing.T) {
	meta := TokenMetadata{}

	a := MetadataImage(meta)
	b := MetadataImage(meta)
	if a != b {
		t.Fatal("MetadataImage changed for the same empty metadata")
	}
}

func TestPredictWrappedTokenInputSensitivity(t *testing.T) {
	base := []byte("ugnot")
	path := u256.NewUint(5)
	baseDenom := PredictWrappedToken(path, 7, base)

	tests := []struct {
		name      string
		path      *u256.Uint
		channel   uint32
		base      []byte
		sameAsBase bool
	}{
		{"path change", u256.NewUint(6), 7, base, false},
		{"channel change", path, 8, base, false},
		{"base change", path, 7, []byte("uatom"), false},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := PredictWrappedToken(tt.path, tt.channel, tt.base)
			if tt.sameAsBase {
				if got != baseDenom {
					t.Fatalf("expected same as base, got %q", got)
				}
			} else {
				if got == baseDenom {
					t.Fatalf("expected change from base, got same")
				}
			}
		})
	}
}

func TestPredictWrappedTokenV2InputSensitivity(t *testing.T) {
	path := u256.NewUint(5)
	base := []byte("ugnot")
	image := MetadataImage(TokenMetadata{
		Implementation: []byte("grc20"),
		Initializer:    []byte("init-a"),
	})
	baseDenom := PredictWrappedTokenV2(path, 7, base, image)

	otherImage := MetadataImage(TokenMetadata{
		Implementation: []byte("grc20"),
		Initializer:    []byte("init-b"),
	})

	tests := []struct {
		name   string
		path   *u256.Uint
		channel uint32
		base   []byte
		image  [32]byte
		sameAsBase bool
	}{
		{"path change", u256.NewUint(6), 7, base, image, false},
		{"channel change", path, 8, base, image, false},
		{"base change", path, 7, []byte("uatom"), image, false},
		{"image change", path, 7, base, otherImage, false},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := PredictWrappedTokenV2(tt.path, tt.channel, tt.base, tt.image)
			if got == baseDenom {
				t.Fatalf("expected change from base, got same")
			}
		})
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

func TestUint256FromBytes32(t *testing.T) {
	var zero [32]byte

	var one [32]byte
	one[31] = 1

	var bigEndian [32]byte
	bigEndian[30] = 1
	bigEndian[31] = 2

	var highBit [32]byte
	highBit[0] = 0x80

	var max [32]byte
	for i := 0; i < len(max); i++ {
		max[i] = 0xff
	}

	tests := []struct {
		name  string
		input [32]byte
		want  string
	}{
		{"zero", zero, "0"},
		{"one", one, "1"},
		{"big endian", bigEndian, "258"},
		{"high bit", highBit, "57896044618658097711785492504343953926634992332820282019728792003956564819968"},
		{"max", max, "115792089237316195423570985008687907853269984665640564039457584007913129639935"},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			assertUint256String(t, tt.name, Uint256FromBytes32(tt.input), tt.want)
		})
	}
}

func assertIBCDenom(t *testing.T, got string) {
	t.Helper()

	if !strings.HasPrefix(got, "ibc/") || len(got) != len("ibc/")+40 {
		t.Fatalf("predicted denom: got %q, want ibc/<20-byte-hex>", got)
	}
}

func assertUint256String(t *testing.T, name string, got *u256.Uint, want string) {
	t.Helper()

	if got.ToString() != want {
		t.Fatalf("%s: got %s want %s", name, got.ToString(), want)
	}
}
