package impl

import (
	"errors"

	z "gno.land/p/onbloc/unionibc/zkgm"
	u256 "gno.land/p/gnoswap/uint256"
	core "gno.land/r/onbloc/unionibc/v1/core"
	zkgm "gno.land/r/onbloc/unionibc/v1/apps/zkgm"
)

var (
	errEurekaUnsupported = errors.New("zkgm/v1: eureka mode not supported")
	errInvalidCallSender = errors.New("zkgm/v1: invalid call sender")
)

func (v *ZkgmV1) verifyCall(cur realm, sender string, call z.Call) error {
	if call.Eureka {
		return errEurekaUnsupported
	}
	if string(call.Sender) != sender {
		return errInvalidCallSender
	}
	return nil
}

func (v *ZkgmV1) executeCall(cur realm, packet core.Packet, relayer address, relayerMsg []byte, path *u256.Uint, call z.Call, intent bool) (core.RecvPacketResult, error) {
	// TODO: when eureka is supported, fail it closed on intent (return
	// ACK_ERR_ONLY_MAKER) like every other opcode instead of a failure ack.
	if call.Eureka {
		return callErrAck(cur, errEurekaUnsupported), nil
	}
	if intent {
		// Calls do not settle on the proofless market-maker fast path.
		return core.NewRecvPacketResult(cross(cur), core.PacketStatusSuccess, cloneBytes(z.ACK_ERR_ONLY_MAKER)), nil
	}

	sender := cloneBytes(call.Sender)
	calldata := cloneBytes(call.ContractCalldata)
	receiverPath := string(call.ContractAddress)
	receiver := zkgm.GetReceiver(receiverPath)
	if receiver == nil {
		return callErrAck(cur, errors.New("zkgm/v1: receiver not registered: "+receiverPath)), nil
	}

	relayerStr := string(relayer)
	env := z.CallEnv{
		Caller:             relayerStr,
		ProxyAccount:       PredictCallProxyAccount(path, packet.DestinationChannelId, sender),
		Path:               path,
		SourceChannel:      packet.SourceChannelId.String(),
		DestinationChannel: packet.DestinationChannelId.String(),
		Sender:             sender,
		Calldata:           calldata,
		Relayer:            []byte(relayerStr),
		RelayerMsg:         cloneBytes(relayerMsg),
	}

	err, panicked := safeCallOnZkgm(cur, receiver, env)
	if panicked {
		return core.NewRecvPacketResult(cross(cur), core.PacketStatusSuccess, cloneBytes(z.ACK_ERR_ONLY_MAKER)), nil
	}
	if err != nil {
		return callErrAck(cur, err), nil
	}

	ack, err := z.EncodeAck(z.Ack{Tag: tagAckSuccess(), InnerAck: []byte{}})
	if err != nil {
		return core.NewRecvPacketResult(cross(cur), core.PacketStatusUnknown, nil), err
	}
	return core.NewRecvPacketResult(cross(cur), core.PacketStatusSuccess, ack), nil
}

func (v *ZkgmV1) acknowledgeCall(cur realm, packet core.Packet, path *u256.Uint, call z.Call) error {
	if call.Eureka {
		return errEurekaUnsupported
	}
	return nil
}

func (v *ZkgmV1) timeoutCall(cur realm, packet core.Packet, path *u256.Uint, call z.Call) error {
	if call.Eureka {
		return errEurekaUnsupported
	}
	return nil
}

// safeCallOnZkgm runs the receiver and reports a failure as panicked=true.
// revive is preferred since it also catches cross-realm aborts. The recover
// fallback, used only when revive is unsupported, catches ordinary panics.
func safeCallOnZkgm(cur realm, receiver z.Zkgmable, env z.CallEnv) (err error, panicked bool) {
	if canRevive() {
		p := revive(func() {
			err = receiver.OnZkgm(cross(cur), env)
		})
		return err, p != nil
	}

	defer func() {
		if recover() != nil {
			err = nil
			panicked = true
		}
	}()
	err = receiver.OnZkgm(cross(cur), env)
	return err, false
}

// canRevive reports whether revive works in the current runtime. revive panics
// rather than returning when the interpreter lacks support for it.
func canRevive() (ok bool) {
	ok = true
	defer func() {
		if recover() != nil {
			ok = false
		}
	}()
	revive(func() {})
	return ok
}

func callErrAck(cur realm, err error) core.RecvPacketResult {
	ack, encErr := z.EncodeAck(z.Ack{Tag: tagAckFailure(), InnerAck: []byte(err.Error())})
	if encErr != nil {
		// EncodeAck on a 2-field schema is essentially infallible. A failure
		// would emit a non-Tag-prefixed ack the counterparty can't decode.
		panic(encErr)
	}
	return failureResult(cur, ack)
}

// cloneBytes copies slices before storing or passing them to code that may
// persist or mutate them across realm boundaries.
func cloneBytes(in []byte) []byte {
	out := make([]byte, len(in))
	copy(out, in)
	return out
}
