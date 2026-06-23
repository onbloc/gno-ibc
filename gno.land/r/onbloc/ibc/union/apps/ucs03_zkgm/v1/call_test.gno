package impl

import (
	"bytes"
	"testing"

	types "gno.land/p/onbloc/ibc/union/types"

	u256 "gno.land/p/gnoswap/uint256"
	"gno.land/p/nt/uassert/v0"
	z "gno.land/p/onbloc/ibc/union/zkgm"
	"gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/testing/mock"
	core "gno.land/r/onbloc/ibc/union/core"
)

const mockReceiverPath = "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/testing/mock"

func TestExecuteCallDispatchesOnZkgm(cur realm, t *testing.T) {
	mock.Reset(cross(cur))
	testStore.SetReceiver(0, cur, mockReceiverPath, mock.Zkgmable(cross(cur)))
	packet := core.NewPacket(types.ChannelId(7), types.ChannelId(8), nil, 0)
	call := z.Call{
		Sender:           []byte("sender"),
		ContractAddress:  []byte(mockReceiverPath),
		ContractCalldata: []byte("calldata"),
	}
	path := u256.NewUint(9)

	res, err := newTestImpl().executeCall(0, cur, packet, address("g1relayer"), []byte("relay-msg"), path, call, false)

	uassert.NoError(t, err)
	uassert.True(t, res.Status == types.PacketStatusSuccess)
	ack, err := z.DecodeAck(res.Acknowledgement)
	uassert.NoError(t, err)
	uassert.True(t, ack.Tag.Eq(tagAckSuccess()))
	uassert.Equal(t, 1, mock.Calls(cross(cur)))
	uassert.Equal(t, "7", mock.LastSourceChannel(cross(cur)))
	uassert.Equal(t, "8", mock.LastDestinationChannel(cross(cur)))
	uassert.Equal(t, "sender", mock.LastSender(cross(cur)))
	uassert.Equal(t, "calldata", mock.LastCalldata(cross(cur)))
	uassert.Equal(t, "g1relayer", mock.LastCaller(cross(cur)))
	uassert.Equal(t, "g1relayer", mock.LastRelayer(cross(cur)))
	uassert.Equal(t, "relay-msg", mock.LastRelayerMsg(cross(cur)))
	uassert.Equal(t, "9", mock.LastPathDec(cross(cur)))
	uassert.Equal(t, z.PredictCallProxyAccount(path, types.ChannelId(8), []byte("sender")), mock.LastProxyAccount(cross(cur)))
}

func TestExecuteCallReceiverErrorReturnsFailureAck(cur realm, t *testing.T) {
	mock.Reset(cross(cur))
	testStore.SetReceiver(0, cur, mockReceiverPath, mock.Zkgmable(cross(cur)))
	mock.SetError(cross(cur), "receiver failed")
	packet := core.NewPacket(types.ChannelId(7), types.ChannelId(8), nil, 0)

	res, err := newTestImpl().executeCall(0, cur, packet, address("g1relayer"), nil, u256.Zero(), z.Call{
		Sender:          []byte("sender"),
		ContractAddress: []byte(mockReceiverPath),
	}, false)

	uassert.NoError(t, err)
	uassert.True(t, res.Status == types.PacketStatusFailure)

	ack, err := z.DecodeAck(res.Acknowledgement)
	uassert.NoError(t, err)
	uassert.True(t, ack.Tag.Eq(tagAckFailure()))
	uassert.Equal(t, "receiver failed", string(ack.InnerAck))
}

func TestExecuteCallReceiverPanicReturnsOnlyMakerAck(cur realm, t *testing.T) {
	mock.Reset(cross(cur))
	testStore.SetReceiver(0, cur, mockReceiverPath, mock.Zkgmable(cross(cur)))
	mock.SetPanic(cross(cur), "boom")
	packet := core.NewPacket(types.ChannelId(7), types.ChannelId(8), nil, 0)

	res, err := newTestImpl().executeCall(0, cur, packet, address("g1relayer"), nil, u256.Zero(), z.Call{
		Sender:          []byte("sender"),
		ContractAddress: []byte(mockReceiverPath),
	}, false)

	uassert.NoError(t, err)
	uassert.True(t, res.Status == types.PacketStatusSuccess)
	uassert.True(t, bytes.Equal(z.ACK_ERR_ONLY_MAKER, res.Acknowledgement))
}

func TestExecuteCallIntentDispatchesOnIntentZkgm(cur realm, t *testing.T) {
	mock.Reset(cross(cur))
	testStore.SetReceiver(0, cur, mockReceiverPath, mock.Zkgmable(cross(cur)))
	packet := core.NewPacket(types.ChannelId(7), types.ChannelId(8), nil, 0)

	res, err := newTestImpl().executeCall(0, cur, packet, address("g1maker"), []byte("mm-msg"), u256.NewUint(9), z.Call{
		Sender:           []byte("sender"),
		ContractAddress:  []byte(mockReceiverPath),
		ContractCalldata: []byte("calldata"),
	}, true)

	uassert.NoError(t, err)
	uassert.True(t, res.Status == types.PacketStatusSuccess)
	ack, err := z.DecodeAck(res.Acknowledgement)
	uassert.NoError(t, err)
	uassert.True(t, ack.Tag.Eq(tagAckSuccess()))
	// The receiver's intent callback ran (not the standard OnZkgm), and saw the env.
	uassert.Equal(t, 1, mock.IntentCalls(cross(cur)))
	uassert.Equal(t, 0, mock.Calls(cross(cur)))
	uassert.Equal(t, "calldata", mock.LastIntentCalldata(cross(cur)))
	uassert.Equal(t, "g1maker", mock.LastIntentMarketMaker(cross(cur)))
}

func TestIntentRecvOnlyMakerCallAborts(cur realm, t *testing.T) {
	mock.Reset(cross(cur))
	testStore.SetReceiver(0, cur, mockReceiverPath, mock.Zkgmable(cross(cur)))
	mock.SetPanic(cross(cur), "boom")
	data := mustZkgmPacketBytes(batchMustCallInstruction(z.Call{
		Sender:          []byte("sender"),
		ContractAddress: []byte(mockReceiverPath),
	}))
	packet := core.NewPacket(types.ChannelId(7), types.ChannelId(8), data, 0)

	uassert.AbortsContains(t, cur, "zkgm: only maker", func(cur realm) {
		newTestImpl().OnIntentRecvPacket(0, cur, packet, address("g1relayer"), nil)
	})
}

func TestVerifyCallRejectsInvalidSender(cur realm, t *testing.T) {
	err := newTestImpl().verifyCall(0, cur, z.Call{
		Sender: []byte("other"),
	})

	uassert.ErrorContains(t, err, "invalid call sender")
}
