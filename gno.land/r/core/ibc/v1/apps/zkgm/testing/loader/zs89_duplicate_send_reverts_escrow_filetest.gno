// PKGPATH: gno.land/r/onbloc/unionibc/v1/apps/zkgm/testing/loader
package loader

import (
	stdtesting "testing"

	u256 "gno.land/p/gnoswap/uint256"
	"gno.land/p/nt/testutils/v0"
	z "gno.land/p/onbloc/unionibc/zkgm"
	zkgm "gno.land/r/onbloc/unionibc/v1/apps/zkgm"
	e2e "gno.land/r/onbloc/unionibc/v1/apps/zkgm/testing/e2e"
	sh "gno.land/r/onbloc/unionibc/v1/apps/zkgm/testing/scenariohelpers"
	impl "gno.land/r/onbloc/unionibc/v1/apps/zkgm/v0/impl"
	core "gno.land/r/onbloc/unionibc/v1/core"
)

func main(cur realm) {
	inst := sh.InstallImpl(cross(cur))
	zkgm.RegisterCoreApp(cross(cur))
	e2e.RegisterMockLightClient(cross(cur))
	pair := e2e.OpenE2EChannelPair(cross(cur))

	sender := string(testutils.TestAddress("zs89-sender"))
	baseToken := sh.MintVoucher(cross(cur), inst, core.ChannelId(80), "base/zs89", sender, 100, "ZS89")
	order := z.TokenOrderV2{
		Sender:      []byte(sender),
		Receiver:    []byte("remote-zs89"),
		BaseToken:   []byte(baseToken),
		BaseAmount:  u256.NewUint(21),
		QuoteToken:  []byte("quote/zs89"),
		QuoteAmount: u256.NewUint(21),
		Kind:        z.TOKEN_ORDER_KIND_ESCROW,
	}
	instr := e2e.MustTokenOrderInstruction(cross(cur), order)

	println("[SCENARIO] first public send commits and escrows")
	stdtesting.SetRealm(stdtesting.NewUserRealm(address(sender)))
	packet := zkgm.Send(cross(cur), pair.Source, core.Timestamp(100), [32]byte{}, instr)
	println("sender_after_first", impl.VoucherBalanceOf(baseToken, address(sender)))
	println("channel_after_first", sh.ChannelBalanceStr(pair.Source, u256.Zero(), order.BaseToken, order.QuoteToken))
	println("commitment_after_first", core.HasPacketCommitment(cross(cur), packet))

	println("")
	println("[SCENARIO] duplicate public send aborts and rolls escrow back")

	println("duplicate_rejected", zs89DuplicateSendReverted(cur, sender, pair.Source, instr))
	println("sender_after_duplicate", impl.VoucherBalanceOf(baseToken, address(sender)))
	println("channel_after_duplicate", sh.ChannelBalanceStr(pair.Source, u256.Zero(), order.BaseToken, order.QuoteToken))
	println("commitment_after_duplicate", core.HasPacketCommitment(cross(cur), packet))
}

func zs89DuplicateSendReverted(cur realm, sender string, channelId core.ChannelId, instr z.Instruction) bool {
	p := revive(func() {
		stdtesting.SetRealm(stdtesting.NewUserRealm(address(sender)))
		zkgm.Send(cross(cur), channelId, core.Timestamp(100), [32]byte{}, instr)
	})
	return p != nil
}

// Output:
// [SCENARIO] first public send commits and escrows
// sender_after_first 79
// channel_after_first 21
// commitment_after_first true
//
// [SCENARIO] duplicate public send aborts and rolls escrow back
// duplicate_rejected true
// sender_after_duplicate 79
// channel_after_duplicate 21
// commitment_after_duplicate true
