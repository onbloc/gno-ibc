// PKGPATH: gno.land/r/onbloc/unionibc/v1/apps/zkgm/testing/e2e/scenarios_batchsend
package scenarios_batchsend

import (
	u256 "gno.land/p/gnoswap/uint256"
	"gno.land/p/nt/testutils/v0"
	z "gno.land/p/onbloc/unionibc/zkgm"
	zkgm "gno.land/r/onbloc/unionibc/v1/apps/zkgm"
	e2e "gno.land/r/onbloc/unionibc/v1/apps/zkgm/testing/e2e"
	_ "gno.land/r/onbloc/unionibc/v1/apps/zkgm/testing/loader"
	impl "gno.land/r/onbloc/unionibc/v1/apps/zkgm/v0/impl"
	core "gno.land/r/onbloc/unionibc/v1/core"
)

const timeoutScenarioClientType = core.ClientType("gno.land/r/onbloc/unionibc/v1/apps/zkgm/testing/e2e/scenarios_batchsend/timeout")

type timeoutScenarioLightClient struct{}

func (m *timeoutScenarioLightClient) CreateClient(_ realm, clientId core.ClientId, clientStateBytes, consensusStateBytes []byte) string {
	return "timeout-scenario-chain"
}

func (m *timeoutScenarioLightClient) UpdateClient(cur realm, clientId core.ClientId, clientMessage []byte) core.ConsensusStateUpdate {
	return core.NewConsensusStateUpdate(cross(cur), core.Height(1), clientMessage, clientMessage)
}

func (m *timeoutScenarioLightClient) VerifyMembership(clientId core.ClientId, height core.Height, proof []byte, key []byte, value []byte) {
}

func (m *timeoutScenarioLightClient) VerifyNonMembership(clientId core.ClientId, height core.Height, proof []byte, key []byte) {
}

func (m *timeoutScenarioLightClient) GetTimestamp(clientId core.ClientId, height core.Height) core.Timestamp {
	return core.Timestamp(2)
}

func (m *timeoutScenarioLightClient) GetLatestHeight(clientId core.ClientId) core.Height {
	return core.Height(1)
}

func (m *timeoutScenarioLightClient) GetStatus(clientId core.ClientId) core.Status {
	return core.StatusActive
}

func main(cur realm) {
	pair := openTimeoutScenarioChannelPair(cross(cur))
	sender := string(testutils.TestAddress("timeout-sender"))
	marketMaker := "g1wymu47drhr0kuq2098m792lytgtj2nyx77yrsm"

	order := z.TokenOrderV2{
		Sender:      []byte(sender),
		Receiver:    []byte("timeout-only-receiver"),
		BaseToken:   []byte("ibc/base"),
		BaseAmount:  u256.NewUint(21),
		QuoteToken:  []byte("ugnot"),
		QuoteAmount: u256.NewUint(21),
		Kind:        z.TOKEN_ORDER_KIND_UNESCROW,
	}
	packet := core.NewPacket(cross(cur), pair.Source, pair.Destination, e2e.MustPacketData(cross(cur), e2e.MustTokenOrderInstruction(cross(cur), order)), 0, core.Timestamp(1))
	ack := e2e.MustSuccessAck(cross(cur), mustMarketMakerTokenOrderAck([]byte(marketMaker)))
	ackMsg := core.NewMsgPacketAcknowledgement(cross(cur), []core.Packet{packet}, [][]byte{ack}, nil, core.Height(1))

	// This file exercises core idempotency only. BatchSend plants the packet
	// commitment directly and intentionally bypasses the send-side voucher burn.
	println("[SCENARIO] 1. first ack settles")
	e2e.BatchSend(cross(cur), packet)
	core.PacketAcknowledgement(cross(cur), ackMsg)
	println("commitment_after_first_ack", core.HasPacketCommitment(cross(cur), packet))
	println("market_maker_after_first_ack", impl.VoucherBalanceOf(string(order.BaseToken), address(marketMaker)))

	println("")
	println("[SCENARIO] 2. duplicate ack is skipped")
	core.PacketAcknowledgement(cross(cur), ackMsg)
	println("commitment_after_second_ack", core.HasPacketCommitment(cross(cur), packet))
	println("market_maker_after_second_ack", impl.VoucherBalanceOf(string(order.BaseToken), address(marketMaker)))

	println("")
	println("[SCENARIO] 3. timeout after ack is skipped")
	core.PacketTimeout(cross(cur), core.NewMsgPacketTimeout(cross(cur), packet, nil, core.Height(1)))
	println("sender_after_timeout_after_ack", impl.VoucherBalanceOf(string(order.BaseToken), address(sender)))

	println("")
	println("[SCENARIO] 4. ack after timeout is skipped")
	timeoutPacket := core.NewPacket(cross(cur), pair.Source, pair.Destination, e2e.MustPacketData(cross(cur), e2e.MustTokenOrderInstruction(cross(cur), z.TokenOrderV2{
		Sender:      []byte(sender),
		Receiver:    []byte(marketMaker),
		BaseToken:   []byte("ibc/base"),
		BaseAmount:  u256.NewUint(21),
		QuoteToken:  []byte("ugnot"),
		QuoteAmount: u256.NewUint(21),
		Kind:        z.TOKEN_ORDER_KIND_UNESCROW,
	})), 0, core.Timestamp(1))
	e2e.BatchSend(cross(cur), timeoutPacket)
	core.PacketTimeout(cross(cur), core.NewMsgPacketTimeout(cross(cur), timeoutPacket, nil, core.Height(1)))
	println("commitment_after_timeout", core.HasPacketCommitment(cross(cur), timeoutPacket))
	println("sender_after_timeout", impl.VoucherBalanceOf(string(order.BaseToken), address(sender)))

	core.PacketAcknowledgement(cross(cur), core.NewMsgPacketAcknowledgement(cross(cur), []core.Packet{timeoutPacket}, [][]byte{ack}, nil, core.Height(1)))
	println("market_maker_after_ack_after_timeout", impl.VoucherBalanceOf(string(order.BaseToken), address(marketMaker)))
	println("sender_after_ack_after_timeout", impl.VoucherBalanceOf(string(order.BaseToken), address(sender)))
	println("ack_timeout_noops", "ok")
}

