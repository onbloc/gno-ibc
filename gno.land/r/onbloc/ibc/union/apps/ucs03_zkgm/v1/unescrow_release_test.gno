package v1

// unescrow_release_test.gno covers the receive-side native RELEASE path: an
// incoming UNESCROW order whose base covers the quote must decrease the channel
// balance and hand the escrowed native coins back to the receiver through the
// banker. escrow_test.gno only checks sendNative's pre-banker guard; here we
// fund the escrow account and assert the coins actually move on receive.
//
// This is unit-tested here (mock store, direct executeTokenOrderV2 call) rather
// than as a scenario filetest: the release writes the channel balance a second
// time (after the matching lock set it), and the real bptree-backed store
// rejects rewriting that node within a single execution as a readonly-tainted
// modification — in production the lock and unescrow are separate transactions,
// each reloading state fresh. The map-backed mock store has no such constraint.

import (
	"chain"
	"chain/banker"
	"testing"

	types "gno.land/p/onbloc/ibc/union/types"

	u256 "gno.land/p/gnoswap/uint256"
	"gno.land/p/nt/uassert/v0"
	z "gno.land/p/onbloc/ibc/union/zkgm"
	core "gno.land/r/onbloc/ibc/union/core"
)

func TestTokenOrderExecuteUnescrowReleasesNativeToReceiver(cur realm, t *testing.T) {
	v := newTestImpl()

	const destChan = types.ChannelId(80)
	path := u256.Zero()
	relayer := testAddress("unescrow-rel-rly")
	receiver := testAddress("unescrow-rel-rx")
	quoteWrapped := "remote-wrapped-ugnot"

	// Seed the escrow: the channel balance records 40 locked for (ugnot, wrapped)
	// and the escrow account physically holds 40ugnot (locked by the matching
	// outbound send in production). decreaseChannelBalanceV2 keys the released
	// native (ugnot) in the baseToken slot and the incoming base in the quote
	// slot, so seed the same (ugnot, wrapped) pair.
	balanceKey := ChannelBalanceKeyV2(destChan, path, []byte("ugnot"), []byte(quoteWrapped))
	testStore.SetChannelBalanceV2(0, cur, balanceKey, u256.NewUint(40))

	escrowAcct := cur.Address() // sendNative draws from rlm.Address()
	testing.IssueCoins(escrowAcct, chain.NewCoins(chain.NewCoin("ugnot", 40)))

	order := z.TokenOrderV2{
		Sender:      []byte("remote-sender"),
		Receiver:    []byte(receiver),
		BaseToken:   []byte(quoteWrapped),
		BaseAmount:  u256.NewUint(40),
		QuoteToken:  []byte("ugnot"),
		QuoteAmount: u256.NewUint(40), // base covers quote, fee = 0
		Kind:        z.TOKEN_ORDER_KIND_UNESCROW,
	}
	packet := core.NewPacket(types.ChannelId(1), destChan, nil, 0)

	res, err := v.executeTokenOrderV2(0, cur, packet, address(relayer), nil, [32]byte{}, path, order, false)

	uassert.NoError(t, err)
	uassert.True(t, res.Status == types.PacketStatusSuccess)

	// The escrowed native coins were sent back to the receiver via the banker.
	bk := banker.NewReadonlyBanker()
	uassert.Equal(t, int64(40), bk.GetCoins(address(receiver)).AmountOf("ugnot"))
	uassert.Equal(t, int64(0), bk.GetCoins(escrowAcct).AmountOf("ugnot"))

	// The channel balance was fully consumed by the unescrow.
	bal, ok := testStore.GetChannelBalanceV2(balanceKey)
	uassert.True(t, ok)
	uassert.True(t, bal.IsZero())
}
