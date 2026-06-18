package impl

import (
	"bytes"
	"errors"

	types "gno.land/p/onbloc/ibc/union/types"

	u256 "gno.land/p/gnoswap/uint256"
	"gno.land/p/nt/ufmt/v0"
	z "gno.land/p/onbloc/ibc/union/zkgm"
	core "gno.land/r/onbloc/ibc/union/core"
)

// dispatchVerify routes an instruction to its opcode-specific verifier (the send-side validation entry point).
// reference: https://github.com/unionlabs/union/blob/d91c5e94354e15801bd5f82dc658eae3b79f2dad/cosmwasm/app/ucs03-zkgm/src/contract.rs#L2742-L2796
func (v *ucs03ZkgmV1) dispatchVerify(_ int, rlm realm, channelId types.ChannelId, sender string, funds *funds, path *u256.Uint, instr z.Instruction) error {
	switch instr.Opcode {
	case z.OP_TOKEN_ORDER:
		order, err := decodeOrderInstruction(instr)
		if err != nil {
			return err
		}

		return v.verifyTokenOrderV2(0, rlm, channelId, sender, funds, path, order)
	case z.OP_CALL:
		call, err := decodeCallInstruction(instr)
		if err != nil {
			return err
		}

		return v.verifyCall(0, rlm, sender, call)
	case z.OP_BATCH:
		batch, err := decodeBatchInstruction(instr)
		if err != nil {
			return err
		}

		return v.verifyBatch(0, rlm, channelId, sender, funds, path, batch)
	case z.OP_FORWARD:
		forward, err := decodeForwardInstruction(instr)
		if err != nil {
			return err
		}

		return v.verifyForward(0, rlm, channelId, sender, funds, path, forward)
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

// dispatchExecute routes a received instruction to its opcode handler, turning non-fatal errors into a failure ack.
func (v *ucs03ZkgmV1) dispatchExecute(_ int, rlm realm, packet types.Packet, relayer address, relayerMsg []byte, path *u256.Uint, salt [32]byte, instr z.Instruction, intent bool) (result types.RecvPacketResult, err error) {
	defer func() {
		if r := recover(); r != nil {
			if _, ok := r.(execFatal); ok {
				panic(r)
			}

			result = failureResult(universalErrorAck())
			err = nil
		}
	}()

	switch instr.Opcode {
	case z.OP_TOKEN_ORDER:
		order, err := decodeOrderInstruction(instr)
		if err != nil {
			return core.NewRecvPacketResult(types.PacketStatusUnknown, nil), err
		}

		return v.executeTokenOrderV2(0, rlm, packet, relayer, relayerMsg, path, order, intent)
	case z.OP_CALL:
		call, err := decodeCallInstruction(instr)
		if err != nil {
			return core.NewRecvPacketResult(types.PacketStatusUnknown, nil), err
		}

		return v.executeCall(0, rlm, packet, relayer, relayerMsg, path, call, intent)
	case z.OP_BATCH:
		batch, err := decodeBatchInstruction(instr)
		if err != nil {
			return core.NewRecvPacketResult(types.PacketStatusUnknown, nil), err
		}

		ack, err := v.executeBatch(0, rlm, packet, relayer, relayerMsg, path, salt, batch, intent)
		if err != nil {
			return core.NewRecvPacketResult(types.PacketStatusUnknown, nil), err
		}

		return core.NewRecvPacketResult(types.PacketStatusSuccess, ack), nil
	case z.OP_FORWARD:
		forward, err := decodeForwardInstruction(instr)
		if err != nil {
			return core.NewRecvPacketResult(types.PacketStatusUnknown, nil), err
		}

		return v.executeForward(0, rlm, packet, path, salt, forward, intent)
	default:
		return core.NewRecvPacketResult(types.PacketStatusUnknown, nil), errors.New("zkgm/v1: unsupported opcode")
	}
}

// dispatchAck routes an acknowledgement to its opcode handler.
func (v *ucs03ZkgmV1) dispatchAck(_ int, rlm realm, packet types.Packet, path *u256.Uint, salt [32]byte, instr z.Instruction, successful bool, ack []byte) error {
	switch instr.Opcode {
	case z.OP_TOKEN_ORDER:
		order, err := decodeOrderInstruction(instr)
		if err != nil {
			return err
		}

		tag := tagAckFailure()
		if successful {
			tag = tagAckSuccess()
		}
		return v.acknowledgeTokenOrderV2(0, rlm, packet.SourceChannelId, path, order, z.Ack{Tag: tag, InnerAck: ack})
	case z.OP_CALL:
		call, err := decodeCallInstruction(instr)
		if err != nil {
			return err
		}

		return v.acknowledgeCall(0, rlm, packet, path, call)
	case z.OP_BATCH:
		batch, err := decodeBatchInstruction(instr)
		if err != nil {
			return err
		}

		return v.acknowledgeBatch(0, rlm, packet, path, salt, batch, successful, ack)
	case z.OP_FORWARD:
		forward, err := decodeForwardInstruction(instr)
		if err != nil {
			return err
		}

		tag := tagAckFailure()
		if successful {
			tag = tagAckSuccess()
		}
		return v.acknowledgeForward(0, rlm, packet, path, salt, forward, z.Ack{Tag: tag, InnerAck: ack})
	default:
		return errors.New("zkgm/v1: unsupported opcode")
	}
}

// dispatchTimeout routes a timeout to its opcode handler.
func (v *ucs03ZkgmV1) dispatchTimeout(_ int, rlm realm, packet types.Packet, path *u256.Uint, salt [32]byte, instr z.Instruction) error {
	switch instr.Opcode {
	case z.OP_TOKEN_ORDER:
		order, err := decodeOrderInstruction(instr)
		if err != nil {
			return err
		}

		return v.refundV2(0, rlm, packet.SourceChannelId, path, order)
	case z.OP_CALL:
		call, err := decodeCallInstruction(instr)
		if err != nil {
			return err
		}

		return v.timeoutCall(0, rlm, packet, path, call)
	case z.OP_BATCH:
		batch, err := decodeBatchInstruction(instr)
		if err != nil {
			return err
		}

		return v.timeoutBatch(0, rlm, packet, path, salt, batch)
	case z.OP_FORWARD:
		forward, err := decodeForwardInstruction(instr)
		if err != nil {
			return err
		}

		return v.timeoutForward(0, rlm, packet, path, salt, forward)
	default:
		return errors.New("zkgm/v1: unsupported opcode")
	}
}

// decodeOrderInstruction decodes a v2 token order, rejecting unsupported instruction versions.
func decodeOrderInstruction(instr z.Instruction) (z.TokenOrderV2, error) {
	if instr.Version != z.INSTR_VERSION_2 {
		return z.TokenOrderV2{}, errors.New("zkgm/v1: unsupported token order version")
	}

	return z.DecodeTokenOrderV2(instr.Operand)
}

// decodeCallInstruction decodes a call, rejecting unsupported instruction versions.
func decodeCallInstruction(instr z.Instruction) (z.Call, error) {
	if instr.Version != z.INSTR_VERSION_0 {
		return z.Call{}, errors.New("zkgm/v1: unsupported call version")
	}

	return z.DecodeCall(instr.Operand)
}

// decodeBatchInstruction decodes a batch, rejecting unsupported instruction versions.
func decodeBatchInstruction(instr z.Instruction) (z.Batch, error) {
	if instr.Version != z.INSTR_VERSION_0 {
		return z.Batch{}, errors.New("zkgm/v1: unsupported batch version")
	}

	return z.DecodeBatch(instr.Operand)
}

// decodeForwardInstruction decodes a forward, rejecting unsupported instruction versions.
func decodeForwardInstruction(instr z.Instruction) (z.Forward, error) {
	if instr.Version != z.INSTR_VERSION_0 {
		return z.Forward{}, errors.New("zkgm/v1: unsupported forward version")
	}

	return z.DecodeForward(instr.Operand)
}

// mustEncodeUniversalErrorAck returns the ABI-encoded failure acknowledgement
// `z.Ack{Tag: TAG_ACK_FAILURE, InnerAck: empty}` that zkgm-internal recv failures
// emit. The empty inner ack matches union's `Ack{tag: TAG_ACK_FAILURE, inner_ack:
// Default::default()}`; the encoded Ack itself is non-empty, satisfying core's
// non-empty acknowledgement requirement.
func mustEncodeUniversalErrorAck() []byte {
	bz, err := z.EncodeAck(z.Ack{
		Tag:      u256.NewUint(0),
		InnerAck: []byte{},
	})
	if err != nil {
		panic(err)
	}

	return bz
}

// failureResult wraps an ack as a failed recv result.
func failureResult(ack []byte) types.RecvPacketResult {
	return core.NewRecvPacketResult(types.PacketStatusFailure, ack)
}

// universalErrorAck returns the cached sentinel error acknowledgement.
func universalErrorAck() []byte {
	return mustEncodeUniversalErrorAck()
}

// tokenOrderDestinationChannel rejects the zero-channel sentinel so the
// derived destChan is safe to feed into UpdateChannelPath / PopChannelFromPath
// without colliding with the "no channel" slot. This mirrors the TokenOrder
// path helper's channel-zero rejection.
func tokenOrderDestinationChannel(channelId types.ChannelId) (uint32, error) {
	raw := uint32(channelId)
	if raw == 0 {
		return 0, errors.New("zkgm/v1: invalid token order destination channel")
	}

	return raw, nil
}

// isOnlyMakerAck reports whether ack is the only-maker sentinel.
func isOnlyMakerAck(ack []byte) bool {
	return bytes.Equal(ack, z.ACK_ERR_ONLY_MAKER)
}

// extractPanicMessage renders a recovered panic value as a string.
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
