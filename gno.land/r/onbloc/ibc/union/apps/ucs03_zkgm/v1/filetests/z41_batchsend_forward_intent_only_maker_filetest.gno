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

const z41ReceiverPath = "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/testing/mock"

var t *testing.T

func main(cur realm) {
	app := impl.NewUCS03ZkgmV1(zkgm.NewStore())
	forward := z.Forward{
		Path:             mustZ41ForwardPath(2, 3),
		TimeoutTimestamp: 999,
		Instruction:      mustZ41CallInstruction("forward-roundtrip"),
	}
	packet := types.NewPacket(types.ChannelId(1), types.ChannelId(2), mustZ41PacketData(mustZ41ForwardInstruction(forward)), 0)

	println("[SCENARIO] forward intent rejects maker-only result")
	uassert.AbortsContains(t, cur, "zkgm: only maker", func() {
		app.OnIntentRecvPacket(0, cur, packet, address("g1maker"), []byte("maker-msg"))
	})
	println("forward_intent_only_maker", "ok")
}

func mustZ41ForwardPath(channels ...uint32) *u256.Uint {
	path := u256.Zero()
	for _, channel := range channels {
		next, err := z.UpdateChannelPath(path, channel)
		if err != nil {
			panic(err)
		}
		path = next
	}
	return path
}

func mustZ41CallInstruction(calldata string) z.Instruction {
	bz, err := z.EncodeCall(z.Call{
		Sender:           []byte("sender"),
		ContractAddress:  []byte(z41ReceiverPath),
		ContractCalldata: []byte(calldata),
	})
	if err != nil {
		panic(err)
	}
	return z.Instruction{Version: z.INSTR_VERSION_0, Opcode: z.OP_CALL, Operand: bz}
}

func mustZ41ForwardInstruction(forward z.Forward) z.Instruction {
	bz, err := z.EncodeForward(forward)
	if err != nil {
		panic(err)
	}
	return z.Instruction{Version: z.INSTR_VERSION_0, Opcode: z.OP_FORWARD, Operand: bz}
}

func mustZ41PacketData(instr z.Instruction) []byte {
	bz, err := z.EncodeZkgmPacket(z.ZkgmPacket{Path: u256.Zero(), Instruction: instr})
	if err != nil {
		panic(err)
	}
	return bz
}

// Output:
// [SCENARIO] forward intent rejects maker-only result
// forward_intent_only_maker ok
