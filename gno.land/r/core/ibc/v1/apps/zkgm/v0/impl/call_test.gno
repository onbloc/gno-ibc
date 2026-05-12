package impl

import (
	"testing"

	z "gno.land/p/gnoswap/ibc/zkgm"
	u256 "gno.land/p/gnoswap/uint256"
	"gno.land/p/nt/uassert/v0"
	core "gno.land/r/core/ibc/v1/core"
	"gno.land/r/gnoswap/ibc/v1/apps/zkgm/testing/mock"
)

const mockReceiverPath = "gno.land/r/gnoswap/ibc/v1/apps/zkgm/testing/mock"

func TestExecuteCallDispatchesOnZkgm(cur realm, t *testing.T) {
	mock.Reset(cross)
	packet := core.Packet{SourceChannelId: core.ChannelId(7), DestinationChannelId: core.ChannelId(8)}
	call := z.Call{
		Sender:           []byte("sender"),
		ContractAddress:  []byte(mockReceiverPath),
		ContractCalldata: []byte("calldata"),
	}
	path := u256.NewUint(9)

	res, err := (&ZkgmV1{}).executeCall(packet, address("g1relayer"), []byte("relay-msg"), path, call)

	uassert.NoError(t, err)
	uassert.True(t, res.Status == core.PacketStatusSuccess)
	ack, err := z.DecodeAck(res.Ack)
	uassert.NoError(t, err)
	uassert.True(t, ack.Tag.Eq(tagAckSuccess))
	uassert.Equal(t, 1, mock.Calls(cross))
	uassert.Equal(t, "7", mock.LastSourceChannel(cross))
	uassert.Equal(t, "8", mock.LastDestinationChannel(cross))
	uassert.Equal(t, "sender", mock.LastSender(cross))
	uassert.Equal(t, "calldata", mock.LastCalldata(cross))
	uassert.Equal(t, "g1relayer", mock.LastCaller(cross))
	uassert.Equal(t, "g1relayer", mock.LastRelayer(cross))
	uassert.Equal(t, "relay-msg", mock.LastRelayerMsg(cross))
	uassert.Equal(t, "9", mock.LastPathDec(cross))
	uassert.Equal(t, PredictCallProxyAccount(path, core.ChannelId(8), []byte("sender")), mock.LastProxyAccount(cross))
}

func TestExecuteCallReceiverErrorReturnsFailureAck(cur realm, t *testing.T) {
	mock.Reset(cross)
	mock.SetError(cross, "receiver failed")
	packet := core.Packet{SourceChannelId: core.ChannelId(7), DestinationChannelId: core.ChannelId(8)}

	res, err := (&ZkgmV1{}).executeCall(packet, address("g1relayer"), nil, u256.Zero(), z.Call{
		Sender:          []byte("sender"),
		ContractAddress: []byte(mockReceiverPath),
	})

	uassert.NoError(t, err)
	uassert.True(t, res.Status == core.PacketStatusFailure)

	ack, err := z.DecodeAck(res.Ack)
	uassert.NoError(t, err)
	uassert.True(t, ack.Tag.Eq(tagAckFailure))
	uassert.Equal(t, "receiver failed", string(ack.InnerAck))
}

func TestExecuteCallReceiverPanicReturnsOnlyMakerAck(cur realm, t *testing.T) {
	mock.Reset(cross)
	mock.SetPanic(cross, "boom")
	packet := core.Packet{SourceChannelId: core.ChannelId(7), DestinationChannelId: core.ChannelId(8)}

	res, err := (&ZkgmV1{}).executeCall(packet, address("g1relayer"), nil, u256.Zero(), z.Call{
		Sender:          []byte("sender"),
		ContractAddress: []byte(mockReceiverPath),
	})

	uassert.NoError(t, err)
	uassert.True(t, res.Status == core.PacketStatusSuccess)
	uassert.True(t, equalBytes(z.ACK_ERR_ONLY_MAKER, res.Ack))
}

func TestVerifyCallRejectsInvalidSender(cur realm, t *testing.T) {
	err := (&ZkgmV1{}).verifyCall("actual", z.Call{
		Sender: []byte("other"),
	})

	uassert.ErrorContains(t, err, "invalid call sender")
}
