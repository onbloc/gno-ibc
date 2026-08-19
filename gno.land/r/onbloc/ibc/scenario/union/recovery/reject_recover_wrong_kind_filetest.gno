// PKGPATH: gno.land/r/onbloc/ibc/scenario/union/recovery
package recovery

// reject_recover_wrong_kind_filetest: Send requires order.Kind ==
// TOKEN_ORDER_KIND_ESCROW — a well-formed operand with the wrong kind (e.g. a
// reused INITIALIZE/UNESCROW request) is rejected instead of being
// reinterpreted as a recovery request.

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
	wrongKindZkgmRecoveryImplPath = "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/v2_locked_recovery"
	wrongKindAdminAddr            = address("g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5")
	wrongKindRecipientAddr        = address("g1dyxy88p94acjnm8dmu9tfj2mv2ncvx83cagllu")

	wrongKindZeroSaltHex = "0000000000000000000000000000000000000000000000000000000000000000"
)

func main(cur realm) {
	testing.SetRealm(testing.NewUserRealm(wrongKindAdminAddr))
	zkgm.UpdateImpl(cross(cur), wrongKindZkgmRecoveryImplPath)

	println("[SCENARIO] 1. Admin sends a well-formed recovery operand but with Kind=INITIALIZE -> rejected")
	zkgm.SendRaw(cross(cur), uint32(types.ChannelId(1)), uint64(1<<62), wrongKindZeroSaltHex, z.INSTR_VERSION_2, z.OP_TOKEN_ORDER, wrongKindRecoveryOperandHex([]byte("ugnot"), []byte("remote-ugnot"), 1000, wrongKindRecipientAddr))
}

// wrongKindRecoveryOperandHex ABI-encodes the recovery request for SendRaw's operandHex, with Kind left as INITIALIZE.
func wrongKindRecoveryOperandHex(baseToken, quoteToken []byte, amount int64, recipient address) string {
	order := z.TokenOrderV2{
		BaseToken:   baseToken,
		QuoteToken:  quoteToken,
		BaseAmount:  u256.NewUint(uint64(amount)),
		QuoteAmount: u256.Zero(),
		Receiver:    []byte(recipient.String()),
		Kind:        z.TOKEN_ORDER_KIND_INITIALIZE,
	}
	operand, err := z.EncodeTokenOrderV2(order)
	if err != nil {
		panic(err)
	}
	return hex.EncodeToString(operand)
}

// Output:
// [SCENARIO] 1. Admin sends a well-formed recovery operand but with Kind=INITIALIZE -> rejected

// Error:
// zkgm/recovery: only ESCROW-kind orders are supported
