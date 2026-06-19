// PKGPATH: gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/testing/e2e/scenarios
package scenarios

import (
	types "gno.land/p/onbloc/ibc/union/types"

	u256 "gno.land/p/gnoswap/uint256"
	"gno.land/p/nt/testutils/v0"
	z "gno.land/p/onbloc/ibc/union/zkgm"
	e2e "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/testing/e2e"
	"gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/testing/mock"
	impl "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/v1"
	core "gno.land/r/onbloc/ibc/union/core"
)

const mockReceiverPath = "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/testing/mock"

func main(cur realm) {
	impl.Register(cross(cur))
	mock.Reset(cross(cur))
	e2e.RegisterMockLightClient(cross(cur))
	pair := e2e.OpenE2EChannelPair(cross(cur))

	receiver := string(testutils.TestAddress("receiver"))
	quoteToken := impl.PredictWrappedToken(u256.Zero(), uint32(pair.Destination), []byte("ugnot"))

	batch := z.Batch{Instructions: []z.Instruction{
		e2e.MustTokenOrderInstruction(cross(cur), z.TokenOrderV2{
			Sender:      []byte("sender"),
			Receiver:    []byte(receiver),
			BaseToken:   []byte("ugnot"),
			BaseAmount:  u256.NewUint(100),
			QuoteToken:  []byte(quoteToken),
			QuoteAmount: u256.NewUint(21),
			Kind:        z.TOKEN_ORDER_KIND_ESCROW,
		}),
		e2e.MustCallInstruction(cross(cur), z.Call{
			Sender:           []byte("sender"),
			ContractAddress:  []byte(mockReceiverPath),
			ContractCalldata: []byte("post-transfer-action"),
		}),
	}}
	packet := core.NewPacket(cross(cur), pair.Source, pair.Destination,
		e2e.MustPacketData(cross(cur), e2e.MustBatchInstruction(cross(cur), batch)), 0)

	core.PacketRecv(cross(cur), types.NewMsgPacketRecv([]types.Packet{packet}, nil, nil, 1))

	println("quote_balance", impl.VoucherBalanceOf(quoteToken, address(receiver)))
	println("mock_calls", mock.Calls(cross(cur)))
	println("last_calldata", mock.LastCalldata(cross(cur)))
	println("receipt_after_recv", core.HasPacketReceipt(cross(cur), packet))
	println("ack_after_recv", core.HasAcknowledgement(cross(cur), packet))
	println("recv_batch_token_order_and_call", "ok")
}

// Output:
// quote_balance 21
// mock_calls 1
// last_calldata post-transfer-action
// receipt_after_recv true
// ack_after_recv true
// recv_batch_token_order_and_call ok
