// PKGPATH: gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/v1/main
package main

import (
	u256 "gno.land/p/gnoswap/uint256"
	types "gno.land/p/onbloc/ibc/union/types"
	z "gno.land/p/onbloc/ibc/union/zkgm"
	zkgm "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm"
	"gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/testing/mock"
	impl "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/v1"
)

const (
	z39RecvMockReceiverPath    = "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/testing/mock"
	z39RecvMissingReceiverPath = "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/testing/missing"
)

func main(cur realm) {
	store := zkgm.NewStore()
	store.SetReceiver(0, cur, z39RecvMockReceiverPath, mock.Zkgmable(cross(cur)))
	app := impl.NewUCS03ZkgmV1(store)

	mock.Reset(cross(cur))
	callResult := app.OnRecvPacket(0, cur, z39RecvCallPacket(z39RecvMockReceiverPath), address("g1relayer"), []byte("relay-msg"))
	println("call_status", int(callResult.Status))
	println("call_mock_calls", mock.Calls(cross(cur)))
	println("call_last_sender", mock.LastSender(cross(cur)))
	println("call_last_calldata", mock.LastCalldata(cross(cur)))
	println("call_last_relayer_msg", mock.LastRelayerMsg(cross(cur)))
	println("call_ack_success", z39RecvAckTagSuccess(callResult.Acknowledgement))

	missingResult := app.OnRecvPacket(0, cur, z39RecvCallPacket(z39RecvMissingReceiverPath), address("g1relayer"), nil)
	println("missing_status", int(missingResult.Status))
	println("missing_ack_failure", z39RecvAckTagFailure(missingResult.Acknowledgement))

	mock.Reset(cross(cur))
	mock.SetPanic(cross(cur), "boom")
	panicResult := app.OnRecvPacket(0, cur, z39RecvCallPacket(z39RecvMockReceiverPath), address("g1relayer"), nil)
	println("panic_status", int(panicResult.Status))
	println("panic_mock_calls", mock.Calls(cross(cur)))
	println("panic_only_maker", string(panicResult.Acknowledgement) == string(z.ACK_ERR_ONLY_MAKER))
}

func z39RecvCallPacket(receiverPath string) types.Packet {
	call := z.Call{
		Sender:           []byte("sender"),
		ContractAddress:  []byte(receiverPath),
		ContractCalldata: []byte("calldata"),
	}
	return types.NewPacket(types.ChannelId(2), types.ChannelId(1), mustZ39RecvPacketData(mustZ39RecvCallInstruction(call)), types.Timestamp(0))
}

func mustZ39RecvCallInstruction(call z.Call) z.Instruction {
	callBytes, err := z.EncodeCall(call)
	if err != nil {
		panic(err)
	}
	return z.Instruction{Version: z.INSTR_VERSION_0, Opcode: z.OP_CALL, Operand: callBytes}
}

func mustZ39RecvPacketData(instr z.Instruction) []byte {
	packetBytes, err := z.EncodeZkgmPacket(z.ZkgmPacket{
		Path:        u256.Zero(),
		Instruction: instr,
	})
	if err != nil {
		panic(err)
	}
	return packetBytes
}

func z39RecvAckTagSuccess(ackBytes []byte) bool {
	ack, err := z.DecodeAck(ackBytes)
	if err != nil {
		panic(err)
	}
	return ack.Tag != nil && ack.Tag.Eq(new(u256.Uint).SetBytes(z.TAG_ACK_SUCCESS[:]))
}

func z39RecvAckTagFailure(ackBytes []byte) bool {
	ack, err := z.DecodeAck(ackBytes)
	if err != nil {
		panic(err)
	}
	return ack.Tag != nil && ack.Tag.IsZero()
}

// Output:
// call_status 1
// call_mock_calls 1
// call_last_sender sender
// call_last_calldata calldata
// call_last_relayer_msg relay-msg
// call_ack_success true
// missing_status 2
// missing_ack_failure true
// panic_status 1
// panic_mock_calls 1
// panic_only_maker true
