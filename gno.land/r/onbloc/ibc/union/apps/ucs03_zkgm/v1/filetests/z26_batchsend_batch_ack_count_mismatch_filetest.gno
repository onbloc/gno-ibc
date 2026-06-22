// PKGPATH: gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/v1/main
package main

import (
	"testing"

	"gno.land/p/nt/uassert/v0"
	types "gno.land/p/onbloc/ibc/union/types"
	z "gno.land/p/onbloc/ibc/union/zkgm"
	u256 "gno.land/p/gnoswap/uint256"
	zkgm "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm"
	impl "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/v1"
)

const z26ReceiverPath = "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/testing/mock"

var t *testing.T

func main(cur realm) {
	app := impl.NewUCS03ZkgmV1(zkgm.NewStore())
	packet := types.NewPacket(types.ChannelId(1), types.ChannelId(2), mustZ26PacketData(mustZ26BatchInstruction(z.Batch{
		Instructions: []z.Instruction{
			mustZ26CallInstruction("first"),
			mustZ26CallInstruction("second"),
		},
	})), 0)

	uassert.AbortsContains(t, cur, "zkgm/v1: batch ack count mismatch", func() {
		app.OnAcknowledgementPacket(0, cur, packet, mustZ26BatchAck([][]byte{mustZ26SuccessAck(nil)}), address("g1relayer"))
	})

	println("batch_ack_count_mismatch", "ok")
}

func mustZ26CallInstruction(calldata string) z.Instruction {
	bz, err := z.EncodeCall(z.Call{
		Sender:           []byte("sender"),
		ContractAddress:  []byte(z26ReceiverPath),
		ContractCalldata: []byte(calldata),
	})
	if err != nil {
		panic(err)
	}
	return z.Instruction{Version: z.INSTR_VERSION_0, Opcode: z.OP_CALL, Operand: bz}
}

func mustZ26BatchInstruction(batch z.Batch) z.Instruction {
	bz, err := z.EncodeBatch(batch)
	if err != nil {
		panic(err)
	}
	return z.Instruction{Version: z.INSTR_VERSION_0, Opcode: z.OP_BATCH, Operand: bz}
}

func mustZ26PacketData(instr z.Instruction) []byte {
	bz, err := z.EncodeZkgmPacket(z.ZkgmPacket{Path: u256.Zero(), Instruction: instr})
	if err != nil {
		panic(err)
	}
	return bz
}

func mustZ26SuccessAck(inner []byte) []byte {
	bz, err := z.EncodeAck(z.Ack{Tag: new(u256.Uint).SetBytes(z.TAG_ACK_SUCCESS[:]), InnerAck: inner})
	if err != nil {
		panic(err)
	}
	return bz
}

func mustZ26BatchAck(children [][]byte) []byte {
	inner, err := z.EncodeBatchAck(z.BatchAck{Acknowledgements: children})
	if err != nil {
		panic(err)
	}
	return mustZ26SuccessAck(inner)
}

// Output:
// batch_ack_count_mismatch ok
