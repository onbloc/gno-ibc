// PKGPATH: gno.land/r/onbloc/ibc/scenario/union/recovery
package recovery

// reject_recover_empty_base_token_filetest: an empty BaseToken is rejected
// upfront with a clear runbook-facing error, rather than falling through to a
// channelBalance underflow that looks like an amount mistake, not a missing
// field. QuoteToken is guarded the same way (not separately tested — same
// upfront-emptiness check, would just duplicate this case).

import (
	"encoding/hex"
	"testing"

	types "gno.land/p/onbloc/ibc/union/types"
	z "gno.land/p/onbloc/ibc/union/zkgm"
	u256 "gno.land/p/onbloc/math/uint256"

	zkgm "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm"
	_ "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/v1"
	_ "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/v2_locked_recovery"
)

const (
	emptyBaseTokenZkgmRecoveryImplPath = "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/v2_locked_recovery"
	emptyBaseTokenAdminAddr            = address("g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5")
	emptyBaseTokenRecipientAddr        = address("g1dyxy88p94acjnm8dmu9tfj2mv2ncvx83cagllu")

	emptyBaseTokenZeroSaltHex = "0000000000000000000000000000000000000000000000000000000000000000"
)

func main(cur realm) {
	testing.SetRealm(testing.NewUserRealm(emptyBaseTokenAdminAddr))
	zkgm.UpdateImpl(cross(cur), emptyBaseTokenZkgmRecoveryImplPath)

	println("[SCENARIO] 1. Admin attempts recovery with an empty BaseToken -> rejected")
	zkgm.SendRaw(cross(cur), uint32(types.ChannelId(1)), uint64(1<<62), emptyBaseTokenZeroSaltHex, z.INSTR_VERSION_2, z.OP_TOKEN_ORDER, emptyBaseTokenRecoveryOperandHex(nil, []byte("remote-ugnot"), 1000, emptyBaseTokenRecipientAddr))
}

// emptyBaseTokenRecoveryOperandHex ABI-encodes the recovery request for SendRaw's operandHex.
func emptyBaseTokenRecoveryOperandHex(baseToken, quoteToken []byte, amount int64, recipient address) string {
	order := z.TokenOrderV2{
		BaseToken:   baseToken,
		QuoteToken:  quoteToken,
		BaseAmount:  u256.NewUint(uint64(amount)),
		QuoteAmount: u256.Zero(),
		Receiver:    []byte(recipient.String()),
		Kind:        z.TOKEN_ORDER_KIND_ESCROW,
	}
	operand, err := z.EncodeTokenOrderV2(order)
	if err != nil {
		panic(err)
	}
	return hex.EncodeToString(operand)
}

// Output:
// [SCENARIO] 1. Admin attempts recovery with an empty BaseToken -> rejected

// Error:
// zkgm/recovery: base token is required
