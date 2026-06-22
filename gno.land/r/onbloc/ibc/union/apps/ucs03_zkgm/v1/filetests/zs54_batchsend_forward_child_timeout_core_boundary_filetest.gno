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

const z54ReceiverPath = "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/testing/mock"

var t *testing.T

func main(cur realm) {
	store := zkgm.NewStore()
	app := impl.NewUCS03ZkgmV1(store)
	parentPacket := types.NewPacket(types.ChannelId(1), types.ChannelId(2), mustZS54PacketData([32]byte{}, mustZS54CallInstruction("parent")), 0)
	childSalt := z.DeriveForwardSalt([32]byte{})
	childPacket := types.NewPacket(types.ChannelId(3), types.ChannelId(4), mustZS54PacketData(childSalt, mustZS54CallInstruction("child")), types.Timestamp(1))
	childKey := types.MustCommit(types.CommitPacket(childPacket)).String()
	store.SetInFlightPacket(0, cur, childKey, parentPacket)

	println("[SCENARIO] forwarded child timeout reaches core ack boundary")
	uassert.AbortsContains(t, cur, "core: implementation not installed", func() {
		app.OnTimeoutPacket(0, cur, childPacket, address("g1relayer"))
	})
	_, inFlight := store.GetInFlightPacket(childKey)
	println("in_flight_after_aborted_core_write", inFlight)
	println("forward_child_timeout_core_boundary", "ok")
}

func mustZS54CallInstruction(calldata string) z.Instruction {
	bz, err := z.EncodeCall(z.Call{
		Sender:           []byte("sender"),
		ContractAddress:  []byte(z54ReceiverPath),
		ContractCalldata: []byte(calldata),
	})
	if err != nil {
		panic(err)
	}
	return z.Instruction{Version: z.INSTR_VERSION_0, Opcode: z.OP_CALL, Operand: bz}
}

func mustZS54PacketData(salt [32]byte, instr z.Instruction) []byte {
	bz, err := z.EncodeZkgmPacket(z.ZkgmPacket{Salt: salt, Path: u256.Zero(), Instruction: instr})
	if err != nil {
		panic(err)
	}
	return bz
}

// Output:
// [SCENARIO] forwarded child timeout reaches core ack boundary
// in_flight_after_aborted_core_write false
// forward_child_timeout_core_boundary ok
