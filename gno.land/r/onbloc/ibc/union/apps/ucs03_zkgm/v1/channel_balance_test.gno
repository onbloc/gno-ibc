package impl

import (
	"testing"

	types "gno.land/p/onbloc/ibc/union/types"

	u256 "gno.land/p/gnoswap/uint256"
	"gno.land/p/nt/uassert/v0"
	zkgm "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm"
)

func TestIncreaseChannelBalanceSingleWrite(cur realm, t *testing.T) {
	baseToken := []byte("uatom-single")
	quoteToken := []byte("uosmo")
	path := u256.Zero()
	chanId := types.ChannelId(21)

	increaseChannelBalanceV2(cross(cur), chanId, path, baseToken, quoteToken, u256.NewUint(500))

	key := ChannelBalanceKeyV2(chanId, path, baseToken, quoteToken)
	bal := zkgm.GetChannelBalanceV2(key)
	uassert.True(t, bal != nil && bal.Uint64() == 500)
}

func TestIncreaseChannelBalanceZeroIsNoop(cur realm, t *testing.T) {
	baseToken := []byte("uatom-zero-noop")
	quoteToken := []byte("uosmo")
	path := u256.Zero()
	chanId := types.ChannelId(22)

	increaseChannelBalanceV2(cross(cur), chanId, path, baseToken, quoteToken, u256.Zero())

	key := ChannelBalanceKeyV2(chanId, path, baseToken, quoteToken)
	bal := zkgm.GetChannelBalanceV2(key)
	uassert.True(t, bal == nil)
}

func TestDecreaseChannelBalanceUnderflowOnEmpty(cur realm, t *testing.T) {
	baseToken := []byte("uatom-underflow")
	quoteToken := []byte("uosmo")
	path := u256.Zero()
	chanId := types.ChannelId(23)

	err := decreaseChannelBalanceV2(cross(cur), chanId, path, baseToken, quoteToken, u256.NewUint(1))
	uassert.Error(t, err)
}

func TestDecreaseChannelBalanceZeroIsNoop(cur realm, t *testing.T) {
	baseToken := []byte("uatom-dec-zero")
	quoteToken := []byte("uosmo")
	path := u256.Zero()
	chanId := types.ChannelId(24)

	err := decreaseChannelBalanceV2(cross(cur), chanId, path, baseToken, quoteToken, u256.Zero())
	uassert.NoError(t, err)

	key := ChannelBalanceKeyV2(chanId, path, baseToken, quoteToken)
	bal := zkgm.GetChannelBalanceV2(key)
	uassert.True(t, bal == nil)
}

func TestChannelBalanceKeyV2Deterministic(t *testing.T) {
	chanId := types.ChannelId(1)
	path := u256.NewUint(42)
	base := []byte("uatom")
	quote := []byte("uosmo")

	k1 := ChannelBalanceKeyV2(chanId, path, base, quote)
	k2 := ChannelBalanceKeyV2(chanId, path, base, quote)
	uassert.Equal(t, k1, k2)
}

func TestChannelBalanceKeyV2DifferentChannels(t *testing.T) {
	path := u256.Zero()
	base := []byte("uatom")
	quote := []byte("uosmo")

	k1 := ChannelBalanceKeyV2(types.ChannelId(1), path, base, quote)
	k2 := ChannelBalanceKeyV2(types.ChannelId(2), path, base, quote)
	if k1 == k2 {
		t.Fatal("different channel IDs produced the same key")
	}
}

func TestChannelBalanceKeyV2DifferentPaths(t *testing.T) {
	chanId := types.ChannelId(1)
	base := []byte("uatom")
	quote := []byte("uosmo")

	k1 := ChannelBalanceKeyV2(chanId, u256.NewUint(1), base, quote)
	k2 := ChannelBalanceKeyV2(chanId, u256.NewUint(2), base, quote)
	if k1 == k2 {
		t.Fatal("different paths produced the same key")
	}
}

func TestChannelBalanceKeyV2DifferentBaseTokens(t *testing.T) {
	chanId := types.ChannelId(1)
	path := u256.Zero()
	quote := []byte("uosmo")

	k1 := ChannelBalanceKeyV2(chanId, path, []byte("uatom"), quote)
	k2 := ChannelBalanceKeyV2(chanId, path, []byte("uosmo"), quote)
	if k1 == k2 {
		t.Fatal("different base tokens produced the same key")
	}
}

func TestChannelBalanceKeyV2DifferentQuoteTokens(t *testing.T) {
	chanId := types.ChannelId(1)
	path := u256.Zero()
	base := []byte("uatom")

	k1 := ChannelBalanceKeyV2(chanId, path, base, []byte("uosmo"))
	k2 := ChannelBalanceKeyV2(chanId, path, base, []byte("uatom"))
	if k1 == k2 {
		t.Fatal("different quote tokens produced the same key")
	}
}
