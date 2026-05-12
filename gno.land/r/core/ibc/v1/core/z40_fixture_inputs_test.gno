package core

import (
	"testing"

	z "gno.land/p/gnoswap/ibc/zkgm"
	u256 "gno.land/p/gnoswap/uint256"
)

const z40MockReceiverPath = "gno.land/r/gnoswap/ibc/v1/apps/zkgm/testing/mock"

func TestZ40BatchFixtureInputPaths(t *testing.T) {
	mixedPacket := z40BatchPacket(10, z.Batch{Instructions: []z.Instruction{
		z40CallInstruction("batch-call"),
		z40TokenOrderInstruction("ibc/batch-quote"),
	}})
	assertH256Hex(t, "z40 mixed batch packet commitment key", PacketCommitmentPath(mixedPacket), "0x642c27b2a9c2cbe440533099564bb5326041acfc25c5142322e3c453a50570c3")
	assertH256Hex(t, "z40 mixed batch packet commitment value", COMMITMENT_MAGIC, "0x0100000000000000000000000000000000000000000000000000000000000000")

	panicPacket := z40BatchPacket(11, z.Batch{Instructions: []z.Instruction{
		z40CallInstruction("panic-call"),
		z40TokenOrderInstruction("ibc/batch-panic-quote"),
	}})
	assertH256Hex(t, "z40 panic batch packet commitment key", PacketCommitmentPath(panicPacket), "0x5650289645e1d5dc8de38e678c37ec8a608cc7befffed6d0b62359403da79567")
	assertH256Hex(t, "z40 panic batch packet commitment value", COMMITMENT_MAGIC, "0x0100000000000000000000000000000000000000000000000000000000000000")
}

func z40BatchPacket(sequence Sequence, batch z.Batch) Packet {
	batchBytes, err := z.EncodeBatch(batch)
	if err != nil {
		panic(err)
	}
	packetBytes, err := z.EncodeZkgmPacket(z.ZkgmPacket{
		Path: u256.Zero(),
		Instruction: z.Instruction{
			Version: z.INSTR_VERSION_0,
			Opcode:  z.OP_BATCH,
			Operand: batchBytes,
		},
	})
	if err != nil {
		panic(err)
	}
	return Packet{
		Sequence:             sequence,
		SourceChannelId:      2,
		DestinationChannelId: 1,
		Data:                 Bytes(packetBytes),
		TimeoutTimestamp:     0,
	}
}

func z40CallInstruction(calldata string) z.Instruction {
	callBytes, err := z.EncodeCall(z.Call{
		Sender:           []byte("sender"),
		ContractAddress:  []byte(z40MockReceiverPath),
		ContractCalldata: []byte(calldata),
	})
	if err != nil {
		panic(err)
	}
	return z.Instruction{Version: z.INSTR_VERSION_0, Opcode: z.OP_CALL, Operand: callBytes}
}

func z40TokenOrderInstruction(quoteToken string) z.Instruction {
	orderBytes, err := z.EncodeTokenOrderV2(z.TokenOrderV2{
		Sender:      []byte("sender"),
		Receiver:    []byte("g1wymu47drhr0kuq2098m792lytgtj2nyx77yrsm"),
		BaseToken:   []byte("ugnot"),
		BaseAmount:  u256.NewUint(100),
		QuoteToken:  []byte(quoteToken),
		QuoteAmount: u256.NewUint(21),
		Kind:        z.TOKEN_ORDER_KIND_ESCROW,
	})
	if err != nil {
		panic(err)
	}
	return z.Instruction{Version: z.INSTR_VERSION_2, Opcode: z.OP_TOKEN_ORDER, Operand: orderBytes}
}
