package impl

import (
	"errors"

	z "gno.land/p/gnoswap/ibc/zkgm"
	u256 "gno.land/p/gnoswap/uint256"
	core "gno.land/r/core/ibc/v1/core"
	zkgm "gno.land/r/gnoswap/ibc/v1/apps/zkgm"
)

var (
	errEurekaUnsupported = errors.New("zkgm/v1: eureka mode not supported")
	errInvalidCallSender = errors.New("zkgm/v1: invalid call sender")
)

func (v *ZkgmV1) verifyCall(sender string, call z.Call) error {
	if call.Eureka {
		return errEurekaUnsupported
	}
	if string(call.Sender) != sender {
		return errInvalidCallSender
	}
	return nil
}

func (v *ZkgmV1) executeCall(packet core.Packet, relayer address, relayerMsg core.Bytes, path *u256.Uint, call z.Call) (core.RecvPacketResult, error) {
	if call.Eureka {
		return callErrAck(errEurekaUnsupported), nil
	}

	receiverPath := string(call.ContractAddress)
	receiver := zkgm.GetReceiver(receiverPath)
	if receiver == nil {
		return callErrAck(errors.New("zkgm/v1: receiver not registered: " + receiverPath)), nil
	}

	relayerStr := string(relayer)
	env := z.CallEnv{
		Caller:             relayerStr,
		ProxyAccount:       PredictCallProxyAccount(path, packet.DestinationChannelId, call.Sender),
		Path:               path,
		SourceChannel:      packet.SourceChannelId.String(),
		DestinationChannel: packet.DestinationChannelId.String(),
		Sender:             call.Sender,
		Calldata:           call.ContractCalldata,
		Relayer:            []byte(relayerStr),
		RelayerMsg:         []byte(relayerMsg),
	}

	err, panicked := safeCallOnZkgm(receiver, env)
	if panicked {
		return core.NewRecvPacketResult(cross, core.PacketStatusSuccess, cloneBytes(z.ACK_ERR_ONLY_MAKER)), nil
	}
	if err != nil {
		return callErrAck(err), nil
	}

	ack, err := z.EncodeAck(z.Ack{Tag: tagAckSuccess, InnerAck: []byte{}})
	if err != nil {
		return core.RecvPacketResult{}, err
	}
	return core.NewRecvPacketResult(cross, core.PacketStatusSuccess, ack), nil
}

func (v *ZkgmV1) acknowledgeCall(packet core.Packet, path *u256.Uint, call z.Call) error {
	if call.Eureka {
		return errEurekaUnsupported
	}
	return nil
}

func (v *ZkgmV1) timeoutCall(packet core.Packet, path *u256.Uint, call z.Call) error {
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

func callErrAck(err error) core.RecvPacketResult {
	ack, encErr := z.EncodeAck(z.Ack{Tag: tagAckFailure, InnerAck: []byte(err.Error())})
	if encErr != nil {
		// EncodeAck on a 2-field schema is essentially infallible; a failure
		// would emit a non-Tag-prefixed ack the counterparty can't decode.
		panic(encErr)
	}
	return failureResult(ack)
}

// cloneBytes copies cross-realm package vars (e.g. ACK_ERR_ONLY_MAKER)
// before returning them, since Gno marks such slices readonly and any later
// []byte -> string conversion (e.g. bytes.Equal) panics.
func cloneBytes(in []byte) []byte {
	out := make([]byte, len(in))
	copy(out, in)
	return out
}
