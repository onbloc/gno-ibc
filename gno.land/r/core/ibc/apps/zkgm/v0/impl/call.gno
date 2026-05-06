package impl

import (
	"crypto/keccak256"
	"encoding/hex"
	"errors"

	"gno.land/p/aib/ibc/types"
	z "gno.land/p/gnoswap/ibc/zkgm"
	u256 "gno.land/p/gnoswap/uint256"
	core "gno.land/r/aib/ibc/core"
	zkgm "gno.land/r/gnoswap/ibc/apps/zkgm"
)

var errEurekaUnsupported = errors.New("zkgm/v0: eureka mode not supported")

func (v *ZkgmV0) sendCall(req zkgm.SendRequest) (zkgm.SendResult, error) {
	if req.Instruction.Version != z.INSTR_VERSION_0 {
		return zkgm.SendResult{}, errors.New("zkgm/v0: unsupported call version")
	}

	call, err := z.DecodeCall(req.Instruction.Operand)
	if err != nil {
		return zkgm.SendResult{}, err
	}
	if err := v.verifyCall(req.Sender, call); err != nil {
		return zkgm.SendResult{}, err
	}

	return v.sendPacket(req)
}

func (v *ZkgmV0) verifyCall(sender string, call z.Call) error {
	if call.Eureka {
		return errEurekaUnsupported
	}
	if string(call.Sender) != sender {
		return errors.New("zkgm/v0: invalid call sender")
	}
	return nil
}

func (v *ZkgmV0) executeCall(req zkgm.RecvRequest, path *u256.Uint, call z.Call) (types.RecvPacketResult, error) {
	if call.Eureka {
		return callErrAck(errEurekaUnsupported), nil
	}

	receiverPath := string(call.ContractAddress)
	receiver := zkgm.GetReceiver(receiverPath)
	if receiver == nil {
		return callErrAck(errors.New("zkgm/v0: receiver not registered: " + receiverPath)), nil
	}

	env := z.CallEnv{
		Caller:             PredictCallProxyAccount(path, req.DestinationClient, call.Sender),
		Path:               path,
		SourceChannel:      req.SourceClient,
		DestinationChannel: req.DestinationClient,
		Sender:             call.Sender,
		Calldata:           call.ContractCalldata,
	}

	err, panicked := safeCallOnZkgm(receiver, env)
	if panicked {
		return types.RecvPacketResult{Status: types.PacketStatus_Success, Acknowledgement: cloneBytes(z.ACK_ERR_ONLY_MAKER)}, nil
	}
	if err != nil {
		return callErrAck(err), nil
	}

	ack, err := z.EncodeAck(z.Ack{Tag: u256.NewUint(1), InnerAck: []byte{}})
	if err != nil {
		return types.RecvPacketResult{}, err
	}

	return types.RecvPacketResult{Status: types.PacketStatus_Success, Acknowledgement: ack}, nil
}

func (v *ZkgmV0) acknowledgeCall(req zkgm.AckRequest, path *u256.Uint, call z.Call) error {
	if call.Eureka {
		return errEurekaUnsupported
	}
	return nil
}

func (v *ZkgmV0) timeoutCall(req zkgm.TimeoutRequest, path *u256.Uint, call z.Call) error {
	if call.Eureka {
		return errEurekaUnsupported
	}
	return nil
}

func safeCallOnZkgm(receiver z.Zkgmable, env z.CallEnv) (err error, panicked bool) {
	p := revive(func() {
		err = receiver.OnZkgm(cross, env)
	})
	return err, p != nil
}

func callErrAck(err error) types.RecvPacketResult {
	ack, encErr := z.EncodeAck(z.Ack{Tag: u256.NewUint(0), InnerAck: []byte(err.Error())})
	if encErr != nil {
		ack = []byte(err.Error())
	}
	return types.RecvPacketResult{Status: types.PacketStatus_Failure, Acknowledgement: ack}
}

func decodeCall(packet z.ZkgmPacket) (z.Call, error) {
	if packet.Instruction.Version != z.INSTR_VERSION_0 {
		return z.Call{}, errors.New("zkgm/v0: unsupported call version")
	}
	return z.DecodeCall(packet.Instruction.Operand)
}

// cloneBytes copies cross-realm package vars (e.g. ACK_ERR_ONLY_MAKER)
// before returning them, since Gno marks such slices readonly and any later
// []byte -> string conversion (e.g. bytes.Equal) panics.
func cloneBytes(in []byte) []byte {
	out := make([]byte, len(in))
	copy(out, in)
	return out
}

// sendPacket encodes req.Instruction into a ZkgmPacket, calls core.SendPacket
// with the standard ZKGM payload envelope, and records the in-flight packet.
// Used by every send-side opcode handler.
func (v *ZkgmV0) sendPacket(req zkgm.SendRequest) (zkgm.SendResult, error) {
	packet := z.ZkgmPacket{
		Salt:        req.Salt,
		Path:        u256.Zero(),
		Instruction: req.Instruction,
	}

	packetBytes, err := z.EncodeZkgmPacket(packet)
	if err != nil {
		return zkgm.SendResult{}, err
	}

	payload := types.Payload{
		SourcePort:      PortID,
		DestinationPort: PortID,
		Version:         z.PROTOCOL_VERSION,
		Encoding:        packetEncoding,
		Value:           packetBytes,
	}

	sequence := core.SendPacket(cross, types.MsgSendPacket{
		SourceClient:     req.ChannelID,
		TimeoutTimestamp: req.TimeoutTimestamp,
		Payloads:         []types.Payload{payload},
	})

	packetHash := keccak256.Sum256(packetBytes)
	zkgm.SetInFlightPacket(cross, hex.EncodeToString(packetHash[:]), types.NewPacket(sequence, req.ChannelID, "", req.TimeoutTimestamp, payload))
	return zkgm.SendResult{PacketSequence: sequence, PacketHash: packetHash}, nil
}
