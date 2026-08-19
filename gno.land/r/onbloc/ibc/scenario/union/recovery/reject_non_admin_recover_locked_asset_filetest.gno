// PKGPATH: gno.land/r/onbloc/ibc/scenario/union/recovery
package recovery

// reject_non_admin_recover_locked_asset_filetest: Send gates on an admin-only
// selector, so a non-admin caller via SendRaw is rejected before any escrow moves.

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
	zkgmRecoveryImplPath = "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/v2_locked_recovery"
	adminAddr            = address("g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5")
	nonAdminAddr         = address("g1wymu47drhr0kuq2098m792lytgtj2nyx77yrsm")
	recipientAddr        = address("g1dyxy88p94acjnm8dmu9tfj2mv2ncvx83cagllu")

	rejectNonAdminZeroSaltHex = "0000000000000000000000000000000000000000000000000000000000000000"
)

func main(cur realm) {
	testing.SetRealm(testing.NewUserRealm(adminAddr))
	zkgm.UpdateImpl(cross(cur), zkgmRecoveryImplPath)

	println("[SCENARIO] 1. A non-admin attempts asset recovery via SendRaw -> rejected")
	testing.SetRealm(testing.NewUserRealm(nonAdminAddr))
	zkgm.SendRaw(cross(cur), uint32(types.ChannelId(1)), uint64(1<<62), rejectNonAdminZeroSaltHex, z.INSTR_VERSION_2, z.OP_TOKEN_ORDER, rejectNonAdminRecoveryOperandHex([]byte("ugnot"), []byte("remote-ugnot"), 1000, recipientAddr))
}

// rejectNonAdminRecoveryOperandHex ABI-encodes the recovery request for SendRaw's operandHex.
func rejectNonAdminRecoveryOperandHex(baseToken, quoteToken []byte, amount int64, recipient address) string {
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
// [SCENARIO] 1. A non-admin attempts asset recovery via SendRaw -> rejected

// Error:
// access manager unauthorized call: g1wymu47drhr0kuq2098m792lytgtj2nyx77yrsm is not authorized to call v2_locked_recovery/admin_recover_locked_token on gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm
