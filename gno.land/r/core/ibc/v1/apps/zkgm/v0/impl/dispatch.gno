package impl

import (
	"errors"

	z "gno.land/p/gnoswap/ibc/zkgm"
	u256 "gno.land/p/gnoswap/uint256"
	"gno.land/p/nt/ufmt/v0"
	core "gno.land/r/core/ibc/v1/core"
)

func (v *ZkgmV1) dispatchVerify(channelId core.ChannelId, salt [32]byte, instr z.Instruction) error {
	switch instr.Opcode {
	case z.OP_TOKEN_ORDER:
		if _, err := decodeOrderInstruction(instr); err != nil {
			return err
		}
		return errors.New("zkgm/v1: token order verify not implemented")
	case z.OP_CALL:
		if _, err := decodeCallInstruction(instr); err != nil {
			return err
		}
		return errors.New("zkgm/v1: call verify not implemented")
	case z.OP_BATCH:
		if _, err := decodeBatchInstruction(instr); err != nil {
			return err
		}
		return errors.New("zkgm/v1: batch verify not implemented")
	case z.OP_FORWARD:
		if _, err := decodeForwardInstruction(instr); err != nil {
			return err
		}
		return errors.New("zkgm/v1: forward verify not implemented")
	default:
		return errors.New("zkgm/v1: unsupported opcode")
	}
}

func (v *ZkgmV1) dispatchExecute(packet core.Packet, path *u256.Uint, salt [32]byte, instr z.Instruction, intent bool) (result core.RecvPacketResult, err error) {
	defer func() {
		if r := recover(); r != nil {
			result = failureResult(universalErrorAck())
			err = nil
		}
	}()

	switch instr.Opcode {
	case z.OP_TOKEN_ORDER:
		if _, err := decodeOrderInstruction(instr); err != nil {
			return core.RecvPacketResult{}, err
		}
		panic("zkgm/v1: token order execute not implemented")
	case z.OP_CALL:
		if _, err := decodeCallInstruction(instr); err != nil {
			return core.RecvPacketResult{}, err
		}
		panic("zkgm/v1: call execute not implemented")
	case z.OP_BATCH:
		if _, err := decodeBatchInstruction(instr); err != nil {
			return core.RecvPacketResult{}, err
		}
		panic("zkgm/v1: batch execute not implemented")
	case z.OP_FORWARD:
		if _, err := decodeForwardInstruction(instr); err != nil {
			return core.RecvPacketResult{}, err
		}
		panic("zkgm/v1: forward execute not implemented")
	default:
		return core.RecvPacketResult{}, errors.New("zkgm/v1: unsupported opcode")
	}
}

func (v *ZkgmV1) dispatchAck(packet core.Packet, path *u256.Uint, salt [32]byte, instr z.Instruction, ack core.Bytes) error {
	switch instr.Opcode {
	case z.OP_TOKEN_ORDER:
		if _, err := decodeOrderInstruction(instr); err != nil {
			return err
		}
		return errors.New("zkgm/v1: token order ack not implemented")
	case z.OP_CALL:
		if _, err := decodeCallInstruction(instr); err != nil {
			return err
		}
		return errors.New("zkgm/v1: call ack not implemented")
	case z.OP_BATCH:
		if _, err := decodeBatchInstruction(instr); err != nil {
			return err
		}
		return errors.New("zkgm/v1: batch ack not implemented")
	case z.OP_FORWARD:
		if _, err := decodeForwardInstruction(instr); err != nil {
			return err
		}
		return errors.New("zkgm/v1: forward ack not implemented")
	default:
		return errors.New("zkgm/v1: unsupported opcode")
	}
}

func (v *ZkgmV1) dispatchTimeout(packet core.Packet, path *u256.Uint, salt [32]byte, instr z.Instruction) error {
	switch instr.Opcode {
	case z.OP_TOKEN_ORDER:
		if _, err := decodeOrderInstruction(instr); err != nil {
			return err
		}
		return errors.New("zkgm/v1: token order timeout not implemented")
	case z.OP_CALL:
		if _, err := decodeCallInstruction(instr); err != nil {
			return err
		}
		return errors.New("zkgm/v1: call timeout not implemented")
	case z.OP_BATCH:
		if _, err := decodeBatchInstruction(instr); err != nil {
			return err
		}
		return errors.New("zkgm/v1: batch timeout not implemented")
	case z.OP_FORWARD:
		if _, err := decodeForwardInstruction(instr); err != nil {
			return err
		}
		return errors.New("zkgm/v1: forward timeout not implemented")
	default:
		return errors.New("zkgm/v1: unsupported opcode")
	}
}

func decodeOrderInstruction(instr z.Instruction) (z.TokenOrderV2, error) {
	if instr.Version != z.INSTR_VERSION_2 {
		return z.TokenOrderV2{}, errors.New("zkgm/v1: unsupported token order version")
	}
	return z.DecodeTokenOrderV2(instr.Operand)
}

func decodeCallInstruction(instr z.Instruction) (z.Call, error) {
	if instr.Version != z.INSTR_VERSION_0 {
		return z.Call{}, errors.New("zkgm/v1: unsupported call version")
	}
	return z.DecodeCall(instr.Operand)
}

func decodeBatchInstruction(instr z.Instruction) (z.Batch, error) {
	if instr.Version != z.INSTR_VERSION_0 {
		return z.Batch{}, errors.New("zkgm/v1: unsupported batch version")
	}
	return z.DecodeBatch(instr.Operand)
}

func decodeForwardInstruction(instr z.Instruction) (z.Forward, error) {
	if instr.Version != z.INSTR_VERSION_0 {
		return z.Forward{}, errors.New("zkgm/v1: unsupported forward version")
	}
	return z.DecodeForward(instr.Operand)
}

func failureResult(ack []byte) core.RecvPacketResult {
	return core.NewRecvPacketResult(cross, core.PacketStatusFailure, ack)
}

func universalErrorAck() []byte {
	ack, err := z.EncodeAck(z.Ack{
		Tag:      u256.NewUint(0),
		InnerAck: []byte("UNIVERSAL_ERROR"),
	})
	if err != nil {
		return []byte("UNIVERSAL_ERROR")
	}
	return ack
}

func isOnlyMakerAck(ack []byte) bool {
	return equalBytes(ack, z.ACK_ERR_ONLY_MAKER)
}

func equalBytes(a []byte, b []byte) bool {
	if len(a) != len(b) {
		return false
	}
	for i := 0; i < len(a); i++ {
		if a[i] != b[i] {
			return false
		}
	}
	return true
}

func extractPanicMessage(r any) string {
	switch v := r.(type) {
	case string:
		return v
	case error:
		return v.Error()
	default:
		return ufmt.Sprintf("%v", v)
	}
}
