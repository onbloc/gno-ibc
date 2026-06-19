package impl

import (
	"errors"

	types "gno.land/p/onbloc/ibc/union/types"

	u256 "gno.land/p/gnoswap/uint256"
	z "gno.land/p/onbloc/ibc/union/zkgm"
)

// TODO: cap batch.Instructions length once the upstream Solidity reference
// confirms a value (Reviewer flagged unbounded recursion as a DoS vector —
// each child runs full dispatchExecute incl. abi decode + keccak).
var errInvalidBatchInstruction = errors.New("zkgm/v1: invalid batch instruction")

// verifyBatch verifies each allowed child instruction against the shared funds budget.
// reference: https://github.com/unionlabs/union/blob/d91c5e94354e15801bd5f82dc658eae3b79f2dad/cosmwasm/app/ucs03-zkgm/src/contract.rs#L2941-L2967
func (v *ucs03ZkgmV1) verifyBatch(_ int, rlm realm, channelId types.ChannelId, sender string, funds *funds, path *u256.Uint, parentSalt [32]byte, batch z.Batch) error {
	for i, instr := range batch.Instructions {
		if !isAllowedBatchInstruction(instr.Opcode) {
			return errInvalidBatchInstruction
		}
		childSalt := z.DeriveBatchSalt(u256.NewUint(uint64(i)), parentSalt)
		if err := v.dispatchVerify(0, rlm, channelId, sender, funds, path, childSalt, instr); err != nil {
			return err
		}
	}
	return nil
}

// executeBatch runs each child in order, aborting the whole batch on an only-maker child.
// reference: https://github.com/unionlabs/union/blob/d91c5e94354e15801bd5f82dc658eae3b79f2dad/cosmwasm/app/ucs03-zkgm/src/contract.rs#L1686-L1726
func (v *ucs03ZkgmV1) executeBatch(_ int, rlm realm, packet types.Packet, relayer address, relayerMsg []byte, path *u256.Uint, parentSalt [32]byte, batch z.Batch, intent bool) ([]byte, error) {
	acks := make([][]byte, len(batch.Instructions))
	for i, instr := range batch.Instructions {
		if !isAllowedBatchInstruction(instr.Opcode) {
			return nil, errInvalidBatchInstruction
		}
		childSalt := z.DeriveBatchSalt(u256.NewUint(uint64(i)), parentSalt)
		childRes, err := v.dispatchExecute(0, rlm, packet, relayer, relayerMsg, path, childSalt, instr, intent)
		if err != nil {
			return nil, err
		}
		childAck := childRes.Acknowledgement
		if len(childAck) == 0 {
			panic("zkgm/v1: batch child returned empty ack")
		}
		// Spec: a single only-maker child aborts the entire batch. Already-processed
		// children's state mutations stand (per Union v0 spec). The outer ack signals
		// "filled by maker, replay later" so the relayer retries against a market-maker
		// fill.
		if isOnlyMakerAck(childAck) {
			return cloneBytes(z.ACK_ERR_ONLY_MAKER), nil
		}
		acks[i] = childAck
	}
	batchAckBytes, err := z.EncodeBatchAck(z.BatchAck{Acknowledgements: acks})
	if err != nil {
		return nil, err
	}
	return z.EncodeAck(z.Ack{Tag: tagAckSuccess(), InnerAck: batchAckBytes})
}

// acknowledgeBatch fans the outer ack out to each child instruction.
func (v *ucs03ZkgmV1) acknowledgeBatch(_ int, rlm realm, packet types.Packet, path *u256.Uint, parentSalt [32]byte, batch z.Batch, outerAck z.Ack) error {
	successful := outerAck.Tag != nil && outerAck.Tag.Eq(tagAckSuccess())
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
		if err := v.dispatchAck(0, rlm, packet, path, childSalt, instr, childAck); err != nil {
			return err
		}
	}
	return nil
}

// timeoutBatch fans the timeout out to each child instruction.
func (v *ucs03ZkgmV1) timeoutBatch(_ int, rlm realm, packet types.Packet, path *u256.Uint, parentSalt [32]byte, batch z.Batch) error {
	for i, instr := range batch.Instructions {
		childSalt := z.DeriveBatchSalt(u256.NewUint(uint64(i)), parentSalt)
		if err := v.dispatchTimeout(0, rlm, packet, path, childSalt, instr); err != nil {
			return err
		}
	}
	return nil
}

// isAllowedBatchInstruction reports whether opcode may appear in a batch.
func isAllowedBatchInstruction(opcode uint8) bool {
	return opcode == z.OP_CALL || opcode == z.OP_TOKEN_ORDER
}
