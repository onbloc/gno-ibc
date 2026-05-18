package impl

import (
	"chain"
	"chain/banker"
	"testing"

	z "gno.land/p/gnoswap/ibc/zkgm"
	u256 "gno.land/p/gnoswap/uint256"
	"gno.land/p/nt/uassert/v0"
	core "gno.land/r/core/ibc/v1/core"
	zkgm "gno.land/r/gnoswap/ibc/v1/apps/zkgm"
)

const proxyRealmPath = "gno.land/r/gnoswap/ibc/v1/apps/zkgm"

// TestRefundV2InitializeNativeRestoresSender reproduces the
// "insufficient coins error" panic seen on TOKEN_ORDER_KIND_INITIALIZE
// timeout when BaseToken is a native (non-IBC) denom.
//
// Production state at the moment of failure:
//   - The user's `-send` lands on the zkgm proxy realm address.
//   - The impl realm holds no balance for that denom.
//
// The pre-fix sendNative tried to spend from the impl realm and panicked.
// The fix must route refundV2's native transfer through the realm that
// actually holds the escrow — the proxy realm.
func TestRefundV2InitializeNativeRestoresSender(cur realm, t *testing.T) {
	resetTokenOrderTest()

	sender := testAddress("native-refund")
	senderAddr := address(sender)
	denom := "ugnot"
	amount := int64(50)

	// Proxy realm holds the user's -send (the post-tx, pre-timeout state).
	proxyAddr := chain.PackageAddress(proxyRealmPath)
	testing.IssueCoins(proxyAddr, chain.NewCoins(chain.NewCoin(denom, amount)))

	// Mirror the channel-balance bump done by verifyTokenOrderV2 INITIALIZE
	// so refundV2's decreaseChannelBalanceV2 succeeds.
	channelId := core.ChannelId(7)
	key := ChannelBalanceKeyV2(channelId, u256.Zero(), []byte(denom), []byte("quote"))
	zkgm.SetChannelBalanceV2(cross, key, u256.NewUint(uint64(amount)))

	order := z.TokenOrderV2{
		Sender:      []byte(sender),
		Receiver:    []byte("g1receiver"),
		BaseToken:   []byte(denom),
		BaseAmount:  u256.NewUint(uint64(amount)),
		QuoteToken:  []byte("quote"),
		QuoteAmount: u256.NewUint(uint64(amount)),
		Kind:        z.TOKEN_ORDER_KIND_INITIALIZE,
	}

	err := (&ZkgmV1{}).refundV2(channelId, u256.Zero(), order)
	uassert.NoError(t, err)

	bk := banker.NewBanker(banker.BankerTypeReadonly)

	// Sender now holds the refunded BaseAmount on the native ledger.
	uassert.Equal(t, amount, bk.GetCoins(senderAddr).AmountOf(denom))

	// Proxy escrow has drained to zero.
	uassert.Equal(t, int64(0), bk.GetCoins(proxyAddr).AmountOf(denom))

	// Channel balance has been decremented.
	finalBalance := zkgm.GetChannelBalanceV2(key)
	uassert.True(t, finalBalance == nil || finalBalance.IsZero())
}

// TestRefundV2EscrowNativeRestoresSender covers the ESCROW kind, which
// shares the refundV2 native code path with INITIALIZE. Kept separate so a
// regression in either kind is caught directly by name.
func TestRefundV2EscrowNativeRestoresSender(cur realm, t *testing.T) {
	resetTokenOrderTest()

	sender := testAddress("native-escrow-refund")
	senderAddr := address(sender)
	denom := "ugnot"
	amount := int64(75)

	proxyAddr := chain.PackageAddress(proxyRealmPath)
	testing.IssueCoins(proxyAddr, chain.NewCoins(chain.NewCoin(denom, amount)))

	channelId := core.ChannelId(8)
	key := ChannelBalanceKeyV2(channelId, u256.Zero(), []byte(denom), []byte("quote"))
	zkgm.SetChannelBalanceV2(cross, key, u256.NewUint(uint64(amount)))

	order := z.TokenOrderV2{
		Sender:      []byte(sender),
		Receiver:    []byte("g1receiver"),
		BaseToken:   []byte(denom),
		BaseAmount:  u256.NewUint(uint64(amount)),
		QuoteToken:  []byte("quote"),
		QuoteAmount: u256.NewUint(uint64(amount)),
		Kind:        z.TOKEN_ORDER_KIND_ESCROW,
	}

	err := (&ZkgmV1{}).refundV2(channelId, u256.Zero(), order)
	uassert.NoError(t, err)

	bk := banker.NewBanker(banker.BankerTypeReadonly)
	uassert.Equal(t, amount, bk.GetCoins(senderAddr).AmountOf(denom))
	uassert.Equal(t, int64(0), bk.GetCoins(proxyAddr).AmountOf(denom))

	finalBalance := zkgm.GetChannelBalanceV2(key)
	uassert.True(t, finalBalance == nil || finalBalance.IsZero())
}
