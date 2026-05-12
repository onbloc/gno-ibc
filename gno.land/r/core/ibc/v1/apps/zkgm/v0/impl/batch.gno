package impl

import (
	"chain"
	"errors"

	z "gno.land/p/gnoswap/ibc/zkgm"
	u256 "gno.land/p/gnoswap/uint256"
	core "gno.land/r/core/ibc/v1/core"
)

// TODO: cap batch.Instructions length once the upstream Solidity reference
// confirms a value (Reviewer flagged unbounded recursion as a DoS vector —
// each child runs full dispatchExecute incl. abi decode + keccak).
var errInvalidBatchInstruction = errors.New("zkgm/v1: invalid batch instruction")

func (v *ZkgmV1) verifyBatch(channelId core.ChannelId, sender string, sentCoins chain.Coins, parentSalt [32]byte, batch z.Batch) error {
	for i, instr := range batch.Instructions {
		if !isAllowedBatchInstruction(instr.Opcode) {
			return errInvalidBatchInstruction
		}
		childSalt := z.DeriveBatchSalt(u256.NewUint(uint64(i)), parentSalt)
		if err := v.dispatchVerify(channelId, sender, sentCoins, childSalt, instr); err != nil {
			return err
		}
	}
	return nil
}

func (v *ZkgmV1) executeBatch(packet core.Packet, relayer address, relayerMsg []byte, path *u256.Uint, parentSalt [32]byte, batch z.Batch, intent bool) ([]byte, error) {
	acks := make([][]byte, len(batch.Instructions))
	for i, instr := range batch.Instructions {
		if !isAllowedBatchInstruction(instr.Opcode) {
			return nil, errInvalidBatchInstruction
		}
		childSalt := z.DeriveBatchSalt(u256.NewUint(uint64(i)), parentSalt)
		childRes, err := v.dispatchExecute(packet, relayer, relayerMsg, path, childSalt, instr, intent)
		if err != nil {
			return nil, err
		}
		childAck := childRes.Ack
		if len(childAck) == 0 {
			panic("zkgm/v1: batch child returned empty ack")
		}
		// Spec: a single only-maker child aborts the entire batch — already-
		// processed children's state mutations stand (per Union v0 spec); the
		// outer ack signals "filled by maker, replay later" so the relayer
		// retries against a market-maker fill.
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

func (v *ZkgmV1) acknowledgeBatch(packet core.Packet, path *u256.Uint, parentSalt [32]byte, batch z.Batch, outerAck z.Ack) error {
	successful := outerAck.Tag != nil && outerAck.Tag.Eq(tagAckSuccess)
	var batchAck z.BatchAck
	if successful {
		decoded, err := z.DecodeBatchAck(outerAck.InnerAck)
		if err != nil {
			return err
		}
		batchAck = decoded
		if len(batchAck.Acknowledgements) != len(batch.Instructions) {
			return errors.New("zkgm/v1: batch ack count mismatch")
		}
	}
	// On outer-failure, per-child acks may be absent or untrusted; surface
	// universalErrorAck to every child so each handler takes its failure path
	// (e.g. token-order refund). Compute once, share the slice.
	var ueAck []byte
	if !successful {
		ueAck = universalErrorAck()
	}
	for i, instr := range batch.Instructions {
		childAck := ueAck
		if successful {
			childAck = batchAck.Acknowledgements[i]
		}
		childSalt := z.DeriveBatchSalt(u256.NewUint(uint64(i)), parentSalt)
		if err := v.dispatchAck(packet, path, childSalt, instr, childAck); err != nil {
			return err
		}
	}
	return nil
}

func (v *ZkgmV1) timeoutBatch(packet core.Packet, path *u256.Uint, parentSalt [32]byte, batch z.Batch) error {
	for i, instr := range batch.Instructions {
		childSalt := z.DeriveBatchSalt(u256.NewUint(uint64(i)), parentSalt)
		if err := v.dispatchTimeout(packet, path, childSalt, instr); err != nil {
			return err
		}
	}
	return nil
}

func isAllowedBatchInstruction(opcode uint8) bool {
	return opcode == z.OP_CALL || opcode == z.OP_TOKEN_ORDER
}
