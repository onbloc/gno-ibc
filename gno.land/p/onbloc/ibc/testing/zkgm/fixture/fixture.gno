// Package fixture is a small building-block toolkit for zkgm handler/dispatch
// tests. It does NOT ship pre-baked scenario values — each test assembles the
// exact ZkgmPacket / Ack it needs from these helpers and verifies it.
//
// It complements the in-tree zkgm encoders/decoders (z.Encode*, z.Decode*) with
// the boilerplate they don't cover:
//   - Ack composition over the tag / fill-type constants (Success/Failure/
//     ProtocolFill/MarketMakerFill/Batch).
//   - Instruction + ZkgmPacket assembly.
//   - A fail-fast Must wrapper and a distinguishable-salt helper.
//
// Constants and shapes mirror union `ucs03-zkgm` `com.rs` via the zkgm package.
package fixture

import (
	u256 "gno.land/p/gnoswap/uint256"
	z "gno.land/p/onbloc/ibc/union/zkgm"
)

// Must unwraps an (bytes, error) encode/decode result, panicking on error. In a
// test an encoding error is a test bug, not a condition to handle, so this keeps
// call sites flat: data := fixture.Must(z.EncodeCall(call)).
func Must(b []byte, err error) []byte {
	if err != nil {
		panic(err)
	}

	return b
}

// Instruction assembles an Instruction from a version, opcode and ABI-encoded
// operand.
func Instruction(version, opcode uint8, operand []byte) z.Instruction {
	return z.Instruction{Version: version, Opcode: opcode, Operand: operand}
}

// Packet assembles a ZkgmPacket envelope from a salt, path and top-level
// instruction.
func Packet(salt [32]byte, path uint64, instr z.Instruction) z.ZkgmPacket {
	return z.ZkgmPacket{Salt: salt, Path: u256.NewUint(path), Instruction: instr}
}

// EncodePacket ABI-encodes a ZkgmPacket (the bytes carried as packet.Data over
// IBC), panicking on error.
func EncodePacket(p z.ZkgmPacket) []byte {
	return Must(z.EncodeZkgmPacket(p))
}

// SuccessAck wraps an inner ack as the canonical success envelope
// Ack{tag=TAG_ACK_SUCCESS, inner_ack=inner}.
func SuccessAck(inner []byte) []byte {
	return Must(z.EncodeAck(z.Ack{
		Tag:      z.Uint256FromBytes32(z.TAG_ACK_SUCCESS),
		InnerAck: inner,
	}))
}

// FailureAck wraps an inner ack as the canonical failure envelope
// Ack{tag=TAG_ACK_FAILURE, inner_ack=inner}.
func FailureAck(inner []byte) []byte {
	return Must(z.EncodeAck(z.Ack{
		Tag:      z.Uint256FromBytes32(z.TAG_ACK_FAILURE),
		InnerAck: inner,
	}))
}

// ProtocolFillAck is the TokenOrder inner ack for a protocol-filled order
// (TokenOrderAck{FILL_TYPE_PROTOCOL, market_maker=empty}).
func ProtocolFillAck() []byte {
	return Must(z.EncodeTokenOrderAck(z.TokenOrderAck{
		FillType:    z.Uint256FromBytes32(z.FILL_TYPE_PROTOCOL),
		MarketMaker: nil,
	}))
}

// MarketMakerFillAck is the TokenOrder inner ack for a marketmaker-filled order
// (TokenOrderAck{FILL_TYPE_MARKETMAKER, market_maker=maker}).
func MarketMakerFillAck(maker []byte) []byte {
	return Must(z.EncodeTokenOrderAck(z.TokenOrderAck{
		FillType:    z.Uint256FromBytes32(z.FILL_TYPE_MARKETMAKER),
		MarketMaker: maker,
	}))
}

// BatchAck wraps per-sub-instruction inner acks as a BatchAck.
func BatchAck(innerAcks [][]byte) []byte {
	return Must(z.EncodeBatchAck(z.BatchAck{Acknowledgements: innerAcks}))
}

// Fixed32 returns a 32-byte array filled with the given byte — handy for
// per-scenario distinguishable salts (e.g. fixture.Fixed32(0x11)).
func Fixed32(fill byte) [32]byte {
	var b [32]byte
	for i := range b {
		b[i] = fill
	}

	return b
}
