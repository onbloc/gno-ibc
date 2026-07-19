package ics20zkgm_adapter

import (
	"testing"

	types "gno.land/p/onbloc/ibc/union/types"

	"gno.land/p/nt/uassert/v0"
	z "gno.land/p/onbloc/ibc/union/zkgm"
	"gno.land/r/onbloc/ibc/union/access"
)

func testTokenMetadata(t *testing.T, decimals uint8) []byte {
	initializer, err := z.EncodeTokenInitializer(z.TokenInitializer{
		Name:     "Test Token",
		Symbol:   "TEST",
		Decimals: decimals,
	})
	if err != nil {
		t.Fatalf("encode initializer: %v", err)
	}

	metadata, err := z.EncodeTokenMetadata(z.TokenMetadata{
		Implementation: []byte("grc20"),
		Initializer:    initializer,
	})
	if err != nil {
		t.Fatalf("encode metadata: %v", err)
	}

	return metadata
}

func TestRegisterDenomRejectsNonZeroMetadataDecimals(cur realm, t *testing.T) {
	cfg := NewDenomConfig(types.ChannelId(1), []byte("quote-token"), testTokenMetadata(t, 6))

	uassert.AbortsContains(t, cur, "metadata decimals must be 0, got 6", func(cur realm) {
		testing.SetRealm(testing.NewUserRealm(access.DefaultAdminAddress))
		RegisterDenom(cross(cur), "uatom-baddecimals", cfg)
	})

	_, found := GetDenomConfig("uatom-baddecimals")
	uassert.False(t, found)
}

func TestRegisterDenomAcceptsZeroMetadataDecimals(cur realm, t *testing.T) {
	cfg := NewDenomConfig(types.ChannelId(1), []byte("quote-token"), testTokenMetadata(t, 0))

	testing.SetRealm(testing.NewUserRealm(access.DefaultAdminAddress))
	RegisterDenom(cross(cur), "uatom-gooddecimals", cfg)

	got, found := GetDenomConfig("uatom-gooddecimals")
	uassert.True(t, found)
	uassert.Equal(t, uint32(1), uint32(got.ZkgmChannelId))
}
