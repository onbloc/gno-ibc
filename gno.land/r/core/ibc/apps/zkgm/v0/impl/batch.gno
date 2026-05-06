package impl

import (
	"chain"
	"errors"

	"gno.land/p/aib/ibc/types"
	z "gno.land/p/gnoswap/ibc/zkgm"
	u256 "gno.land/p/gnoswap/uint256"
	zkgm "gno.land/r/gnoswap/ibc/apps/zkgm"
)

func (v *ZkgmV0) verifyBatch(channelID string, sender string, sentCoins chain.Coins, path *u256.Uint, batch z.Batch) error {
	for _, instr := range batch.Instructions {
		if !isAllowedBatchInstruction(instr.Opcode) {
			return errors.New("zkgm/v0: invalid batch instruction")
		}
		if err := v.dispatchVerify(channelID, sender, sentCoins, path, instr); err != nil {
			return err
		}
	}
	return nil
}

func (v *ZkgmV0) executeBatch(req zkgm.RecvRequest, path *u256.Uint, parentSalt [32]byte, batch z.Batch, intent bool) ([]byte, error) {
	acks := make([][]byte, len(batch.Instructions))
	for i, instr := range batch.Instructions {
		if !isAllowedBatchInstruction(instr.Opcode) {
			return nil, errors.New("zkgm/v0: invalid batch instruction")
		}
		childSalt := z.DeriveBatchSalt(u256.NewUint(uint64(i)), parentSalt)
		childRes, err := v.dispatchExecute(req, path, childSalt, instr, intent)
		if err != nil {
			return nil, err
		}
		childAck := childRes.Acknowledgement
		if len(childAck) == 0 {
			panic("zkgm/v0: batch child returned empty ack")
		}
		if isOnlyMakerAck(childAck) {
			return cloneBytes(z.ACK_ERR_ONLY_MAKER), nil
		}
		acks[i] = childAck
	}
	batchAckBytes, err := z.EncodeBatchAck(z.BatchAck{Acknowledgements: acks})
	if err != nil {
		return nil, err
	}
	return z.EncodeAck(z.Ack{Tag: tagAckSuccess, InnerAck: batchAckBytes})
}

func (v *ZkgmV0) acknowledgeBatch(req zkgm.AckRequest, path *u256.Uint, parentSalt [32]byte, batch z.Batch, outerAck z.Ack) error {
	successful := outerAck.Tag != nil && outerAck.Tag.Eq(tagAckSuccess)
	var batchAck z.BatchAck
	if successful {
		decoded, err := z.DecodeBatchAck(outerAck.InnerAck)
		if err != nil {
			return err
		}
		batchAck = decoded
		if len(batchAck.Acknowledgements) != len(batch.Instructions) {
			return errors.New("zkgm/v0: batch ack count mismatch")
		}
	}
	for i, instr := range batch.Instructions {
		var childAck []byte
		if successful {
			childAck = batchAck.Acknowledgements[i]
		} else {
			childAck = types.UniversalErrorAcknowledgement()
		}
		childSalt := z.DeriveBatchSalt(u256.NewUint(uint64(i)), parentSalt)
		if err := v.dispatchAck(req, path, childSalt, instr, childAck); err != nil {
			return err
		}
	}
	return nil
}

func (v *ZkgmV0) timeoutBatch(req zkgm.TimeoutRequest, path *u256.Uint, parentSalt [32]byte, batch z.Batch) error {
	for i, instr := range batch.Instructions {
		childSalt := z.DeriveBatchSalt(u256.NewUint(uint64(i)), parentSalt)
		if err := v.dispatchTimeout(req, path, childSalt, instr); err != nil {
			return err
		}
	}
	return nil
}

func isAllowedBatchInstruction(opcode uint8) bool {
	return opcode == z.OP_CALL || opcode == z.OP_TOKEN_ORDER
}

func decodeBatchInstruction(instr z.Instruction) (z.Batch, error) {
	if instr.Version != z.INSTR_VERSION_0 {
		return z.Batch{}, errors.New("zkgm/v0: unsupported batch version")
	}
	return z.DecodeBatch(instr.Operand)
}
