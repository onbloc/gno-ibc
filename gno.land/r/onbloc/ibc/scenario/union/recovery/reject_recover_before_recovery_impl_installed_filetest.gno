// PKGPATH: gno.land/r/onbloc/ibc/scenario/union/recovery
package recovery

// reject_recover_before_recovery_impl_installed_filetest: v1 has no recovery
// mode, so the same operand via SendRaw fails ordinary (Kind-zero) token-order
// validation instead of accidentally moving funds.

import (
	"encoding/hex"
	"testing"

	types "gno.land/p/onbloc/ibc/union/types"
	z "gno.land/p/onbloc/ibc/union/zkgm"
	u256 "gno.land/p/onbloc/math/uint256"

	"gno.land/r/onbloc/ibc/union/access"
	zkgm "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm"
	_ "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/v1"
	_ "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/v2_locked_recovery"
)

const (
	zkgmImplPath  = "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/v1"
	adminAddr     = address("g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5")
	recipientAddr = address("g1dyxy88p94acjnm8dmu9tfj2mv2ncvx83cagllu")

	rejectBeforeInstalledZeroSaltHex = "0000000000000000000000000000000000000000000000000000000000000000"
)

func main(cur realm) {
	testing.SetRealm(testing.NewUserRealm(adminAddr))
	zkgm.UpdateImpl(cross(cur), zkgmImplPath)
	access.GrantRole(cross(cur), access.RelayerRole, adminAddr)

	println("[SCENARIO] 1. Admin sends the recovery-shaped operand while v1 (not v2_locked_recovery) is installed -> fails safely, no funds move")
	zkgm.SendRaw(cross(cur), uint32(types.ChannelId(1)), uint64(1<<62), rejectBeforeInstalledZeroSaltHex, z.INSTR_VERSION_2, z.OP_TOKEN_ORDER, rejectBeforeInstalledRecoveryOperandHex([]byte("ugnot"), []byte("remote-ugnot"), 1000, recipientAddr))
}

// rejectBeforeInstalledRecoveryOperandHex ABI-encodes the recovery request for SendRaw's operandHex.
func rejectBeforeInstalledRecoveryOperandHex(baseToken, quoteToken []byte, amount int64, recipient address) string {
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
// [SCENARIO] 1. Admin sends the recovery-shaped operand while v1 (not v2_locked_recovery) is installed -> fails safely, no funds move

// Error:
// zkgm/coins: sent coin mismatch
