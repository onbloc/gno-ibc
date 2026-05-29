package impl

import (
	"testing"

	z "gno.land/p/gnoswap/ibc/zkgm"
	u256 "gno.land/p/gnoswap/uint256"
	"gno.land/p/nt/uassert/v0"
	core "gno.land/r/core/ibc/v1/core"
	"gno.land/r/gnoswap/ibc/v1/apps/zkgm/testing/mock"
)

func TestExecuteBatchTokenOrderAndCallBothSucceed(cur realm, t *testing.T) {
	resetTokenOrderTest(cur)
	mock.Reset(cross(cur))

	receiver := testAddress("batch-hook-receiver")
	relayer := testAddress("batch-hook-relayer")
	metaBytes := mustEncodeTokenMetadata(z.TokenMetadata{
		Implementation: []byte("grc20"),
		Initializer:    []byte("init"),
	})
	image := MetadataImage(mustDecodeTokenMetadata(metaBytes))
	path := u256.NewUint(9)
	destChannel := core.ChannelId(5)
	ibcDenom := PredictWrappedTokenV2(path, uint32(destChannel), []byte("ugnot"), image)

	batch := z.Batch{Instructions: []z.Instruction{
		batchMustOrderInstruction(z.TokenOrderV2{
			Sender:      []byte("sender"),
			Receiver:    []byte(receiver),
			BaseToken:   []byte("ugnot"),
			BaseAmount:  u256.NewUint(100),
			QuoteToken:  []byte(ibcDenom),
			QuoteAmount: u256.NewUint(100),
			Kind:        z.TOKEN_ORDER_KIND_INITIALIZE,
			Metadata:    metaBytes,
		}),
		batchMustCallInstruction(batchCall("sender", "hook-calldata")),
	}}
	packet := core.NewPacket(cross(cur), core.ChannelId(1), destChannel, nil, 0, 0)

	ackBytes, err := (&ZkgmV1{}).executeBatch(cur, packet, address(relayer), []byte("relay-msg"), path, [32]byte{0xCC}, batch, false)

	uassert.NoError(t, err)
	outerAck, err := z.DecodeAck(ackBytes)
	uassert.NoError(t, err)
	uassert.True(t, outerAck.Tag.Eq(tagAckSuccess))

	batchAck, err := z.DecodeBatchAck(outerAck.InnerAck)
	uassert.NoError(t, err)
	uassert.Equal(t, 2, len(batchAck.Acknowledgements))
	assertProtocolAck(t, batchAck.Acknowledgements[0])
	assertSuccessAck(t, batchAck.Acknowledgements[1])

	uassert.Equal(t, int64(100), VoucherBalanceOf(ibcDenom, address(receiver)))
	uassert.Equal(t, 1, mock.Calls(cross(cur)))
	uassert.Equal(t, "hook-calldata", mock.LastCalldata(cross(cur)))
}
