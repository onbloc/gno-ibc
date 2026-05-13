package impl

import (
	"chain"
	"crypto/keccak256"
	"encoding/hex"
	"errors"
	"strconv"
	"strings"

	"gno.land/p/aib/ibc/types"
	z "gno.land/p/gnoswap/ibc/zkgm"
	u256 "gno.land/p/gnoswap/uint256"
	core "gno.land/r/aib/ibc/core"
	zkgm "gno.land/r/gnoswap/ibc/apps/zkgm"
)

func (v *ZkgmV0) verifyForward(channelID string, sender string, sentCoins chain.Coins, path *u256.Uint, forward z.Forward) error {
	if !isAllowedForwardInstruction(forward.Instruction.Opcode) {
		return errors.New("zkgm/v0: invalid forward instruction")
	}
	// defensive: this should unreachable given the bounds of u256.
	if z.HopCount(forward.Path) > z.MaxHops {
		return errors.New("zkgm/v0: forward hop count exceeded")
	}
	return v.dispatchVerify(channelID, sender, sentCoins, forward.Path, forward.Instruction)
}

func (v *ZkgmV0) executeForward(req zkgm.RecvRequest, path *u256.Uint, parentSalt [32]byte, forward z.Forward, intent bool) (types.RecvPacketResult, error) {
	if !isAllowedForwardInstruction(forward.Instruction.Opcode) {
		return types.RecvPacketResult{}, errors.New("zkgm/v0: invalid forward instruction")
	}
	if intent {
		return types.RecvPacketResult{Status: types.PacketStatus_Success, Acknowledgement: cloneBytes(z.ACK_ERR_ONLY_MAKER)}, nil
	}

	childPayload, childHash, nextSourceChannel, err := buildForwardChild(req, path, parentSalt, forward)
	if err != nil {
		return types.RecvPacketResult{}, err
	}

	core.SendPacket(cross, types.MsgSendPacket{
		SourceClient:     channelToClient(nextSourceChannel),
		TimeoutTimestamp: forward.TimeoutTimestamp,
		Payloads:         []types.Payload{childPayload},
	})

	parentPacket := types.NewPacket(req.Sequence, req.SourceClient, req.DestinationClient, 0, req.Payload)
	zkgm.SetInFlightPacket(cross, zkgm.InFlightKey(childHash), parentPacket)

	// TODO: return a deferred/async ack once IBC core exposes
	// WriteAcknowledgement or honors PacketStatus_Async. The current core
	// commits recv acknowledgements immediately, so Forward can only track
	// child packets and report child ack/timeout later through events.
	ack, err := z.EncodeAck(z.Ack{Tag: tagAckSuccess, InnerAck: []byte{}})
	if err != nil {
		return types.RecvPacketResult{}, err
	}
	return types.RecvPacketResult{Status: types.PacketStatus_Success, Acknowledgement: ack}, nil
}

func (v *ZkgmV0) acknowledgeForward(req zkgm.AckRequest, path *u256.Uint, salt [32]byte, forward z.Forward, ack z.Ack) error {
	return v.dispatchAck(req, forward.Path, salt, forward.Instruction, ack.InnerAck)
}

func (v *ZkgmV0) timeoutForward(req zkgm.TimeoutRequest, path *u256.Uint, salt [32]byte, forward z.Forward) error {
	return v.dispatchTimeout(req, forward.Path, salt, forward.Instruction)
}

func buildForwardChild(req zkgm.RecvRequest, path *u256.Uint, parentSalt [32]byte, forward z.Forward) (types.Payload, [32]byte, uint32, error) {
	tailPath, prevDestChannel := z.DequeueChannelFromPath(forward.Path)
	if prevDestChannel == 0 {
		return types.Payload{}, [32]byte{}, 0, errors.New("zkgm/v0: forward missing previous destination channel")
	}
	continuationPath, nextSourceChannel := z.DequeueChannelFromPath(tailPath)
	if nextSourceChannel == 0 {
		return types.Payload{}, [32]byte{}, 0, errors.New("zkgm/v0: forward missing next source channel")
	}
	if req.DestinationClient != channelToClient(prevDestChannel) {
		return types.Payload{}, [32]byte{}, 0, errors.New("zkgm/v0: forward previous-destination mismatch")
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
			return types.Payload{}, [32]byte{}, 0, err
		}
		nextInstruction = z.Instruction{
			Version: z.INSTR_VERSION_0,
			Opcode:  z.OP_FORWARD,
			Operand: forwardBytes,
		}
	}

	intermediate, err := z.UpdateChannelPath(path, prevDestChannel)
	if err != nil {
		return types.Payload{}, [32]byte{}, 0, err
	}
	nextPath, err := z.UpdateChannelPath(intermediate, nextSourceChannel)
	if err != nil {
		return types.Payload{}, [32]byte{}, 0, err
	}

	childBytes, err := z.EncodeZkgmPacket(z.ZkgmPacket{
		Salt:        z.DeriveForwardSalt(parentSalt),
		Path:        nextPath,
		Instruction: nextInstruction,
	})
	if err != nil {
		return types.Payload{}, [32]byte{}, 0, err
	}

	return types.Payload{
		SourcePort:      PortID,
		DestinationPort: PortID,
		Version:         z.PROTOCOL_VERSION,
		Encoding:        packetEncoding,
		Value:           childBytes,
	}, keccak256.Sum256(childBytes), nextSourceChannel, nil
}

