package impl

import (
	"testing"

	"gno.land/p/aib/ibc/types"
	z "gno.land/p/gnoswap/ibc/zkgm"
	u256 "gno.land/p/gnoswap/uint256"
	"gno.land/p/nt/uassert/v0"
	zkgm "gno.land/r/gnoswap/ibc/apps/zkgm"
	"gno.land/r/gnoswap/ibc/apps/zkgm/testing/mock"
)

const mockReceiverPath = "gno.land/r/gnoswap/ibc/apps/zkgm/testing/mock"

func TestExecuteCallDispatchesOnZkgm(cur realm, t *testing.T) {
	mock.Reset(cross)
	call := z.Call{
		Sender:           []byte("sender"),
		ContractAddress:  []byte(mockReceiverPath),
		ContractCalldata: []byte("calldata"),
	}
	path := u256.NewUint(7)

	res, err := (&ZkgmV0{}).executeCall(zkgm.RecvRequest{
		SourceClient:      "client-a",
		DestinationClient: "client-b",
		Caller:            "relayer-1",
		Relayer:           []byte("relayer-1"),
		RelayerMsg:        []byte("relay-msg"),
	}, path, call)

	uassert.NoError(t, err)
	uassert.True(t, res.Status == types.PacketStatus_Success)
	ack, err := z.DecodeAck(res.Acknowledgement)
	uassert.NoError(t, err)
	uassert.True(t, ack.Tag.Eq(tagAckSuccess))
	uassert.Equal(t, 1, mock.Calls())
	uassert.Equal(t, "client-a", mock.LastSourceChannel(cross))
	uassert.Equal(t, "client-b", mock.LastDestinationChannel(cross))
	uassert.Equal(t, "sender", mock.LastSender(cross))
	uassert.Equal(t, "calldata", mock.LastCalldata(cross))
	uassert.Equal(t, "relayer-1", mock.LastCaller(cross))
	uassert.Equal(t, PredictCallProxyAccount(path, "client-b", []byte("sender")), mock.LastProxyAccount(cross))
	uassert.Equal(t, "relayer-1", mock.LastRelayer(cross))
	uassert.Equal(t, "relay-msg", mock.LastRelayerMsg(cross))
}

func TestExecuteCallReceiverErrorReturnsFailureAck(cur realm, t *testing.T) {
	mock.Reset(cross)
	mock.SetError(cross, "receiver failed")

	res, err := (&ZkgmV0{}).executeCall(zkgm.RecvRequest{
		DestinationClient: "client-b",
	}, u256.Zero(), z.Call{
		Sender:          []byte("sender"),
		ContractAddress: []byte(mockReceiverPath),
	})

	uassert.NoError(t, err)
	uassert.True(t, res.Status == types.PacketStatus_Failure)
	ack, err := z.DecodeAck(res.Acknowledgement)
	uassert.NoError(t, err)
	uassert.True(t, ack.Tag.Eq(tagAckFailure))
	uassert.Equal(t, "receiver failed", string(ack.InnerAck))
}

func TestExecuteCallReceiverPanicReturnsOnlyMakerAck(cur realm, t *testing.T) {
	mock.Reset(cross)
	mock.SetPanic(cross, "boom")

	res, err := (&ZkgmV0{}).executeCall(zkgm.RecvRequest{
		DestinationClient: "client-b",
	}, u256.Zero(), z.Call{
		Sender:          []byte("sender"),
		ContractAddress: []byte(mockReceiverPath),
	})

	uassert.NoError(t, err)
	uassert.True(t, res.Status == types.PacketStatus_Success)
	uassert.True(t, equalBytes(z.ACK_ERR_ONLY_MAKER, res.Acknowledgement))
}

func TestVerifyCallRejectsEurekaAndSenderMismatch(cur realm, t *testing.T) {
	err := (&ZkgmV0{}).verifyCall("sender", z.Call{Sender: []byte("other")})
	uassert.ErrorContains(t, err, "invalid call sender")

	err = (&ZkgmV0{}).verifyCall("sender", z.Call{Sender: []byte("sender"), Eureka: true})
	uassert.ErrorContains(t, err, "eureka mode not supported")
}

func TestAcknowledgeCallNoopForStandardMode(t *testing.T) {
	err := (&ZkgmV0{}).acknowledgeCall(zkgm.AckRequest{SourceClient: "client-a"}, u256.NewUint(1), z.Call{
		Sender: []byte("sender"),
	})

	uassert.NoError(t, err)
}

func TestTimeoutCallNoopForStandardMode(t *testing.T) {
	err := (&ZkgmV0{}).timeoutCall(zkgm.TimeoutRequest{SourceClient: "client-a"}, u256.NewUint(1), z.Call{
		Sender: []byte("sender"),
	})

	uassert.NoError(t, err)
}

func TestRecvDispatchesCallOpcode(cur realm, t *testing.T) {
	mock.Reset(cross)
	call := z.Call{
		Sender:           []byte("sender"),
		ContractAddress:  []byte(mockReceiverPath),
		ContractCalldata: []byte("dispatch"),
	}
	payload := mustCallPayload(call)

	res, err := (&ZkgmV0{}).Recv(zkgm.RecvRequest{
		SourceClient:      "client-a",
		DestinationClient: "client-b",
		Payload:           payload,
		Caller:            "relayer-2",
		Relayer:           []byte("relayer-2"),
	})

	uassert.NoError(t, err)
	uassert.True(t, res.Status == types.PacketStatus_Success)
	uassert.Equal(t, 1, mock.Calls())
	uassert.Equal(t, "dispatch", mock.LastCalldata(cross))
	uassert.Equal(t, "relayer-2", mock.LastCaller(cross))
}

func TestRecvDispatchesCallFailureStatus(cur realm, t *testing.T) {
	mock.Reset(cross)
	mock.SetError(cross, "receiver failed")
	payload := mustCallPayload(z.Call{
		Sender:          []byte("sender"),
		ContractAddress: []byte(mockReceiverPath),
	})

	res, err := (&ZkgmV0{}).Recv(zkgm.RecvRequest{
		SourceClient:      "client-a",
		DestinationClient: "client-b",
		Payload:           payload,
		Caller:            "relayer",
	})

	uassert.NoError(t, err)
	uassert.True(t, res.Status == types.PacketStatus_Failure)
	ack, err := z.DecodeAck(res.Acknowledgement)
	uassert.NoError(t, err)
	uassert.True(t, ack.Tag.Eq(tagAckFailure))
}

func mustCallPayload(call z.Call) types.Payload {
	callBytes, err := z.EncodeCall(call)
	if err != nil {
		panic(err)
	}
	packetBytes, err := z.EncodeZkgmPacket(z.ZkgmPacket{
		Salt: [32]byte{},
		Path: u256.Zero(),
		Instruction: z.Instruction{
			Version: z.INSTR_VERSION_0,
			Opcode:  z.OP_CALL,
			Operand: callBytes,
		},
	})
	if err != nil {
		panic(err)
	}
	return types.Payload{
		SourcePort:      PortID,
		DestinationPort: PortID,
		Version:         z.PROTOCOL_VERSION,
		Encoding:        packetEncoding,
		Value:           packetBytes,
	}
}
