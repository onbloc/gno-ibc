package zkgm

import (
	"testing"

	"gno.land/p/nt/uassert/v0"

	u256 "gno.land/p/gnoswap/uint256"
)

// Forward.Instruction.Operand is raw bytes, so an outer Forward whose
// instruction wraps another Forward must round-trip cleanly. Forward
// continuation rebuilds depend on this.
func TestSanityForwardOfForwardRoundTrip(t *testing.T) {
	innerCallBytes, err := EncodeCall(Call{
		Sender:           []byte("a"),
		ContractAddress:  []byte("b"),
		ContractCalldata: []byte("c"),
	})
	uassert.NoError(t, err)

	inner := Forward{
		Path:             u256.NewUint(0x42),
		TimeoutHeight:    100,
		TimeoutTimestamp: 1000,
		Instruction: Instruction{
			Version: INSTR_VERSION_0,
			Opcode:  OP_CALL,
			Operand: innerCallBytes,
		},
	}
	innerBytes, err := EncodeForward(inner)
	uassert.NoError(t, err)

	outer := Forward{
		Path:             u256.NewUint(0x101),
		TimeoutHeight:    200,
		TimeoutTimestamp: 2000,
		Instruction: Instruction{
			Version: INSTR_VERSION_0,
			Opcode:  OP_FORWARD,
			Operand: innerBytes,
		},
	}
	outerBytes, err := EncodeForward(outer)
	uassert.NoError(t, err)

	decoded, err := DecodeForward(outerBytes)
	uassert.NoError(t, err)
	uassert.Equal(t, uint64(2000), decoded.TimeoutTimestamp)
	uassert.Equal(t, uint64(200), decoded.TimeoutHeight)
	uassert.True(t, decoded.Path.Eq(u256.NewUint(0x101)))
	uassert.Equal(t, OP_FORWARD, decoded.Instruction.Opcode)

	decodedInner, err := DecodeForward(decoded.Instruction.Operand)
	uassert.NoError(t, err)
	uassert.Equal(t, uint64(1000), decodedInner.TimeoutTimestamp)
	uassert.Equal(t, OP_CALL, decodedInner.Instruction.Opcode)

	decodedCall, err := DecodeCall(decodedInner.Instruction.Operand)
	uassert.NoError(t, err)
	uassert.Equal(t, "a", string(decodedCall.Sender))
	uassert.Equal(t, "b", string(decodedCall.ContractAddress))
	uassert.Equal(t, "c", string(decodedCall.ContractCalldata))
}

// Forward → Batch[Call] round-trip. A final-hop continuation may dispatch a
// Batch as the final instruction.
func TestSanityForwardOfBatchRoundTrip(t *testing.T) {
	callBytes, err := EncodeCall(Call{Sender: []byte("s"), ContractAddress: []byte("r")})
	uassert.NoError(t, err)

	batchBytes, err := EncodeBatch(Batch{Instructions: []Instruction{
		{Version: INSTR_VERSION_0, Opcode: OP_CALL, Operand: callBytes},
	}})
	uassert.NoError(t, err)

	outer := Forward{
		Path:             u256.NewUint(0x7),
		TimeoutTimestamp: 3000,
		Instruction: Instruction{
			Version: INSTR_VERSION_0,
			Opcode:  OP_BATCH,
			Operand: batchBytes,
		},
	}
	outerBytes, err := EncodeForward(outer)
	uassert.NoError(t, err)

	decoded, err := DecodeForward(outerBytes)
	uassert.NoError(t, err)
	uassert.Equal(t, OP_BATCH, decoded.Instruction.Opcode)

	decodedBatch, err := DecodeBatch(decoded.Instruction.Operand)
	uassert.NoError(t, err)
	uassert.Equal(t, 1, len(decodedBatch.Instructions))
	uassert.Equal(t, OP_CALL, decodedBatch.Instructions[0].Opcode)
}
