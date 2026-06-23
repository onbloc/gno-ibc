package impl

import (
	"errors"

	types "gno.land/p/onbloc/ibc/union/types"

	u256 "gno.land/p/gnoswap/uint256"
	z "gno.land/p/onbloc/ibc/union/zkgm"
	core "gno.land/r/onbloc/ibc/union/core"
)

var (
	errInvalidForwardInstruction = errors.New("zkgm/v1: invalid forward instruction")
	errForwardMissingPrevDest    = errors.New("zkgm/v1: forward missing previous destination channel")
	errForwardMissingNextSource  = errors.New("zkgm/v1: forward missing next source channel")
	errForwardPrevDestMismatch   = errors.New("zkgm/v1: forward previous-destination mismatch")
	errForwardZeroTimeout        = errors.New("zkgm/v1: forward timeout timestamp must be non-zero")
)

// verifyForward checks the forwarded instruction is allowed and the timeout is set, then verifies the inner instruction.
// reference: https://github.com/unionlabs/union/blob/d91c5e94354e15801bd5f82dc658eae3b79f2dad/cosmwasm/app/ucs03-zkgm/src/contract.rs#L2969-L2995
func (v *ucs03ZkgmV1) verifyForward(_ int, rlm realm, funds *funds, channelId types.ChannelId, forward z.Forward) error {
	if !isAllowedForwardInstruction(forward.Instruction.Opcode) {
		return errInvalidForwardInstruction
	}

	if forward.TimeoutTimestamp == 0 {
		return errForwardZeroTimeout
	}

	return v.verifyInternal(0, rlm, funds, channelId, forward.Path, forward.Instruction)
}

// executeForward builds and dispatches the next-hop packet, recording the parent for async ack settlement.
// reference: https://github.com/unionlabs/union/blob/d91c5e94354e15801bd5f82dc658eae3b79f2dad/cosmwasm/app/ucs03-zkgm/src/contract.rs#L1392-L1497
func (v *ucs03ZkgmV1) executeForward(_ int, rlm realm, packet types.Packet, salt [32]byte, path *u256.Uint, forward z.Forward, intent bool) (types.RecvPacketResult, error) {
	// Recv skips verifyInternal (see impl.gno OnRecvPacket flow), so this opcode check is
	// the only line of defense on receive. Do not strip as redundant with
	// verifyForward.
	if !isAllowedForwardInstruction(forward.Instruction.Opcode) {
		return core.NewRecvPacketResult(types.PacketStatusUnknown, nil), errInvalidForwardInstruction
	}

	if intent {
		return core.NewRecvPacketResult(types.PacketStatusSuccess, cloneBytes(z.ACK_ERR_ONLY_MAKER)), nil
	}

	childPacket, err := buildForwardChild(packet, path, salt, forward)
	if err != nil {
		return core.NewRecvPacketResult(types.PacketStatusUnknown, nil), err
	}

	// Forward children construct ZkgmPacket directly; their salt is namespaced via
	// DeriveForwardSalt, not DeriveSenderSalt. Record the parent so the child's
	// resolution can write the deferred parent ack, then dispatch via core.
	v.store.SetInFlightPacket(0, rlm, forwardInFlightKey(childPacket), packet)
	core.BatchSend(cross(rlm), types.NewMsgBatchSend([]types.Packet{childPacket}))

	return core.NewRecvPacketResult(types.PacketStatusAsync, nil), nil
}

// handleForwardChild detects a forwarded child packet resolving on ack/timeout
// and writes the captured parent's deferred acknowledgement through core.
func (v *ucs03ZkgmV1) handleForwardChild(_ int, rlm realm, packet types.Packet, zp z.ZkgmPacket, ack []byte) bool {
	if !z.IsForwardedPacket(zp.Salt) {
		return false
	}

	key := forwardInFlightKey(packet)

	parent, ok := v.store.GetInFlightPacket(key)
	if !ok {
		return false
	}

	v.store.RemoveInFlightPacket(0, rlm, key)
	core.WriteAcknowledgement(cross(rlm), types.NewMsgWriteAcknowledgement(parent, ack))

	return true
}

// forwardInFlightKey derives the in-flight key from the child packet's commitment hash.
func forwardInFlightKey(packet types.Packet) string {
	return types.MustCommit(types.CommitPacket(packet)).String()
}

// buildForwardChild builds the next-hop packet, advancing the channel path and namespacing the salt.
func buildForwardChild(packet types.Packet, path *u256.Uint, parentSalt [32]byte, forward z.Forward) (types.Packet, error) {
	if forward.TimeoutTimestamp == 0 {
		return core.NewPacket(0, 0, nil, 0), errForwardZeroTimeout
	}

	tailPath, prevDestChannel := z.DequeueChannelFromPath(forward.Path)
	if prevDestChannel == 0 {
		return core.NewPacket(0, 0, nil, 0), errForwardMissingPrevDest
	}

	continuationPath, nextSourceChannel := z.DequeueChannelFromPath(tailPath)
	if nextSourceChannel == 0 {
		return core.NewPacket(0, 0, nil, 0), errForwardMissingNextSource
	}

	if packet.DestinationChannelId != types.ChannelId(prevDestChannel) {
		return core.NewPacket(0, 0, nil, 0), errForwardPrevDestMismatch
	}

	nextInstruction := forward.Instruction

	if !continuationPath.IsZero() {
		nextForward := z.Forward{
			Path:             continuationPath,
			TimeoutHeight:    0,
			TimeoutTimestamp: forward.TimeoutTimestamp,
			Instruction:      forward.Instruction,
		}

		forwardBytes, err := z.EncodeForward(nextForward)
		if err != nil {
			return core.NewPacket(0, 0, nil, 0), err
		}

		nextInstruction = z.Instruction{
			Version: z.INSTR_VERSION_0,
			Opcode:  z.OP_FORWARD,
			Operand: forwardBytes,
		}
	}

	intermediate, err := z.UpdateChannelPath(path, prevDestChannel)
	if err != nil {
		return core.NewPacket(0, 0, nil, 0), err
	}

	nextPath, err := z.UpdateChannelPath(intermediate, nextSourceChannel)
	if err != nil {
		return core.NewPacket(0, 0, nil, 0), err
	}

	childBytes, err := z.EncodeZkgmPacket(z.ZkgmPacket{
		Salt:        z.DeriveForwardSalt(parentSalt),
		Path:        nextPath,
		Instruction: nextInstruction,
	})
	if err != nil {
		return core.NewPacket(0, 0, nil, 0), err
	}

	sourceChannelId := types.ChannelId(nextSourceChannel)
	sourceChannel, err := core.GetChannel(sourceChannelId)
	if err != nil {
		return core.NewPacket(0, 0, nil, 0), err
	}

	return core.NewPacket(sourceChannelId, sourceChannel.CounterpartyChannelId, childBytes, types.Timestamp(forward.TimeoutTimestamp)), nil
}

// isAllowedForwardInstruction reports whether opcode may be forwarded.
func isAllowedForwardInstruction(opcode uint8) bool {
	return opcode == z.OP_CALL || opcode == z.OP_TOKEN_ORDER || opcode == z.OP_BATCH
}
