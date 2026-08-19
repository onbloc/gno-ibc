// PKGPATH: gno.land/r/onbloc/ibc/scenario/union/recovery
package recovery

// reject_recover_zero_amount_filetest: a zero (or negative) amount is
// rejected upfront rather than silently succeeding as a no-op — otherwise the
// channel balance and recovery ledger stay unchanged but an
// AdminRecoveredLockedToken event still fires, polluting the audit trail.

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
	zeroAmountZkgmRecoveryImplPath = "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/v2_locked_recovery"
	zeroAmountAdminAddr            = address("g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5")
	zeroAmountRecipientAddr        = address("g1dyxy88p94acjnm8dmu9tfj2mv2ncvx83cagllu")

	zeroAmountZeroSaltHex = "0000000000000000000000000000000000000000000000000000000000000000"
)

func main(cur realm) {
	testing.SetRealm(testing.NewUserRealm(zeroAmountAdminAddr))
	zkgm.UpdateImpl(cross(cur), zeroAmountZkgmRecoveryImplPath)

	println("[SCENARIO] 1. Admin attempts recovery with amount=0 -> rejected")
	zkgm.SendRaw(cross(cur), uint32(types.ChannelId(1)), uint64(1<<62), zeroAmountZeroSaltHex, z.INSTR_VERSION_2, z.OP_TOKEN_ORDER, zeroAmountRecoveryOperandHex([]byte("ugnot"), []byte("remote-ugnot"), 0, zeroAmountRecipientAddr))
}

// zeroAmountRecoveryOperandHex ABI-encodes the recovery request for SendRaw's operandHex.
func zeroAmountRecoveryOperandHex(baseToken, quoteToken []byte, amount int64, recipient address) string {
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
// [SCENARIO] 1. Admin attempts recovery with amount=0 -> rejected

// Error:
// zkgm/recovery: amount must be positive
