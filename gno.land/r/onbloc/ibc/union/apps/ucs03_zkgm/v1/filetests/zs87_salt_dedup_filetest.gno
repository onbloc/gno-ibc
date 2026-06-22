// PKGPATH: gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/v1/main
package main

import (
	"gno.land/p/nt/testutils/v0"
	types "gno.land/p/onbloc/ibc/union/types"
	z "gno.land/p/onbloc/ibc/union/zkgm"
	u256 "gno.land/p/gnoswap/uint256"
	zkgm "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm"
	impl "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/v1"
)

func main(cur realm) {
	store := zkgm.NewStore()
	app := impl.NewUCS03ZkgmV1(store)

	receiver := string(testutils.TestAddress("zs87-receiver"))
	destination := types.ChannelId(2)
	quoteToken := impl.PredictWrappedToken(u256.Zero(), uint32(destination), []byte("ugnot"))
	otherQuoteToken := impl.PredictWrappedToken(u256.Zero(), uint32(destination), []byte("uother"))

	order := z.TokenOrderV2{
		Sender:      []byte("same-sender"),
		Receiver:    []byte(receiver),
		BaseToken:   []byte("ugnot"),
		BaseAmount:  u256.NewUint(10),
		QuoteToken:  []byte(quoteToken),
		QuoteAmount: u256.NewUint(10),
		Kind:        z.TOKEN_ORDER_KIND_ESCROW,
	}
	otherOrder := z.TokenOrderV2{
		Sender:      []byte("same-sender"),
		Receiver:    []byte(receiver),
		BaseToken:   []byte("uother"),
		BaseAmount:  u256.NewUint(10),
		QuoteToken:  []byte(otherQuoteToken),
		QuoteAmount: u256.NewUint(10),
		Kind:        z.TOKEN_ORDER_KIND_ESCROW,
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

	samePacket := types.NewPacket(types.ChannelId(1), destination,
		mustZS87SaltedPacketData(derivedA, mustZS87TokenOrderInstruction(order)), types.Timestamp(1<<62))
	samePacket2 := types.NewPacket(types.ChannelId(1), destination,
		mustZS87SaltedPacketData(derivedA2, mustZS87TokenOrderInstruction(order)), types.Timestamp(1<<62))
	otherPacket := types.NewPacket(types.ChannelId(1), destination,
		mustZS87SaltedPacketData(derivedB, mustZS87TokenOrderInstruction(otherOrder)), types.Timestamp(1<<62))
	println("same_packet_commit_equal", types.MustCommit(types.CommitPacket(samePacket)) == types.MustCommit(types.CommitPacket(samePacket2)))
	println("different_salt_commit_distinct", types.MustCommit(types.CommitPacket(samePacket)) != types.MustCommit(types.CommitPacket(otherPacket)))

	first := app.OnRecvPacket(0, cur, samePacket, testutils.TestAddress("relayer-a"), nil)
	second := app.OnRecvPacket(0, cur, otherPacket, testutils.TestAddress("relayer-b"), nil)
	voucher, _ := store.GetVoucher(quoteToken)
	otherVoucher, _ := store.GetVoucher(otherQuoteToken)

	println("first_status", int(first.Status))
	println("second_status", int(second.Status))
	println("receiver_first_token", voucher.Token().BalanceOf(address(receiver)))
	println("receiver_other_token", otherVoucher.Token().BalanceOf(address(receiver)))
}

func mustZS87TokenOrderInstruction(order z.TokenOrderV2) z.Instruction {
	orderBytes, err := z.EncodeTokenOrderV2(order)
	if err != nil {
		panic(err)
	}
	return z.Instruction{Version: z.INSTR_VERSION_2, Opcode: z.OP_TOKEN_ORDER, Operand: orderBytes}
}

func mustZS87SaltedPacketData(salt [32]byte, instr z.Instruction) []byte {
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

// Output:
// same_sender_salt_equal true
// different_salt_distinct true
// same_packet_commit_equal true
// different_salt_commit_distinct true
// first_status 1
// second_status 1
// receiver_first_token 10
// receiver_other_token 10
