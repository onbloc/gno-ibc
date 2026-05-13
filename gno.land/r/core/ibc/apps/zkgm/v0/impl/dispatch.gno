package impl

import (
	"chain"
	"errors"

	"gno.land/p/aib/ibc/types"
	z "gno.land/p/gnoswap/ibc/zkgm"
	u256 "gno.land/p/gnoswap/uint256"
	"gno.land/p/nt/ufmt/v0"
	zkgm "gno.land/r/gnoswap/ibc/apps/zkgm"
)

// ZKGM v0 instruction dispatcher.
//
// Child handlers must treat `path *u256.Uint` as read-only. gnoswap/uint256
// arithmetic mutates the receiver in place, so mutating path inside one batch
// child would leak into sibling children.

func (v *ZkgmV0) dispatchVerify(channelID string, sender string, sentCoins chain.Coins, path *u256.Uint, instr z.Instruction) error {
	switch instr.Opcode {
	case z.OP_TOKEN_ORDER:
		order, err := decodeOrderInstruction(instr)
		if err != nil {
			return err
		}
		return v.verifyTokenOrderV2(channelID, sender, sentCoins, path, order)
	case z.OP_CALL:
		call, err := decodeCallInstruction(instr)
		if err != nil {
			return err
		}
		return v.verifyCall(sender, call)
	case z.OP_BATCH:
		batch, err := decodeBatchInstruction(instr)
		if err != nil {
			return err
		}
		return v.verifyBatch(channelID, sender, sentCoins, path, batch)
	case z.OP_FORWARD:
		forward, err := decodeForwardInstruction(instr)
		if err != nil {
			return err
		}
		return v.verifyForward(channelID, sender, sentCoins, path, forward)
	default:
		return errors.New("zkgm/v0: unsupported opcode")
	}
}

func (v *ZkgmV0) dispatchExecute(req zkgm.RecvRequest, path *u256.Uint, salt [32]byte, instr z.Instruction, intent bool) (types.RecvPacketResult, error) {
	switch instr.Opcode {
	case z.OP_TOKEN_ORDER:
		order, err := decodeOrderInstruction(instr)
		if err != nil {
			return types.RecvPacketResult{}, err
		}
		return v.executeTokenOrderV2(req, path, order)
	case z.OP_CALL:
		call, err := decodeCallInstruction(instr)
		if err != nil {
			return types.RecvPacketResult{}, err
		}
		return v.executeCall(req, path, call)
	case z.OP_BATCH:
		batch, err := decodeBatchInstruction(instr)
		if err != nil {
			return types.RecvPacketResult{}, err
		}
		ack, err := v.executeBatch(req, path, salt, batch, intent)
		if err != nil {
			return types.RecvPacketResult{}, err
		}
		return types.RecvPacketResult{Status: types.PacketStatus_Success, Acknowledgement: ack}, nil
	case z.OP_FORWARD:
		forward, err := decodeForwardInstruction(instr)
		if err != nil {
			return types.RecvPacketResult{}, err
		}
		return v.executeForward(req, path, salt, forward, intent)
	default:
		return types.RecvPacketResult{}, errors.New("zkgm/v0: unsupported opcode")
	}
}

func (v *ZkgmV0) dispatchAck(req zkgm.AckRequest, path *u256.Uint, salt [32]byte, instr z.Instruction, ackBytes []byte) error {
	switch instr.Opcode {
	case z.OP_TOKEN_ORDER:
		order, err := decodeOrderInstruction(instr)
		if err != nil {
			return err
		}
		if isUniversalErrorAck(ackBytes) {
			return v.refundV2(req.SourceClient, path, order)
		}
		ack, err := z.DecodeAck(ackBytes)
		if err != nil {
			return err
		}
		return v.acknowledgeTokenOrderV2(req.SourceClient, path, order, ack)
	case z.OP_CALL:
		call, err := decodeCallInstruction(instr)
		if err != nil {
			return err
		}
		return v.acknowledgeCall(req, path, call)
	case z.OP_BATCH:
		batch, err := decodeBatchInstruction(instr)
		if err != nil {
			return err
		}
		if isUniversalErrorAck(ackBytes) {
			return v.acknowledgeBatch(req, path, salt, batch, z.Ack{Tag: tagAckFailure})
		}
		ack, err := z.DecodeAck(ackBytes)
		if err != nil {
			return err
		}
		return v.acknowledgeBatch(req, path, salt, batch, ack)
	case z.OP_FORWARD:
		forward, err := decodeForwardInstruction(instr)
		if err != nil {
			return err
		}
		ack, err := z.DecodeAck(ackBytes)
		if err != nil {
			return err
		}
		return v.acknowledgeForward(req, path, salt, forward, ack)
	default:
		return errors.New("zkgm/v0: unsupported opcode")
	}
}

func (v *ZkgmV0) dispatchTimeout(req zkgm.TimeoutRequest, path *u256.Uint, salt [32]byte, instr z.Instruction) error {
	switch instr.Opcode {
	case z.OP_TOKEN_ORDER:
		order, err := decodeOrderInstruction(instr)
		if err != nil {
			return err
		}
		return v.refundV2(req.SourceClient, path, order)
	case z.OP_CALL:
		call, err := decodeCallInstruction(instr)
		if err != nil {
			return err
		}
		return v.timeoutCall(req, path, call)
	case z.OP_BATCH:
		batch, err := decodeBatchInstruction(instr)
		if err != nil {
			return err
		}
		return v.timeoutBatch(req, path, salt, batch)
	case z.OP_FORWARD:
		forward, err := decodeForwardInstruction(instr)
		if err != nil {
			return err
		}
		return v.timeoutForward(req, path, salt, forward)
	default:
		return errors.New("zkgm/v0: unsupported opcode")
	}
}

func isOnlyMakerAck(ack []byte) bool {
	return equalBytes(ack, z.ACK_ERR_ONLY_MAKER)
}

// equalBytes is used instead of bytes.Equal because bytes.Equal does
// string(a)==string(b) internally, which panics on readonly cross-realm
// slices like z.ACK_ERR_ONLY_MAKER.
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
