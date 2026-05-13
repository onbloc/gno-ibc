// Prints primitive zkgm.SendRaw arguments for a TokenOrderV2 INITIALIZE send.
// Run this after opening a fresh channel pair, then pass source_channel and
// operand_hex to `gnokey maketx call ... -func SendRaw ... -send 100ugnot`.
package main

import (
	"encoding/hex"

	z "gno.land/p/gnoswap/ibc/zkgm"
	u256 "gno.land/p/gnoswap/uint256"
	e2e "gno.land/r/gnoswap/ibc/v1/apps/zkgm/testing/e2e"
)

func main() {
	e2e.RegisterMockLightClient(cross)
	pair := e2e.OpenE2EChannelPair(cross)

	order := z.TokenOrderV2{
		Sender:      []byte("gno-sender"),
		Receiver:    []byte("counterparty-receiver"),
		BaseToken:   []byte("ugnot"),
		BaseAmount:  u256.NewUint(100),
		QuoteToken:  []byte("counterparty-projected-quote"),
		QuoteAmount: u256.NewUint(100),
		Kind:        z.TOKEN_ORDER_KIND_INITIALIZE,
	}
	operand, err := z.EncodeTokenOrderV2(order)
	if err != nil {
		panic(err)
	}

	println("source_channel", pair.Source.String())
	println("destination_channel", pair.Destination.String())
	println("timeout_timestamp", "1700000000000000000")
	println("salt_hex", "0000000000000000000000000000000000000000000000000000000000000000")
	println("version", "2")
	println("opcode", "3")
	println("operand_hex", hex.EncodeToString(operand))
	println("send", "100ugnot")
}
