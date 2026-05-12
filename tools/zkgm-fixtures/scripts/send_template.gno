// Template for a single zkgm.Send invocation derived from one
// scenarios.json entry. The wrapper script (gen-send-script.sh)
// substitutes the double-at-sign placeholders below.
//
// Usage (after substitution):
//   gnokey maketx run -gas-fee 1000000ugnot -gas-wanted 90000000 \
//       -broadcast -chainid <chain-id> -remote <rpc-url> \
//       <signing-address> <generated>.gno
package main

import (
	"encoding/hex"

	z "gno.land/p/gnoswap/ibc/zkgm"
	zkgm "gno.land/r/core/ibc/v1/apps/zkgm"
	core "gno.land/r/core/ibc/v1/core"
)

// Scenario:        @@SCENARIO_NAME@@
// instruction_type @@INSTRUCTION_TYPE@@
// source_channel   @@SOURCE_CHANNEL@@

func main() {
	saltBytes := mustHex("@@SALT_HEX@@")
	var salt [32]byte
	copy(salt[:], saltBytes)

	operand := mustHex("@@OPERAND_HEX@@")

	instr := z.Instruction{
		Version: @@VERSION@@,
		Opcode:  @@OPCODE@@,
		Operand: operand,
	}

	zkgm.Send(
		cross,
		core.ChannelId(@@SOURCE_CHANNEL@@),
		core.Timestamp(@@TX_TIMEOUT_TIMESTAMP@@),
		salt,
		instr,
	)
}

func mustHex(s string) []byte {
	if len(s) >= 2 && s[0] == '0' && (s[1] == 'x' || s[1] == 'X') {
		s = s[2:]
	}
	b, err := hex.DecodeString(s)
	if err != nil {
		panic(err)
	}
	return b
}
