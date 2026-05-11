package impl

import (
	"chain"
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
)

func (v *ZkgmV1) verifyForward(channelId core.ChannelId, sender string, sent chain.Coins, salt [32]byte, forward z.Forward) error {
	if !isAllowedForwardInstruction(forward.Instruction.Opcode) {
		return errInvalidForwardInstruction
	}
	if z.HopCount(forward.Path) > z.MaxHops {
		return errForwardHopExceeded
	}

	return v.dispatchVerify(channelId, sender, sent, z.DeriveForwardSalt(salt), forward.Instruction)
}

func (v *ZkgmV1) executeForward(packet core.Packet, path *u256.Uint, parentSalt [32]byte, forward z.Forward, intent bool) (core.RecvPacketResult, error) {
	// Recv skips dispatchVerify (see impl.gno Recv flow), so this opcode check
	// is the only line of defense on receive — do not strip as redundant with
	// verifyForward.
	if !isAllowedForwardInstruction(forward.Instruction.Opcode) {
		return core.RecvPacketResult{}, errInvalidForwardInstruction
	}
	if intent {
		return core.NewRecvPacketResult(cross, core.PacketStatusSuccess, cloneBytes(z.ACK_ERR_ONLY_MAKER)), nil
	}

	msg, err := buildForwardChild(packet, path, parentSalt, forward)
	if err != nil {
		return core.RecvPacketResult{}, err
	}

	childPacket := core.PacketSend(cross, msg)
	zkgm.SetInFlightPacket(cross, forwardInFlightKey(childPacket), zkgm.InFlightValue{
		ParentSourceChannelId:      packet.SourceChannelId,
		ParentDestinationChannelId: packet.DestinationChannelId,
		ParentSequence:             packet.Sequence,
	})

	return core.NewRecvPacketResult(cross, core.PacketStatusAsync, nil), nil
}

func (v *ZkgmV1) acknowledgeForward(packet core.Packet, path *u256.Uint, salt [32]byte, forward z.Forward, ack z.Ack) error {
	return v.dispatchAck(packet, path, salt, forward.Instruction, core.NewBytes(cross, ack.InnerAck))
}

func (v *ZkgmV1) timeoutForward(packet core.Packet, path *u256.Uint, salt [32]byte, forward z.Forward) error {
	return v.dispatchTimeout(packet, path, salt, forward.Instruction)
}

func buildForwardChild(packet core.Packet, path *u256.Uint, parentSalt [32]byte, forward z.Forward) (core.MsgPacketSend, error) {
	tailPath, prevDestChannel := z.DequeueChannelFromPath(forward.Path)
	if prevDestChannel == 0 {
		return core.MsgPacketSend{}, errForwardMissingPrevDest
	}

	continuationPath, nextSourceChannel := z.DequeueChannelFromPath(tailPath)
	if nextSourceChannel == 0 {
		return core.MsgPacketSend{}, errForwardMissingNextSource
	}
	if packet.DestinationChannelId != core.ChannelId(prevDestChannel) {
		return core.MsgPacketSend{}, errForwardPrevDestMismatch
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
			return core.MsgPacketSend{}, err
		}

		nextInstruction = z.Instruction{
			Version: z.INSTR_VERSION_0,
			Opcode:  z.OP_FORWARD,
			Operand: forwardBytes,
		}
	}

	intermediate, err := z.UpdateChannelPath(path, prevDestChannel)
	if err != nil {
		return core.MsgPacketSend{}, err
	}
	nextPath, err := z.UpdateChannelPath(intermediate, nextSourceChannel)
	if err != nil {
		return core.MsgPacketSend{}, err
	}

	childBytes, err := z.EncodeZkgmPacket(z.ZkgmPacket{
		Salt:        z.DeriveForwardSalt(parentSalt),
		Path:        nextPath,
		Instruction: nextInstruction,
	})
	if err != nil {
		return core.MsgPacketSend{}, err
	}

	return core.MsgPacketSend{
		SourceChannelId:  core.ChannelId(nextSourceChannel),
		TimeoutTimestamp: core.Timestamp(forward.TimeoutTimestamp),
		Data:             core.NewBytes(cross, childBytes),
	}, nil
}

func (v *ZkgmV1) handleForwardChild(packet core.Packet, zp z.ZkgmPacket, ack core.Bytes) bool {
	parent, ok := consumeForwardChild(packet, zp.Salt)
	if !ok {
		return false
	}

	zkgm.WriteForwardAck(cross, parent.ParentDestinationChannelId, parent.ParentSequence, ack)
	return true
}

func consumeForwardChild(packet core.Packet, salt [32]byte) (zkgm.InFlightValue, bool) {
	if !z.IsForwardedPacket(salt) {
		return zkgm.InFlightValue{}, false
	}

	return zkgm.PopInFlightPacket(cross, forwardInFlightKey(packet))
}

func forwardInFlightKey(packet core.Packet) zkgm.InFlightKey {
	return zkgm.InFlightKey{
		SourceChannelId:      packet.SourceChannelId,
		DestinationChannelId: packet.DestinationChannelId,
		Sequence:             packet.Sequence,
	}
}

func isAllowedForwardInstruction(opcode uint8) bool {
	return opcode == z.OP_CALL || opcode == z.OP_TOKEN_ORDER || opcode == z.OP_BATCH
}
