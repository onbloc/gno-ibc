package impl

import (
	"errors"

	z "gno.land/p/gnoswap/ibc/zkgm"
	u256 "gno.land/p/gnoswap/uint256"
	core "gno.land/r/core/ibc/v1/core"
	zkgm "gno.land/r/gnoswap/ibc/v1/apps/zkgm"
)

var (
	errInvalidForwardInstruction = errors.New("zkgm/v1: invalid forward instruction")
	errForwardHopExceeded        = errors.New("zkgm/v1: forward hop count exceeded")
	errForwardMissingPrevDest    = errors.New("zkgm/v1: forward missing previous destination channel")
	errForwardMissingNextSource  = errors.New("zkgm/v1: forward missing next source channel")
	errForwardPrevDestMismatch   = errors.New("zkgm/v1: forward previous-destination mismatch")
	errForwardZeroTimeout        = errors.New("zkgm/v1: forward timeout timestamp must be non-zero")
)

func (v *ZkgmV1) verifyForward(cur realm, channelId core.ChannelId, sender string, budget *sentCoinBudget, path *u256.Uint, salt [32]byte, forward z.Forward) error {
	if !isAllowedForwardInstruction(forward.Instruction.Opcode) {
		return errInvalidForwardInstruction
	}
	if z.HopCount(forward.Path) > z.MaxHops {
		return errForwardHopExceeded
	}

	return v.dispatchVerify(cur, channelId, sender, budget, forward.Path, z.DeriveForwardSalt(salt), forward.Instruction)
}

func (v *ZkgmV1) executeForward(cur realm, packet core.Packet, path *u256.Uint, parentSalt [32]byte, forward z.Forward, intent bool) (core.RecvPacketResult, error) {
	// Recv skips dispatchVerify (see impl.gno Recv flow), so this opcode check
	// is the only line of defense on receive. Do not strip as redundant with
	// verifyForward.
	if !isAllowedForwardInstruction(forward.Instruction.Opcode) {
		return core.NewRecvPacketResult(cross(cur), core.PacketStatusUnknown, nil), errInvalidForwardInstruction
	}
	if intent {
		return core.NewRecvPacketResult(cross(cur), core.PacketStatusSuccess, cloneBytes(z.ACK_ERR_ONLY_MAKER)), nil
	}

	childPacket, err := buildForwardChild(cur, packet, path, parentSalt, forward)
	if err != nil {
		return core.NewRecvPacketResult(cross(cur), core.PacketStatusUnknown, nil), err
	}

	// Forward children construct ZkgmPacket directly via BatchSend. Their salt
	// is namespaced via DeriveForwardSalt, not DeriveSenderSalt.
	zkgm.BatchSend(cross(cur), core.NewMsgBatchSend(cross(cur), []core.Packet{childPacket}))
	zkgm.SetInFlightPacket(cross(cur), forwardInFlightKey(cur, childPacket), zkgm.NewInFlightValue(cross(cur), packet))

	return core.NewRecvPacketResult(cross(cur), core.PacketStatusAsync, nil), nil
}

func (v *ZkgmV1) acknowledgeForward(cur realm, packet core.Packet, path *u256.Uint, salt [32]byte, forward z.Forward, ack z.Ack) error {
	return v.dispatchAck(cur, packet, forward.Path, salt, forward.Instruction, ack.InnerAck)
}

func (v *ZkgmV1) timeoutForward(cur realm, packet core.Packet, path *u256.Uint, salt [32]byte, forward z.Forward) error {
	return v.dispatchTimeout(cur, packet, forward.Path, salt, forward.Instruction)
}

func buildForwardChild(cur realm, packet core.Packet, path *u256.Uint, parentSalt [32]byte, forward z.Forward) (core.Packet, error) {
	if forward.TimeoutTimestamp == 0 {
		return core.NewPacket(cross(cur), 0, 0, nil, 0, 0), errForwardZeroTimeout
	}

	tailPath, prevDestChannel := z.DequeueChannelFromPath(forward.Path)
	if prevDestChannel == 0 {
		return core.NewPacket(cross(cur), 0, 0, nil, 0, 0), errForwardMissingPrevDest
	}

	continuationPath, nextSourceChannel := z.DequeueChannelFromPath(tailPath)
	if nextSourceChannel == 0 {
		return core.NewPacket(cross(cur), 0, 0, nil, 0, 0), errForwardMissingNextSource
	}
	if packet.DestinationChannelId != core.ChannelId(prevDestChannel) {
		return core.NewPacket(cross(cur), 0, 0, nil, 0, 0), errForwardPrevDestMismatch
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
			return core.NewPacket(cross(cur), 0, 0, nil, 0, 0), err
		}

		nextInstruction = z.Instruction{
			Version: z.INSTR_VERSION_0,
			Opcode:  z.OP_FORWARD,
			Operand: forwardBytes,
		}
	}

	intermediate, err := z.UpdateChannelPath(path, prevDestChannel)
	if err != nil {
		return core.NewPacket(cross(cur), 0, 0, nil, 0, 0), err
	}
	nextPath, err := z.UpdateChannelPath(intermediate, nextSourceChannel)
	if err != nil {
		return core.NewPacket(cross(cur), 0, 0, nil, 0, 0), err
	}

	childBytes, err := z.EncodeZkgmPacket(z.ZkgmPacket{
		Salt:        z.DeriveForwardSalt(parentSalt),
		Path:        nextPath,
		Instruction: nextInstruction,
	})
	if err != nil {
		return core.NewPacket(cross(cur), 0, 0, nil, 0, 0), err
	}

	sourceChannelId := core.ChannelId(nextSourceChannel)
	sourceChannel := core.GetChannel(sourceChannelId)
	return core.NewPacket(cross(cur), sourceChannelId, sourceChannel.CounterpartyChannelId, childBytes, 0, core.Timestamp(forward.TimeoutTimestamp)), nil
}

func (v *ZkgmV1) handleForwardChild(cur realm, packet core.Packet, zp z.ZkgmPacket, ack []byte) bool {
	parent, ok := consumeForwardChild(cur, packet, zp.Salt)
	if !ok {
		return false
	}

	zkgm.WriteForwardAck(cross(cur), parent.ParentPacket, ack)
	return true
}

func consumeForwardChild(cur realm, packet core.Packet, salt [32]byte) (zkgm.InFlightValue, bool) {
	if !z.IsForwardedPacket(salt) {
		return zkgm.NewInFlightValue(cross(cur), core.NewPacket(cross(cur), 0, 0, nil, 0, 0)), false
	}

	return zkgm.PopInFlightPacket(cross(cur), forwardInFlightKey(cur, packet))
}

func forwardInFlightKey(cur realm, packet core.Packet) zkgm.InFlightKey {
	return zkgm.NewInFlightKey(cross(cur), core.CommitPacket(packet))
}

func isAllowedForwardInstruction(opcode uint8) bool {
	return opcode == z.OP_CALL || opcode == z.OP_TOKEN_ORDER || opcode == z.OP_BATCH
}
