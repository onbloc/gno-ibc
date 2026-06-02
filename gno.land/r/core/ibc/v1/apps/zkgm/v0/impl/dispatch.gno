package impl

import (
	"bytes"
	"errors"

	z "gno.land/p/gnoswap/ibc/zkgm"
	u256 "gno.land/p/gnoswap/uint256"
	"gno.land/p/nt/ufmt/v0"
	core "gno.land/r/core/ibc/v1/core"
)

func (v *ZkgmV1) dispatchVerify(cur realm, channelId core.ChannelId, sender string, budget *sentCoinBudget, path *u256.Uint, salt [32]byte, instr z.Instruction) error {
	switch instr.Opcode {
	case z.OP_TOKEN_ORDER:
		order, err := decodeOrderInstruction(instr)
		if err != nil {
			return err
		}
		return v.verifyTokenOrderV2(cur, channelId, sender, budget, path, order)
	case z.OP_CALL:
		call, err := decodeCallInstruction(instr)
		if err != nil {
			return err
		}
		return v.verifyCall(cur, sender, call)
	case z.OP_BATCH:
		batch, err := decodeBatchInstruction(instr)
		if err != nil {
			return err
		}
		return v.verifyBatch(cur, channelId, sender, budget, path, salt, batch)
	case z.OP_FORWARD:
		forward, err := decodeForwardInstruction(instr)
		if err != nil {
			return err
		}
		return v.verifyForward(cur, channelId, sender, budget, path, salt, forward)
	default:
		return errors.New("zkgm/v1: unsupported opcode")
	}
}

// execFatal is a sentinel panic value.
//
// Unlike ordinary panics, values of this type are re-panicked by the recover
// handler so the VM can observe the failure after transaction rollback.
type execFatal struct{ msg string }

func (e execFatal) Error() string { return e.msg }

func (v *ZkgmV1) dispatchExecute(cur realm, packet core.Packet, relayer address, relayerMsg []byte, path *u256.Uint, salt [32]byte, instr z.Instruction, intent bool) (result core.RecvPacketResult, err error) {
	defer func() {
		if r := recover(); r != nil {
			if _, ok := r.(execFatal); ok {
				panic(r)
			}
			result = failureResult(cur, universalErrorAck())
			err = nil
		}
	}()

	switch instr.Opcode {
	case z.OP_TOKEN_ORDER:
		order, err := decodeOrderInstruction(instr)
		if err != nil {
			return core.NewRecvPacketResult(cross(cur), core.PacketStatusUnknown, nil), err
		}
		return v.executeTokenOrderV2(cur, packet, relayer, path, order, intent)
	case z.OP_CALL:
		call, err := decodeCallInstruction(instr)
		if err != nil {
			return core.NewRecvPacketResult(cross(cur), core.PacketStatusUnknown, nil), err
		}
		return v.executeCall(cur, packet, relayer, relayerMsg, path, call)
	case z.OP_BATCH:
		batch, err := decodeBatchInstruction(instr)
		if err != nil {
			return core.NewRecvPacketResult(cross(cur), core.PacketStatusUnknown, nil), err
		}
		ack, err := v.executeBatch(cur, packet, relayer, relayerMsg, path, salt, batch, intent)
		if err != nil {
			return core.NewRecvPacketResult(cross(cur), core.PacketStatusUnknown, nil), err
		}
		return core.NewRecvPacketResult(cross(cur), core.PacketStatusSuccess, ack), nil
	case z.OP_FORWARD:
		forward, err := decodeForwardInstruction(instr)
		if err != nil {
			return core.NewRecvPacketResult(cross(cur), core.PacketStatusUnknown, nil), err
		}
		return v.executeForward(cur, packet, path, salt, forward, intent)
	default:
		return core.NewRecvPacketResult(cross(cur), core.PacketStatusUnknown, nil), errors.New("zkgm/v1: unsupported opcode")
	}
}

func (v *ZkgmV1) dispatchAck(cur realm, packet core.Packet, path *u256.Uint, salt [32]byte, instr z.Instruction, ack []byte) error {
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
		return v.acknowledgeTokenOrderV2(cur, packet.SourceChannelId, path, order, decodedAck)
	case z.OP_CALL:
		call, err := decodeCallInstruction(instr)
		if err != nil {
			return err
		}
		return v.acknowledgeCall(cur, packet, path, call)
	case z.OP_BATCH:
		batch, err := decodeBatchInstruction(instr)
		if err != nil {
			return err
		}
		outerAck, err := z.DecodeAck(ack)
		if err != nil {
			return err
		}
		return v.acknowledgeBatch(cur, packet, path, salt, batch, outerAck)
	case z.OP_FORWARD:
		forward, err := decodeForwardInstruction(instr)
		if err != nil {
			return err
		}
		outerAck, err := z.DecodeAck(ack)
		if err != nil {
			return err
		}
		return v.acknowledgeForward(cur, packet, path, salt, forward, outerAck)
	default:
		return errors.New("zkgm/v1: unsupported opcode")
	}
}

func (v *ZkgmV1) dispatchTimeout(cur realm, packet core.Packet, path *u256.Uint, salt [32]byte, instr z.Instruction) error {
	switch instr.Opcode {
	case z.OP_TOKEN_ORDER:
		order, err := decodeOrderInstruction(instr)
		if err != nil {
			return err
		}
		return v.refundV2(cur, packet.SourceChannelId, path, order)
	case z.OP_CALL:
		call, err := decodeCallInstruction(instr)
		if err != nil {
			return err
		}
		return v.timeoutCall(cur, packet, path, call)
	case z.OP_BATCH:
		batch, err := decodeBatchInstruction(instr)
		if err != nil {
			return err
		}
		return v.timeoutBatch(cur, packet, path, salt, batch)
	case z.OP_FORWARD:
		forward, err := decodeForwardInstruction(instr)
		if err != nil {
			return err
		}
		return v.timeoutForward(cur, packet, path, salt, forward)
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

func failureResult(cur realm, ack []byte) core.RecvPacketResult {
	return core.NewRecvPacketResult(cross(cur), core.PacketStatusFailure, ack)
}

func universalErrorAck() []byte {
	return universalErrorAckBytes
}

// tokenOrderDestinationChannel rejects the zero-channel sentinel so the
// derived destChan is safe to feed into UpdateChannelPath / PopChannelFromPath
// without colliding with the "no channel" slot. This mirrors the TokenOrder
// path helper's channel-zero rejection.
func tokenOrderDestinationChannel(channelId core.ChannelId) (uint32, error) {
	raw := uint32(channelId)
	if raw == 0 {
		return 0, errors.New("zkgm/v1: invalid token order destination channel")
	}
	return raw, nil
}

func isOnlyMakerAck(ack []byte) bool {
	return bytes.Equal(ack, z.ACK_ERR_ONLY_MAKER)
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
