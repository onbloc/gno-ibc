package ucs03_zkgm

import (
	"testing"

	"gno.land/p/onbloc/ibc/union/types"

	"gno.land/p/nt/uassert/v0"
	z "gno.land/p/onbloc/ibc/union/zkgm"
	u256 "gno.land/p/onbloc/math/uint256"
	"gno.land/r/onbloc/ibc/union/core"
)

const forwardHandlerPkgPathForTest = "gno.land/r/onbloc/ibc/bridge/ics20zkgmadapter"

func TestExecuteTokenOrderV2Forward_NoHandlerRegistered(cur realm, t *testing.T) {
	testStore = newMockStore()
	v := newTestImpl()

	path := u256.Zero()
	destChan := types.ChannelId(2)
	receiver := testAddress("some-receiver")
	quoteDenom := z.PredictWrappedToken(path, uint32(destChan), []byte("ugnot"))
	_, err := v.getOrCreateVoucher(0, cur, quoteDenom, [32]byte{}, "T", "TOF0", canonicalDecimals)
	uassert.NoError(t, err)

	order := z.TokenOrderV2{
		Sender: []byte("sender"), Receiver: []byte(receiver),
		BaseToken: []byte("ugnot"), BaseAmount: u256.NewUint(100),
		QuoteToken: []byte(quoteDenom), QuoteAmount: u256.NewUint(21),
		Kind: z.TOKEN_ORDER_KIND_ESCROW,
	}
	packet := core.NewPacket(types.ChannelId(1), destChan, nil, 0)

	res, err := v.executeTokenOrderV2(0, cur, packet, address(testAddress("relayer")), nil, [32]byte{}, path, order, false)

	uassert.NoError(t, err)
	uassert.True(t, res.Status == types.PacketStatusSuccess)
	uassert.Equal(t, int64(21), voucherBalanceOf(quoteDenom, receiver))
}

func TestExecuteTokenOrderV2Forward_ReceiverMismatch(cur realm, t *testing.T) {
	testStore = newMockStore()
	ResetForwardHandler(cross(cur))
	handlerAddr := testAddress("forward-handler")
	testStore.SetTokenForwardHandler(0, cur, mockFwd, handlerAddr, forwardHandlerPkgPathForTest)
	v := newTestImpl()

	path := u256.Zero()
	destChan := types.ChannelId(2)
	receiver := testAddress("someone-else")
	quoteDenom := z.PredictWrappedToken(path, uint32(destChan), []byte("ugnot"))
	_, err := v.getOrCreateVoucher(0, cur, quoteDenom, [32]byte{}, "T", "TOFM", canonicalDecimals)
	uassert.NoError(t, err)

	order := z.TokenOrderV2{
		Sender: []byte("sender"), Receiver: []byte(receiver),
		BaseToken: []byte("ugnot"), BaseAmount: u256.NewUint(100),
		QuoteToken: []byte(quoteDenom), QuoteAmount: u256.NewUint(21),
		Kind: z.TOKEN_ORDER_KIND_ESCROW,
	}
	packet := core.NewPacket(types.ChannelId(1), destChan, nil, 0)

	res, err := v.executeTokenOrderV2(0, cur, packet, address(testAddress("relayer")), nil, [32]byte{}, path, order, false)

	uassert.NoError(t, err)
	uassert.True(t, res.Status == types.PacketStatusSuccess)
	uassert.Equal(t, 0, ForwardPrepareCalls(cross(cur)))
	uassert.Equal(t, int64(21), voucherBalanceOf(quoteDenom, receiver))
}

