// PKGPATH: gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/v1/main
package main

import (
	"gno.land/p/nt/testutils/v0"
	types "gno.land/p/onbloc/ibc/union/types"
	z "gno.land/p/onbloc/ibc/union/zkgm"
	u256 "gno.land/p/gnoswap/uint256"
	zkgm "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm"
	"gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/testing/mock"
	impl "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/v1"
)

const z24MockReceiverPath = "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/testing/mock"

func main(cur realm) {
	mock.Reset(cross(cur))
	store := zkgm.NewStore()
	store.SetReceiver(0, cur, z24MockReceiverPath, mock.Zkgmable(cross(cur)))
	app := impl.NewUCS03ZkgmV1(store)

	source := types.ChannelId(1)
	destination := types.ChannelId(2)
	receiver := string(testutils.TestAddress("batch-receiver"))
	relayer := testutils.TestAddress("batch-relayer")
	quoteToken := impl.PredictWrappedToken(u256.Zero(), uint32(destination), []byte("ugnot"))

	order := z.TokenOrderV2{
		Sender:      []byte("sender"),
		Receiver:    []byte(receiver),
		BaseToken:   []byte("ugnot"),
		BaseAmount:  u256.NewUint(100),
		QuoteToken:  []byte(quoteToken),
		QuoteAmount: u256.NewUint(21),
		Kind:        z.TOKEN_ORDER_KIND_ESCROW,
	}
	call := z.Call{
		Sender:           []byte("sender"),
		ContractAddress:  []byte(z24MockReceiverPath),
		ContractCalldata: []byte("post-transfer-action"),
	}
	batch := z.Batch{Instructions: []z.Instruction{
		mustZ24TokenOrderInstruction(order),
		mustZ24CallInstruction(call),
	}}
	packet := types.NewPacket(source, destination, mustZ24PacketData(mustZ24BatchInstruction(batch)), 0)

	result := app.OnRecvPacket(0, cur, packet, relayer, []byte("relay-msg"))
	voucher, _ := store.GetVoucher(quoteToken)
	ack, _ := z.DecodeAck(result.Acknowledgement)
	batchAck, _ := z.DecodeBatchAck(ack.InnerAck)

	println("status", int(result.Status))
	println("batch_ack_count", len(batchAck.Acknowledgements))
	println("quote_balance", voucher.Token().BalanceOf(address(receiver)))
	println("relayer_balance", voucher.Token().BalanceOf(relayer))
	println("mock_calls", mock.Calls(cross(cur)))
	println("last_calldata", mock.LastCalldata(cross(cur)))
	println("last_relayer_msg", mock.LastRelayerMsg(cross(cur)))
}

func mustZ24TokenOrderInstruction(order z.TokenOrderV2) z.Instruction {
	orderBytes, err := z.EncodeTokenOrderV2(order)
	if err != nil {
		panic(err)
	}
	return z.Instruction{Version: z.INSTR_VERSION_2, Opcode: z.OP_TOKEN_ORDER, Operand: orderBytes}
}

func mustZ24CallInstruction(call z.Call) z.Instruction {
	callBytes, err := z.EncodeCall(call)
	if err != nil {
		panic(err)
	}
	return z.Instruction{Version: z.INSTR_VERSION_0, Opcode: z.OP_CALL, Operand: callBytes}
}

func mustZ24BatchInstruction(batch z.Batch) z.Instruction {
	batchBytes, err := z.EncodeBatch(batch)
	if err != nil {
		panic(err)
	}
	return z.Instruction{Version: z.INSTR_VERSION_0, Opcode: z.OP_BATCH, Operand: batchBytes}
}

func mustZ24PacketData(instr z.Instruction) []byte {
	packetBytes, err := z.EncodeZkgmPacket(z.ZkgmPacket{
		Path:        u256.Zero(),
		Instruction: instr,
	})
	if err != nil {
		panic(err)
	}
	return packetBytes
}

// Output:
// status 1
// batch_ack_count 2
// quote_balance 21
// relayer_balance 79
// mock_calls 1
// last_calldata post-transfer-action
// last_relayer_msg relay-msg
