package main

import (
	"crypto/keccak256"
	"encoding/binary"
	"encoding/hex"

	z "gno.land/p/gnoswap/ibc/zkgm"
	u256 "gno.land/p/gnoswap/uint256"
	core "gno.land/r/core/ibc/v1/core"
	e2e "gno.land/r/gnoswap/ibc/v1/apps/zkgm/testing/e2e"
	realcometbls "gno.land/r/gnoswap/ibc/v1/apps/zkgm/testing/realcometbls"
	_ "gno.land/r/gnoswap/ibc/v1/apps/zkgm/v0/loader"
)

func main() {
	pair := realcometbls.OpenZ35CometBLSChannel(cross)

	order := z.TokenOrderV2{
		Sender:      []byte("sender"),
		Receiver:    []byte("g1wymu47drhr0kuq2098m792lytgtj2nyx77yrsm"),
		BaseToken:   []byte("ibc/base"),
		BaseAmount:  u256.NewUint(21),
		QuoteToken:  []byte("ugnot"),
		QuoteAmount: u256.NewUint(21),
		Kind:        z.TOKEN_ORDER_KIND_UNESCROW,
	}
	packet := core.PacketSend(cross, core.MsgPacketSend{
		SourceChannelId:  pair.Destination,
		TimeoutTimestamp: core.Timestamp(3600),
		Data:             e2e.MustPacketData(cross, e2e.MustTokenOrderInstruction(cross, order)),
	})
	ack := e2e.MustSuccessAck(cross, mustMarketMakerTokenOrderAck([]byte("g1wymu47drhr0kuq2098m792lytgtj2nyx77yrsm")))
	ackHash := keccak256.Sum256(ack)

	ackKey := packetAcknowledgementPath(packet)
	receiptKey := packetReceiptPath(packet)

	printKV("ack_membership", ackKey[:], ackHash[:])
	println("ack_bytes", "0x"+hex.EncodeToString(ack))
	printKV("receipt_non_membership", receiptKey[:], nil)
	println("packet_sequence", packet.Sequence.String())
	println("source_channel", packet.SourceChannelId.String())
	println("destination_channel", packet.DestinationChannelId.String())
	println("packet_data", "0x"+hex.EncodeToString(packet.Data))
}

func mustMarketMakerTokenOrderAck(marketMaker []byte) []byte {
	bz, err := z.EncodeTokenOrderAck(z.TokenOrderAck{
		FillType:    new(u256.Uint).SetBytes(z.FILL_TYPE_MARKETMAKER[:]),
		MarketMaker: marketMaker,
	})
	if err != nil {
		panic(err)
	}
	return bz
}

func printKV(name string, key []byte, value []byte) {
	println(name+"_key", "0x"+hex.EncodeToString(key))
	if value != nil {
		println(name+"_value", "0x"+hex.EncodeToString(value))
	}
}

// Keep the path derivation local because passing a main-realm Packet into the
// imported core path helpers currently trips an external realm type conversion.
// The matching core unit test binds these golden values to the production path
// helpers directly.
func packetAcknowledgementPath(packet core.Packet) [32]byte {
	batchHash := hash(packet.EthAbiEncode())
	return hash(concat(core.PACKET_ACKS[:], batchHash[:]))
}

func packetReceiptPath(packet core.Packet) [32]byte {
	return hash(concat(
		core.PACKET_RECEIPTS[:],
		u32ToH256(uint32(packet.SourceChannelId)),
		u32ToH256(uint32(packet.DestinationChannelId)),
		u64ToH256(uint64(packet.Sequence)),
	))
}

func hash(bz []byte) [32]byte {
	return keccak256.Sum256(bz)
}

func u32ToH256(n uint32) []byte {
	bz := [32]byte{}
	binary.BigEndian.PutUint32(bz[28:], n)
	return bz[:]
}

func u64ToH256(n uint64) []byte {
	bz := [32]byte{}
	binary.BigEndian.PutUint64(bz[24:], n)
	return bz[:]
}

func concat(parts ...[]byte) []byte {
	size := 0
	for _, p := range parts {
		size += len(p)
	}
	out := make([]byte, 0, size)
	for _, p := range parts {
		out = append(out, p...)
	}
	return out
}

// Output:
// ack_membership_key 0x01a2eb330b6260811ce5ca10fbff1cfb4611444cc65003ad76eacd804085ce55
// ack_membership_value 0x51b1bc1398f211274f5339ff648616f0aaf364c1cab142847beae15e25a0f2d9
// ack_bytes 0x0000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000000a000000000000000000000000000000000000000000000000000000000d1cec45e00000000000000000000000000000000000000000000000000000000000000400000000000000000000000000000000000000000000000000000000000000028673177796d75343764726872306b7571323039386d3739326c797467746a326e797837377972736d000000000000000000000000000000000000000000000000
// receipt_non_membership_key 0xaaa7bd6e1524998c867fc9248d3940e6873a82884f0754f79fd7bec370f222b7
// packet_sequence 0
// source_channel 1
// destination_channel 2
// packet_data 0x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000006000000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000003000000000000000000000000000000000000000000000000000000000000006000000000000000000000000000000000000000000000000000000000000002400000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000014000000000000000000000000000000000000000000000000000000000000001a0000000000000000000000000000000000000000000000000000000000000001500000000000000000000000000000000000000000000000000000000000001e0000000000000000000000000000000000000000000000000000000000000001500000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000220000000000000000000000000000000000000000000000000000000000000000673656e64657200000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000028673177796d75343764726872306b7571323039386d3739326c797467746a326e797837377972736d00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000086962632f62617365000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000575676e6f740000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
