// PKGPATH: gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/testing/e2e/scenarios
package scenarios

import (
	types "gno.land/p/onbloc/ibc/union/types"

	u256 "gno.land/p/gnoswap/uint256"
	"gno.land/p/nt/testutils/v0"
	z "gno.land/p/onbloc/ibc/union/zkgm"
	e2e "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/testing/e2e"
	impl "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/v1"
	core "gno.land/r/onbloc/ibc/union/core"
)

func main(cur realm) {
	impl.Register(cross(cur))
	e2e.RegisterMockLightClient(cross(cur))
	pair := e2e.OpenE2EChannelPair(cross(cur))

	receiver := string(testutils.TestAddress("zs87-receiver"))
	metaBytes := e2e.MustTokenMetadata(cross(cur), "grc20", z.TokenInitializer{Name: "Dedup Token", Symbol: "DDP", Decimals: 6})
	quoteToken := z.PredictWrappedTokenV2(u256.Zero(), uint32(pair.Destination), []byte("ugnot"), z.MetadataImage(mustDecodeZS87TokenMetadata(metaBytes)))
	order := z.TokenOrderV2{
		Sender:      []byte("same-sender"),
		Receiver:    []byte(receiver),
		BaseToken:   []byte("ugnot"),
		BaseAmount:  u256.NewUint(10),
		QuoteToken:  []byte(quoteToken),
		QuoteAmount: u256.NewUint(10),
		Kind:        z.TOKEN_ORDER_KIND_INITIALIZE,
		Metadata:    metaBytes,
	}
	otherMetaBytes := e2e.MustTokenMetadata(cross(cur), "grc20", z.TokenInitializer{Name: "Other Dedup Token", Symbol: "DDP2", Decimals: 6})
	otherQuoteToken := z.PredictWrappedTokenV2(u256.Zero(), uint32(pair.Destination), []byte("uother"), z.MetadataImage(mustDecodeZS87TokenMetadata(otherMetaBytes)))
	otherOrder := z.TokenOrderV2{
		Sender:      []byte("same-sender"),
		Receiver:    []byte(receiver),
		BaseToken:   []byte("uother"),
		BaseAmount:  u256.NewUint(10),
		QuoteToken:  []byte(otherQuoteToken),
		QuoteAmount: u256.NewUint(10),
		Kind:        z.TOKEN_ORDER_KIND_INITIALIZE,
		Metadata:    otherMetaBytes,
	}

	var saltA [32]byte
	saltA[31] = 1
	var saltB [32]byte
	saltB[31] = 2
	derivedA := z.DeriveSenderSalt(order.Sender, saltA)
	derivedA2 := z.DeriveSenderSalt(order.Sender, saltA)
	derivedB := z.DeriveSenderSalt(order.Sender, saltB)
	println("same_sender_salt_equal", derivedA == derivedA2)
	println("different_salt_distinct", derivedA != derivedB)

	samePacket := core.NewPacket(pair.Source, pair.Destination,
		mustSaltedPacketData(cross(cur), derivedA, e2e.MustTokenOrderInstruction(cross(cur), order)), types.Timestamp(1<<62))
	samePacket2 := core.NewPacket(pair.Source, pair.Destination,
		mustSaltedPacketData(cross(cur), derivedA2, e2e.MustTokenOrderInstruction(cross(cur), order)), types.Timestamp(1<<62))
	otherPacket := core.NewPacket(pair.Source, pair.Destination,
		mustSaltedPacketData(cross(cur), derivedB, e2e.MustTokenOrderInstruction(cross(cur), otherOrder)), types.Timestamp(1<<62))
	println("same_packet_commit_equal", types.MustCommit(types.CommitPacket(samePacket)) == types.MustCommit(types.CommitPacket(samePacket2)))
	println("different_salt_commit_distinct", types.MustCommit(types.CommitPacket(samePacket)) != types.MustCommit(types.CommitPacket(otherPacket)))

	println("")
	println("[SCENARIO] repeated packet is swallowed by receipt")
	core.PacketRecv(cross(cur), types.NewMsgPacketRecv([]types.Packet{samePacket}, [][]byte{nil}, nil, 1))
	println("receipt_after_first", core.HasPacketReceipt(cross(cur), samePacket))
	println("receiver_after_first", impl.VoucherBalanceOf(quoteToken, address(receiver)))
	core.PacketRecv(cross(cur), types.NewMsgPacketRecv([]types.Packet{samePacket}, [][]byte{nil}, nil, 1))
	println("receiver_after_second_same", impl.VoucherBalanceOf(quoteToken, address(receiver)))

	println("")
	println("[SCENARIO] different salt is a distinct packet")
	core.PacketRecv(cross(cur), types.NewMsgPacketRecv([]types.Packet{otherPacket}, [][]byte{nil}, nil, 1))
	println("other_receipt", core.HasPacketReceipt(cross(cur), otherPacket))
	println("receiver_other_token", impl.VoucherBalanceOf(otherQuoteToken, address(receiver)))
}

func mustSaltedPacketData(cur realm, salt [32]byte, instr z.Instruction) []byte {
	packetBytes, err := z.EncodeZkgmPacket(z.ZkgmPacket{
		Salt:        salt,
		Path:        u256.Zero(),
		Instruction: instr,
	})
	if err != nil {
		panic(err)
	}
	return packetBytes
}

func mustDecodeZS87TokenMetadata(bz []byte) z.TokenMetadata {
	meta, err := z.DecodeTokenMetadata(bz)
	if err != nil {
		panic(err)
	}
	return meta
}

// Output:
// same_sender_salt_equal true
// different_salt_distinct true
// same_packet_commit_equal true
// different_salt_commit_distinct true
//
// [SCENARIO] repeated packet is swallowed by receipt
// receipt_after_first true
// receiver_after_first 10
// receiver_after_second_same 10
//
// [SCENARIO] different salt is a distinct packet
// other_receipt true
// receiver_other_token 10
