// PKGPATH: gno.land/r/onbloc/unionibc/v1/apps/zkgm/testing/loader
package loader

import (
	u256 "gno.land/p/gnoswap/uint256"
	z "gno.land/p/onbloc/ibc/zkgm"
	zkgm "gno.land/r/onbloc/unionibc/v1/apps/zkgm"
	e2e "gno.land/r/onbloc/unionibc/v1/apps/zkgm/testing/e2e"
	sh "gno.land/r/onbloc/unionibc/v1/apps/zkgm/testing/scenariohelpers"
	core "gno.land/r/onbloc/unionibc/v1/core"
)

func main(cur realm) {
	inst := sh.InstallImpl(cross(cur))
	channelId := core.ChannelId(61)
	amount := u256.NewUint(1234567)
	order := z.TokenOrderV2{
		Sender:      []byte("g16decsender"),
		BaseToken:   []byte("ugnot"),
		BaseAmount:  amount,
		QuoteToken:  []byte("quote/zs26"),
		QuoteAmount: amount,
		Kind:        z.TOKEN_ORDER_KIND_ESCROW,
	}

	println("[SCENARIO] native 6-dec send preserves base amount")
	if _, err := inst.Send(cross(cur), zkgm.NewSendRequest(cross(cur), channelId, core.Timestamp(100), [32]byte{}, e2e.MustTokenOrderInstruction(cross(cur), order), string(order.Sender), "1234567ugnot")); err != nil {
		panic(err)
	}
	println("base_amount", order.BaseAmount.ToString())
	println("channel_balance", sh.ChannelBalanceStr(channelId, u256.Zero(), order.BaseToken, order.QuoteToken))
}

// Output:
// [SCENARIO] native 6-dec send preserves base amount
// base_amount 1234567
// channel_balance 1234567
