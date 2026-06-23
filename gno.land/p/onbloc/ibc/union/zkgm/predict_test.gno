package zkgm

import (
	"strings"
	"testing"

	u256 "gno.land/p/gnoswap/uint256"
	types "gno.land/p/onbloc/ibc/union/types"
)

func TestPredictWrappedToken(t *testing.T) {
	base := []byte("ugnot")

	v1Zero := PredictWrappedToken(u256.Zero(), 7, base)
	path := u256.NewUint(5)
	baseDenom := PredictWrappedToken(path, 7, base)

	tests := []struct {
		name             string
		path             *u256.Uint
		channel          uint32
		base             []byte
		want             string
		wantIBCDenom     bool
		wantDiffFromBase bool
	}{
		{"nil path equals zero", nil, 7, base, v1Zero, true, false},
		{"path change", u256.NewUint(6), 7, base, "", false, true},
		{"channel change", path, 8, base, "", false, true},
		{"base change", path, 7, []byte("uatom"), "", false, true},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := PredictWrappedToken(tt.path, tt.channel, tt.base)
			if tt.want != "" && got != tt.want {
				t.Fatalf("got %q want %q", got, tt.want)
			}
			if tt.wantIBCDenom {
				assertIBCDenom(t, got)
			}
			if tt.wantDiffFromBase && got == baseDenom {
				t.Fatalf("expected change from base, got same")
			}
		})
	}
}

func TestPredictWrappedTokenV2(t *testing.T) {
	path := u256.NewUint(5)
	base := []byte("ugnot")
	image := MetadataImage(TokenMetadata{
		Implementation: []byte("grc20"),
		Initializer:    []byte("init-a"),
	})

	v2Zero := PredictWrappedTokenV2(u256.Zero(), 7, base, image)
	baseDenom := PredictWrappedTokenV2(path, 7, base, image)

	otherImage := MetadataImage(TokenMetadata{
		Implementation: []byte("grc20"),
		Initializer:    []byte("init-b"),
	})

	tests := []struct {
		name             string
		path             *u256.Uint
		channel          uint32
		base             []byte
		image            [32]byte
		want             string
		wantIBCDenom     bool
		wantDiffFromBase bool
	}{
		{"nil path equals zero", nil, 7, base, image, v2Zero, true, false},
		{"path change", u256.NewUint(6), 7, base, image, "", false, true},
		{"channel change", path, 8, base, image, "", false, true},
		{"base change", path, 7, []byte("uatom"), image, "", false, true},
		{"image change", path, 7, base, otherImage, "", false, true},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := PredictWrappedTokenV2(tt.path, tt.channel, tt.base, tt.image)
			if tt.want != "" && got != tt.want {
				t.Fatalf("got %q want %q", got, tt.want)
			}
			if tt.wantIBCDenom {
				assertIBCDenom(t, got)
			}
			if tt.wantDiffFromBase && got == baseDenom {
				t.Fatalf("expected change from base, got same")
			}
		})
	}
}

func TestMetadataImage(t *testing.T) {
	tests := []struct {
		name string
		a    TokenMetadata
		b    TokenMetadata
		same bool
	}{
		{
			"changes with metadata",
			TokenMetadata{Implementation: []byte("grc20"), Initializer: []byte("init-a")},
			TokenMetadata{Implementation: []byte("grc20"), Initializer: []byte("init-b")},
			false,
		},
		{
			"empty fields deterministic",
			TokenMetadata{},
			TokenMetadata{},
			true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			a := MetadataImage(tt.a)
			b := MetadataImage(tt.b)
			if (a == b) != tt.same {
				t.Fatalf("same image: got %t want %t", a == b, tt.same)
			}
		})
	}
}

func TestPredictCallProxyAccount(t *testing.T) {
	path := u256.NewUint(5)
	a := PredictCallProxyAccount(path, types.ChannelId(8), []byte("sender"))
	b := PredictCallProxyAccount(path, types.ChannelId(8), []byte("sender"))
	c := PredictCallProxyAccount(path, types.ChannelId(9), []byte("sender"))
	zero := PredictCallProxyAccount(u256.Zero(), types.ChannelId(8), []byte("sender"))
	nilPath := PredictCallProxyAccount(nil, types.ChannelId(8), []byte("sender"))

	tests := []struct {
		name        string
		got         string
		other       string
		wantEqual   bool
		wantAddress bool
	}{
		{"deterministic", a, b, true, false},
		{"channel change", a, c, false, false},
		{"nil path equals zero", nilPath, zero, true, false},
		{"address shape", a, "", false, true},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			if tt.other != "" && (tt.got == tt.other) != tt.wantEqual {
				t.Fatalf("equal: got %t want %t", tt.got == tt.other, tt.wantEqual)
			}
			if tt.wantAddress && (!strings.HasPrefix(tt.got, "zkgm1") || len(tt.got) != len("zkgm1")+40) {
				t.Fatalf("PredictCallProxyAccount: unexpected address %q", tt.got)
			}
		})
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
