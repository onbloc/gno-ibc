// PKGPATH: gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/testing/e2e/scenarios_direct
package scenarios_direct

import (
	types "gno.land/p/onbloc/ibc/union/types"

	u256 "gno.land/p/gnoswap/uint256"
	z "gno.land/p/onbloc/ibc/union/zkgm"
	zkgm "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm"
	e2e "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/testing/e2e"
	sh "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/testing/scenariohelpers"
)

func main(cur realm) {
	inst := sh.InstallV1Harness(cross(cur))
	channelId := types.ChannelId(61)
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
	if _, err := inst.Send(cross(cur), zkgm.NewSendRequest(cross(cur), channelId, types.Timestamp(100), [32]byte{}, e2e.MustTokenOrderInstruction(cross(cur), order), string(order.Sender), "1234567ugnot")); err != nil {
		panic(err)
	}
	println("base_amount", order.BaseAmount.ToString())
	println("channel_balance", sh.ChannelBalanceStr(channelId, u256.Zero(), order.BaseToken, order.QuoteToken))
}

// Output:
// [SCENARIO] native 6-dec send preserves base amount
// base_amount 1234567
// channel_balance 1234567
