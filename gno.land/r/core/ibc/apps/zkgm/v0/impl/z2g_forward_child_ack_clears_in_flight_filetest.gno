package main

import (
	"crypto/keccak256"
	"encoding/hex"

	"gno.land/p/aib/ibc/types"
	z "gno.land/p/gnoswap/ibc/zkgm"
	u256 "gno.land/p/gnoswap/uint256"
	zkgm "gno.land/r/gnoswap/ibc/apps/zkgm"
	_ "gno.land/r/gnoswap/ibc/apps/zkgm/v0/loader"
)

func main() {
	payload, hash := forwardedChildPayload()
	parent := types.NewPacket(12, "client-parent-src", "client-parent-dst", 0, mustPayload(mustForwardInstruction(z.Forward{Path: forwardPath(1, 2)})))
	zkgm.SetInFlightPacket(cross, zkgm.InFlightKey(hash), parent)

	_, before := zkgm.GetInFlightPacket(zkgm.InFlightKey(hash))
	err := zkgm.AsIBCApp().OnAcknowledgementPacket(cross, "client-2", "client-3", 21, mustAck(z.Ack{Tag: u256.NewUint(1), InnerAck: []byte{}}), payload)
	if err != nil {
		panic(err)
	}
	_, after := zkgm.GetInFlightPacket(zkgm.InFlightKey(hash))

	println("hash_len", len(hex.EncodeToString(hash[:])))
	println("in_flight_before", before)
	println("in_flight_after", after)
}

func forwardedChildPayload() (types.Payload, [32]byte) {
	childCall := mustCallInstruction("tracked")
	childBytes, err := z.EncodeZkgmPacket(z.ZkgmPacket{
		Salt:        z.DeriveForwardSalt([32]byte{0x0b}),
		Path:        forwardPath(8, 1, 2),
		Instruction: childCall,
	})
	if err != nil {
		panic(err)
	}
	return types.Payload{
		SourcePort:      "zkgm",
		DestinationPort: "zkgm",
		Version:         z.PROTOCOL_VERSION,
		Encoding:        "application/octet-stream",
		Value:           childBytes,
	}, keccak256.Sum256(childBytes)
}

func mustPayload(instr z.Instruction) types.Payload {
	packetBytes, err := z.EncodeZkgmPacket(z.ZkgmPacket{Path: u256.Zero(), Instruction: instr})
	if err != nil {
		panic(err)
	}
	return types.Payload{Value: packetBytes}
}

func mustCallInstruction(calldata string) z.Instruction {
	callBytes, err := z.EncodeCall(z.Call{
		Sender:           []byte("sender"),
		ContractAddress:  []byte("gno.land/r/gnoswap/ibc/apps/zkgm/testing/mock"),
		ContractCalldata: []byte(calldata),
	})
	if err != nil {
		panic(err)
	}
	return z.Instruction{Version: z.INSTR_VERSION_0, Opcode: z.OP_CALL, Operand: callBytes}
}

func mustForwardInstruction(forward z.Forward) z.Instruction {
	forwardBytes, err := z.EncodeForward(forward)
	if err != nil {
		panic(err)
	}
	return z.Instruction{Version: z.INSTR_VERSION_0, Opcode: z.OP_FORWARD, Operand: forwardBytes}
}

func mustAck(ack z.Ack) []byte {
	bz, err := z.EncodeAck(ack)
	if err != nil {
		panic(err)
	}
	return bz
}

func forwardPath(channels ...uint64) *u256.Uint {
	path := u256.Zero()
	for i, channel := range channels {
		path = new(u256.Uint).Or(path, new(u256.Uint).Lsh(u256.NewUint(channel), uint(32*i)))
	}
	return path
}

// Output:
// hash_len 64
// in_flight_before true
// in_flight_after false
