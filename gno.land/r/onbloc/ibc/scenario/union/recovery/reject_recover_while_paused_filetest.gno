// PKGPATH: gno.land/r/onbloc/ibc/scenario/union/recovery
package recovery

// reject_recover_while_paused_filetest: SendRaw's existing pause gate applies
// regardless of impl, so recovery can't run while paused — admin must unpause
// first (see recover_native_escrow_after_halt_filetest).

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
	pausedZkgmRecoveryImplPath = "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/v2_locked_recovery"
	pausedAdminAddr            = address("g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5")
	pausedRecipientAddr        = address("g1dyxy88p94acjnm8dmu9tfj2mv2ncvx83cagllu")

	pausedZeroSaltHex = "0000000000000000000000000000000000000000000000000000000000000000"
)

func main(cur realm) {
	testing.SetRealm(testing.NewUserRealm(pausedAdminAddr))
	zkgm.UpdateImpl(cross(cur), pausedZkgmRecoveryImplPath)
	zkgm.Pausable(cross(cur), true)

	println("[SCENARIO] 1. Admin attempts recovery via SendRaw while the app is still paused -> rejected")
	zkgm.SendRaw(cross(cur), uint32(types.ChannelId(1)), uint64(1<<62), pausedZeroSaltHex, z.INSTR_VERSION_2, z.OP_TOKEN_ORDER, pausedRecoveryOperandHex([]byte("ugnot"), []byte("remote-ugnot"), 1000, pausedRecipientAddr))
}

// pausedRecoveryOperandHex ABI-encodes the recovery request for SendRaw's operandHex.
func pausedRecoveryOperandHex(baseToken, quoteToken []byte, amount int64, recipient address) string {
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
// [SCENARIO] 1. Admin attempts recovery via SendRaw while the app is still paused -> rejected

// Error:
// paused