func TestExecuteTokenOrderV2Forward_Success(cur realm, t *testing.T) {
	testStore = newMockStore()
	ResetForwardHandler(cross(cur))
	v := newTestImpl()

	path := u256.Zero()
	destChan := types.ChannelId(8)
	handlerAddr := testAddress("forward-handler")
	testStore.SetTokenForwardHandler(0, cur, mockFwd, handlerAddr, forwardHandlerPkgPathForTest)

	quoteDenom := z.PredictWrappedToken(path, uint32(destChan), []byte("ugnot"))
	_, err := v.getOrCreateVoucher(0, cur, quoteDenom, [32]byte{}, "T", "TOF1", canonicalDecimals)
	uassert.NoError(t, err)

	order := z.TokenOrderV2{
		Sender:      []byte("sender"),
		Receiver:    []byte(handlerAddr),
		BaseToken:   []byte("ugnot"),
		BaseAmount:  u256.NewUint(100),
		QuoteToken:  []byte(quoteDenom),
		QuoteAmount: u256.NewUint(21),
		Kind:        z.TOKEN_ORDER_KIND_ESCROW,
		Metadata:    []byte(`{"forward":{"destination_client":"07-tendermint-1","atomone_receiver":"atone1receiver"}}`),
	}
	packet := core.NewPacket(types.ChannelId(7), destChan, nil, 0)

	res, err := v.executeTokenOrderV2(0, cur, packet, address(testAddress("relayer")), nil, [32]byte{}, path, order, false)

	uassert.NoError(t, err)
	uassert.True(t, res.Status == types.PacketStatusAsync)
	uassert.True(t, len(res.Acknowledgement) == 0)
	uassert.Equal(t, 1, ForwardPrepareCalls(cross(cur)))
	uassert.Equal(t, 1, ForwardExecuteCalls(cross(cur)))
	uassert.Equal(t, int64(21), voucherBalanceOf(quoteDenom, handlerAddr))
	uassert.Equal(t, "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/v1.TOF1", LastForwardBaseTokenKey(cross(cur)))
	uassert.Equal(t, int64(21), LastForwardAmount(cross(cur)))
	uassert.Equal(t, `{"forward":{"destination_client":"07-tendermint-1","atomone_receiver":"atone1receiver"}}`, LastForwardMemo(cross(cur)))

	corrID := tokenForwardCorrID(packet)
	uassert.Equal(t, corrID, LastForwardCorrID(cross(cur)))
	_, found := testStore.GetPendingTokenForward(corrID)
	uassert.True(t, found)
}

func TestExecuteTokenOrderV2Forward_PrepareErrorReturnsFailureAckWithoutMintOrPendingState(cur realm, t *testing.T) {
	testStore = newMockStore()
	ResetForwardHandler(cross(cur))
	v := newTestImpl()

	path := u256.Zero()
	destChan := types.ChannelId(9)
	handlerAddr := testAddress("forward-handler-2")
	testStore.SetTokenForwardHandler(0, cur, mockFwd, handlerAddr, forwardHandlerPkgPathForTest)
	SetForwardPrepareErr(cross(cur), "bad routing memo")

	quoteDenom := z.PredictWrappedToken(path, uint32(destChan), []byte("ugnot"))
	_, err := v.getOrCreateVoucher(0, cur, quoteDenom, [32]byte{}, "T", "TOF2", canonicalDecimals)
	uassert.NoError(t, err)

	order := z.TokenOrderV2{
		Sender:      []byte("sender"),
		Receiver:    []byte(handlerAddr),
		BaseToken:   []byte("ugnot"),
		BaseAmount:  u256.NewUint(100),
		QuoteToken:  []byte(quoteDenom),
		QuoteAmount: u256.NewUint(21),
		Kind:        z.TOKEN_ORDER_KIND_ESCROW,
		Metadata:    []byte("not valid json"),
	}
	packet := core.NewPacket(types.ChannelId(7), destChan, nil, 0)

	res, err := v.executeTokenOrderV2(0, cur, packet, address(testAddress("relayer")), nil, [32]byte{}, path, order, false)

	uassert.NoError(t, err)
	uassert.True(t, res.Status == types.PacketStatusFailure)
	uassert.Equal(t, 0, ForwardExecuteCalls(cross(cur)))
	uassert.Equal(t, int64(0), voucherBalanceOf(quoteDenom, handlerAddr))

	_, found := testStore.GetPendingTokenForward(tokenForwardCorrID(packet))
	uassert.False(t, found)
}
