// PKGPATH: gno.land/r/onbloc/ibc/scenario/union/recovery
package recovery

// reject_recover_unrecognized_opcode_filetest: Send requires the exact
// version/opcode before decoding — catches a runbook mistake, not an attacker
// (this is already admin-gated).

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
	wrongOpcodeZkgmRecoveryImplPath = "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/v2_locked_recovery"
	wrongOpcodeAdminAddr            = address("g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5")
	wrongOpcodeRecipientAddr        = address("g1dyxy88p94acjnm8dmu9tfj2mv2ncvx83cagllu")

	wrongOpcodeZeroSaltHex = "0000000000000000000000000000000000000000000000000000000000000000"
)

func main(cur realm) {
	testing.SetRealm(testing.NewUserRealm(wrongOpcodeAdminAddr))
	zkgm.UpdateImpl(cross(cur), wrongOpcodeZkgmRecoveryImplPath)

	println("[SCENARIO] 1. Admin sends a well-formed recovery operand but with the wrong opcode -> rejected")
	zkgm.SendRaw(cross(cur), uint32(types.ChannelId(1)), uint64(1<<62), wrongOpcodeZeroSaltHex, z.INSTR_VERSION_2, z.OP_CALL, wrongOpcodeRecoveryOperandHex([]byte("ugnot"), []byte("remote-ugnot"), 1000, wrongOpcodeRecipientAddr))
}

// wrongOpcodeRecoveryOperandHex ABI-encodes the recovery request for SendRaw's operandHex.
func wrongOpcodeRecoveryOperandHex(baseToken, quoteToken []byte, amount int64, recipient address) string {
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
// [SCENARIO] 1. Admin sends a well-formed recovery operand but with the wrong opcode -> rejected

// Error:
// recovery impl: Send: unrecognized version/opcode not supported
