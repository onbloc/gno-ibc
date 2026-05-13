package impl

import (
	"chain"
	"errors"

	z "gno.land/p/gnoswap/ibc/zkgm"
	u256 "gno.land/p/gnoswap/uint256"
	"gno.land/p/nt/ufmt/v0"
	core "gno.land/r/core/ibc/v1/core"
)

func (v *ZkgmV1) dispatchVerify(channelId core.ChannelId, sender string, sent chain.Coins, path *u256.Uint, salt [32]byte, instr z.Instruction) error {
	switch instr.Opcode {
	case z.OP_TOKEN_ORDER:
		order, err := decodeOrderInstruction(instr)
		if err != nil {
			return err
		}
		return v.verifyTokenOrderV2(channelId, sender, sent, path, order)
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
		return v.verifyBatch(channelId, sender, sent, path, salt, batch)
	case z.OP_FORWARD:
		forward, err := decodeForwardInstruction(instr)
		if err != nil {
			return err
		}
		return v.verifyForward(channelId, sender, sent, path, salt, forward)
	default:
		return errors.New("zkgm/v1: unsupported opcode")
	}
}

func (v *ZkgmV1) dispatchExecute(packet core.Packet, relayer address, relayerMsg []byte, path *u256.Uint, salt [32]byte, instr z.Instruction, intent bool) (result core.RecvPacketResult, err error) {
	defer func() {
		if r := recover(); r != nil {
			result = failureResult(universalErrorAck())
			err = nil
		}
	}()

	switch instr.Opcode {
	case z.OP_TOKEN_ORDER:
		order, err := decodeOrderInstruction(instr)
		if err != nil {
			return core.RecvPacketResult{}, err
		}
		return v.executeTokenOrderV2(packet, relayer, path, order)
	case z.OP_CALL:
		call, err := decodeCallInstruction(instr)
		if err != nil {
			return core.RecvPacketResult{}, err
		}
		return v.executeCall(packet, relayer, relayerMsg, path, call)
	case z.OP_BATCH:
		batch, err := decodeBatchInstruction(instr)
		if err != nil {
			return core.RecvPacketResult{}, err
		}
		ack, err := v.executeBatch(packet, relayer, relayerMsg, path, salt, batch, intent)
		if err != nil {
			return core.RecvPacketResult{}, err
		}
		return core.RecvPacketResult{Status: core.PacketStatusSuccess, Ack: ack}, nil
	case z.OP_FORWARD:
		forward, err := decodeForwardInstruction(instr)
		if err != nil {
			return core.RecvPacketResult{}, err
		}
		return v.executeForward(packet, path, salt, forward, intent)
	default:
		return core.RecvPacketResult{}, errors.New("zkgm/v1: unsupported opcode")
	}
}

func (v *ZkgmV1) dispatchAck(packet core.Packet, path *u256.Uint, salt [32]byte, instr z.Instruction, ack []byte) error {
	switch instr.Opcode {
	case z.OP_TOKEN_ORDER:
		order, err := decodeOrderInstruction(instr)
		if err != nil {
			return err
		}
		decodedAck, err := z.DecodeAck(ack)
		if err != nil {
			return err
		}
		return v.acknowledgeTokenOrderV2(packet.SourceChannelId, path, order, decodedAck)
	case z.OP_CALL:
		call, err := decodeCallInstruction(instr)
		if err != nil {
			return err
		}
		return v.acknowledgeCall(packet, path, call)
	case z.OP_BATCH:
		batch, err := decodeBatchInstruction(instr)
		if err != nil {
			return err
		}
		outerAck, err := z.DecodeAck(ack)
		if err != nil {
			return err
		}
		return v.acknowledgeBatch(packet, path, salt, batch, outerAck)
	case z.OP_FORWARD:
		forward, err := decodeForwardInstruction(instr)
		if err != nil {
			return err
		}
		outerAck, err := z.DecodeAck(ack)
		if err != nil {
			return err
		}
		return v.acknowledgeForward(packet, path, salt, forward, outerAck)
	default:
		return errors.New("zkgm/v1: unsupported opcode")
	}
}

func (v *ZkgmV1) dispatchTimeout(packet core.Packet, path *u256.Uint, salt [32]byte, instr z.Instruction) error {
	switch instr.Opcode {
	case z.OP_TOKEN_ORDER:
		order, err := decodeOrderInstruction(instr)
		if err != nil {
			return err
		}
		return v.refundV2(packet.SourceChannelId, path, order)
	case z.OP_CALL:
		call, err := decodeCallInstruction(instr)
		if err != nil {
			return err
		}
		return v.timeoutCall(packet, path, call)
	case z.OP_BATCH:
		batch, err := decodeBatchInstruction(instr)
		if err != nil {
			return err
		}
		return v.timeoutBatch(packet, path, salt, batch)
	case z.OP_FORWARD:
		forward, err := decodeForwardInstruction(instr)
		if err != nil {
			return err
		}
		return v.timeoutForward(packet, path, salt, forward)
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

// universalErrorAckBytes is the cached ABI-encoded `z.Ack{Tag:0, InnerAck:"UNIVERSAL_ERROR"}`
// that zkgm-internal recv failures emit. Built once at package init so the per-packet
// `failureResult(universalErrorAck())` paths do not re-encode the same constant payload.
var universalErrorAckBytes = mustEncodeUniversalErrorAck()

func mustEncodeUniversalErrorAck() []byte {
	bz, err := z.EncodeAck(z.Ack{
		Tag:      u256.NewUint(0),
		InnerAck: []byte("UNIVERSAL_ERROR"),
	})
	if err != nil {
		panic(err)
	}
	return bz
}

func failureResult(ack []byte) core.RecvPacketResult {
	return core.RecvPacketResult{Status: core.PacketStatusFailure, Ack: ack}
}

func universalErrorAck() []byte {
	return universalErrorAckBytes
}

// tokenOrderDestinationChannel rejects the zero-channel sentinel so the
// derived destChan is safe to feed into UpdateChannelPath / PopChannelFromPath
// without colliding with the "no channel" slot. Symmetric with the non-v1
// helper at gno.land/r/core/ibc/apps/zkgm/v0/impl/token_order.gno.
func tokenOrderDestinationChannel(channelId core.ChannelId) (uint32, error) {
	raw := uint32(channelId)
	if raw == 0 {
		return 0, errors.New("zkgm/v1: invalid token order destination channel")
	}
	return raw, nil
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