// consumeForwardChild looks up and clears the parent packet that was tracked
// when this forward child was sent. Returns ok=false if the salt isn't
// forward-tinted or no in-flight entry exists.
func consumeForwardChild(payload types.Payload, salt [32]byte) (types.Packet, bool) {
	if !z.IsForwardedPacket(salt) {
		return types.Packet{}, false
	}
	packetHash := keccak256.Sum256(payload.Value)
	return zkgm.PopInFlightPacket(cross, zkgm.InFlightKey(packetHash))
}

func handleForwardChildAck(req zkgm.AckRequest, packet z.ZkgmPacket) bool {
	parent, ok := consumeForwardChild(req.Payload, packet.Salt)
	if !ok {
		return false
	}
	// TODO: write req.Acknowledgement as the parent packet ack after IBC core
	// supports post-recv acknowledgement writes. Until then, emit an event only
	// because the parent success ack has already been committed.
	chain.Emit(z.EventTypeForwardChildAck,
		z.AttributeKeyParentSequence, strconv.FormatUint(parent.Sequence, 10),
		z.AttributeKeyChildSequence, strconv.FormatUint(req.Sequence, 10),
		z.AttributeKeyParentClient, parent.SourceClient,
		z.AttributeKeyChildClient, req.SourceClient,
		z.AttributeKeyAckHex, hex.EncodeToString(req.Acknowledgement),
	)
	return true
}

func handleForwardChildTimeout(req zkgm.TimeoutRequest, packet z.ZkgmPacket) bool {
	parent, ok := consumeForwardChild(req.Payload, packet.Salt)
	if !ok {
		return false
	}
	// TODO: propagate child timeout to the parent packet after IBC core supports
	// deferred ack/timeout handling. Until then, only record the observation
	// because the parent ack cannot be changed.
	chain.Emit(z.EventTypeForwardChildTimeout,
		z.AttributeKeyParentSequence, strconv.FormatUint(parent.Sequence, 10),
		z.AttributeKeyChildSequence, strconv.FormatUint(req.Sequence, 10),
		z.AttributeKeyParentClient, parent.SourceClient,
		z.AttributeKeyChildClient, req.SourceClient,
	)
	return true
}

func isAllowedForwardInstruction(opcode uint8) bool {
	return opcode == z.OP_CALL || opcode == z.OP_TOKEN_ORDER || opcode == z.OP_BATCH
}

func channelToClient(numericID uint32) string {
	// TODO: replace this convention with a channel registry populated during
	// channel setup. Forward paths encode numeric channel IDs, while the current
	// Gno IBC fork addresses clients as strings such as "client-1".
	return "client-" + strconv.FormatUint(uint64(numericID), 10)
}

func clientToChannel(clientID string) (uint32, bool) {
	// TODO: replace with the same registry as channelToClient. This parser only
	// supports the temporary "client-<id>" test/e2e convention.
	if !strings.HasPrefix(clientID, "client-") {
		return 0, false
	}
	n, err := strconv.ParseUint(clientID[len("client-"):], 10, 32)
	if err != nil {
		return 0, false
	}
	return uint32(n), true
}

func decodeForwardInstruction(instr z.Instruction) (z.Forward, error) {
	if instr.Version != z.INSTR_VERSION_0 {
		return z.Forward{}, errors.New("zkgm/v0: unsupported forward version")
	}
	return z.DecodeForward(instr.Operand)
}
