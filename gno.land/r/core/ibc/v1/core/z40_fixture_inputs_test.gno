package core

import (
	"testing"

	z "gno.land/p/gnoswap/ibc/zkgm"
	u256 "gno.land/p/gnoswap/uint256"
)

const z40MockReceiverPath = "gno.land/r/gnoswap/ibc/v1/apps/zkgm/testing/mock"

func TestZ40BatchFixtureInputPaths(t *testing.T) {
	mixedPacket := z40BatchPacket(z.Batch{Instructions: []z.Instruction{
		z40CallInstruction("batch-call"),
		z40TokenOrderInstruction("ibc/batch-quote"),
	}})
	assertH256Hex(t, "z40 mixed batch packet commitment key", PacketCommitmentPath(mixedPacket), "0xa27e1b52c3beaeb1c4b3c6afb3bb6000536eb98562c019f0109f7b1274a3d102")
	assertH256Hex(t, "z40 mixed batch packet commitment value", COMMITMENT_MAGIC, "0x0100000000000000000000000000000000000000000000000000000000000000")

	panicPacket := z40BatchPacket(z.Batch{Instructions: []z.Instruction{
		z40CallInstruction("panic-call"),
		z40TokenOrderInstruction("ibc/batch-panic-quote"),
	}})
	assertH256Hex(t, "z40 panic batch packet commitment key", PacketCommitmentPath(panicPacket), "0x9102811e2a4d94c7593e8711e65c4163820045992a2ab08e771615a067ca23cd")
	assertH256Hex(t, "z40 panic batch packet commitment value", COMMITMENT_MAGIC, "0x0100000000000000000000000000000000000000000000000000000000000000")
}

func z40BatchPacket(batch z.Batch) Packet {
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
