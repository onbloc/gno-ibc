// PKGPATH: gno.land/r/onbloc/ibc/scenario/union/recovery
package recovery

// reject_recover_invalid_recipient_filetest: a malformed (non-bech32)
// recipient is rejected upfront rather than moving funds nobody controls.

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
	invalidRecipientZkgmRecoveryImplPath = "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/v2_locked_recovery"
	invalidRecipientAdminAddr            = address("g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5")

	invalidRecipientZeroSaltHex = "0000000000000000000000000000000000000000000000000000000000000000"
)

func main(cur realm) {
	testing.SetRealm(testing.NewUserRealm(invalidRecipientAdminAddr))
	zkgm.UpdateImpl(cross(cur), invalidRecipientZkgmRecoveryImplPath)

	println("[SCENARIO] 1. Admin attempts recovery with a malformed (non-bech32) recipient -> rejected")
	zkgm.SendRaw(cross(cur), uint32(types.ChannelId(1)), uint64(1<<62), invalidRecipientZeroSaltHex, z.INSTR_VERSION_2, z.OP_TOKEN_ORDER, invalidRecipientRecoveryOperandHex([]byte("ugnot"), []byte("remote-ugnot"), 1000, "0x1111111111111111111111111111111111111111"))
}

// invalidRecipientRecoveryOperandHex encodes with a raw recipient string (not an address) to exercise a malformed value.
func invalidRecipientRecoveryOperandHex(baseToken, quoteToken []byte, amount int64, recipientRaw string) string {
	order := z.TokenOrderV2{
		BaseToken:   baseToken,
		QuoteToken:  quoteToken,
		BaseAmount:  u256.NewUint(uint64(amount)),
		QuoteAmount: u256.Zero(),
		Receiver:    []byte(recipientRaw),
		Kind:        z.TOKEN_ORDER_KIND_ESCROW,
	}
	operand, err := z.EncodeTokenOrderV2(order)
	if err != nil {
		panic(err)
	}
	return hex.EncodeToString(operand)
}

// Output:
// [SCENARIO] 1. Admin attempts recovery with a malformed (non-bech32) recipient -> rejected

// Error:
// zkgm/recovery: recipient is not a valid address
