// PKGPATH: gno.land/r/onbloc/unionibc/v1/apps/zkgm/testing/loader
package loader

import (
	u256 "gno.land/p/gnoswap/uint256"
	"gno.land/p/nt/testutils/v0"
	z "gno.land/p/onbloc/unionibc/zkgm"
	zkgm "gno.land/r/onbloc/unionibc/v1/apps/zkgm"
	e2e "gno.land/r/onbloc/unionibc/v1/apps/zkgm/testing/e2e"
	"gno.land/r/onbloc/unionibc/v1/apps/zkgm/testing/mock"
	sh "gno.land/r/onbloc/unionibc/v1/apps/zkgm/testing/scenariohelpers"
	impl "gno.land/r/onbloc/unionibc/v1/apps/zkgm/v0/impl"
	core "gno.land/r/onbloc/unionibc/v1/core"
)

const zs86MockReceiverPath = "gno.land/r/onbloc/unionibc/v1/apps/zkgm/testing/mock"

func main(cur realm) {
	inst := sh.InstallImpl(cross(cur))
	zkgm.RegisterCoreApp(cross(cur))
	e2e.RegisterMockLightClient(cross(cur))
	pair := e2e.OpenE2EChannelPair(cross(cur))

	marketMaker := cur.Address()
	receiver := string(testutils.TestAddress("zs86-receiver"))
	quoteToken := sh.MintVoucher(cross(cur), inst, pair.Destination, "zs86-base", marketMaker.String(), 12, "ZS86")
	order := z.TokenOrderV2{
		Sender:      []byte("sender"),
		Receiver:    []byte(receiver),
		BaseToken:   []byte("remote-base"),
		BaseAmount:  u256.NewUint(12),
		QuoteToken:  []byte(quoteToken),
		QuoteAmount: u256.NewUint(12),
		Kind:        z.TOKEN_ORDER_KIND_ESCROW,
	}
	intentPacket := core.NewPacket(cross(cur), pair.Source, pair.Destination,
		e2e.MustPacketData(cross(cur), e2e.MustTokenOrderInstruction(cross(cur), order)), 0, core.Timestamp(1<<62))

	println("[SCENARIO] fillable token order intent preempts proven recv")
	core.IntentPacketRecv(cross(cur), core.NewMsgIntentPacketRecv(cross(cur), []core.Packet{intentPacket}, nil))
	println("maker_quote_after_intent", impl.VoucherBalanceOf(quoteToken, marketMaker))
	println("receiver_quote_after_intent", impl.VoucherBalanceOf(quoteToken, address(receiver)))
	println("intent_receipt", core.HasPacketReceipt(cross(cur), intentPacket))
	core.PacketRecv(cross(cur), core.NewMsgPacketRecv(cross(cur), []core.Packet{intentPacket}, nil, nil, core.Height(1)))
	println("receiver_quote_after_proven_recv", impl.VoucherBalanceOf(quoteToken, address(receiver)))

	println("")
	println("[SCENARIO] op call intent fails closed before receiver")
	mock.Reset(cross(cur))
	callPacket := core.NewPacket(cross(cur), pair.Source, pair.Destination,
		e2e.MustPacketData(cross(cur), e2e.MustCallInstruction(cross(cur), z.Call{
			Sender:           []byte("sender"),
			ContractAddress:  []byte(zs86MockReceiverPath),
			ContractCalldata: []byte("intent-call"),
		})), 0, core.Timestamp(1<<62))
	println("call_intent_reverted", zs86IntentRecvReverted(cur, callPacket))
	println("call_mock_calls", mock.Calls(cross(cur)))
	// revive catches the panic inside this filetest transaction, so the receipt
	// write is observable here. A top-level failed tx would roll this state back.
	println("call_receipt_in_recovered_harness", core.HasPacketReceipt(cross(cur), callPacket))
}

func zs86IntentRecvReverted(cur realm, packet core.Packet) (reverted bool) {
	p := revive(func() {
		core.IntentPacketRecv(cross(cur), core.NewMsgIntentPacketRecv(cross(cur), []core.Packet{packet}, nil))
	})
	return p != nil
}

// Output:
// [SCENARIO] fillable token order intent preempts proven recv
// maker_quote_after_intent 0
// receiver_quote_after_intent 12
// intent_receipt true
// receiver_quote_after_proven_recv 12
//
// [SCENARIO] op call intent fails closed before receiver
// call_intent_reverted true
// call_mock_calls 0
// call_receipt_in_recovered_harness true