func openTimeoutScenarioChannelPair(cur realm) e2e.ChannelPair {
	if !core.HasClient(timeoutScenarioClientType) {
		core.RegisterClient(cross(cur), timeoutScenarioClientType, &timeoutScenarioLightClient{})
	}
	clientId := core.CreateClient(cross(cur), core.NewMsgCreateClient(cross(cur), timeoutScenarioClientType, nil, nil))
	connectionId := core.ConnectionOpenInit(cross(cur), core.NewMsgConnectionOpenInit(cross(cur), clientId, core.ClientId(99)))
	core.ConnectionOpenAck(cross(cur), core.NewMsgConnectionOpenAck(cross(cur), connectionId, core.ConnectionId(77), nil, core.Height(1)))

	portId := []byte(zkgm.ProxyPkgPath())
	source := core.ChannelOpenInit(cross(cur), core.NewMsgChannelOpenInit(cross(cur), portId, portId, connectionId, zkgm.Version))
	core.ChannelOpenAck(cross(cur), core.NewMsgChannelOpenAck(cross(cur), source, zkgm.Version, core.ChannelId(2), nil, core.Height(1)))
	return e2e.NewChannelPair(cross(cur), clientId, connectionId, source, core.ChannelId(2))
}

func mustMarketMakerTokenOrderAck(marketMaker []byte) []byte {
	bz, err := z.EncodeTokenOrderAck(z.TokenOrderAck{
		FillType:    new(u256.Uint).SetBytes(z.FILL_TYPE_MARKETMAKER[:]),
		MarketMaker: marketMaker,
	})
	if err != nil {
		panic(err)
	}
	return bz
}

// Output:
// [SCENARIO] 1. first ack settles
// commitment_after_first_ack true
// market_maker_after_first_ack 21
//
// [SCENARIO] 2. duplicate ack is skipped
// commitment_after_second_ack true
// market_maker_after_second_ack 21
//
// [SCENARIO] 3. timeout after ack is skipped
// sender_after_timeout_after_ack 0
//
// [SCENARIO] 4. ack after timeout is skipped
// commitment_after_timeout true
// sender_after_timeout 21
// market_maker_after_ack_after_timeout 21
// sender_after_ack_after_timeout 21
// ack_timeout_noops ok
