// PKGPATH: gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/testing/e2e/scenarios_batchsend
package scenarios_batchsend

import (
	"errors"

	"gno.land/p/onbloc/ibc/union/lightclient"
	types "gno.land/p/onbloc/ibc/union/types"

	u256 "gno.land/p/gnoswap/uint256"
	"gno.land/p/nt/testutils/v0"
	z "gno.land/p/onbloc/ibc/union/zkgm"
	zkgm "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm"
	e2e "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/testing/e2e"
	impl "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/v1"
	core "gno.land/r/onbloc/ibc/union/core"
)

const timeoutScenarioClientType = types.ClientType("gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/testing/e2e/scenarios_batchsend/timeout")

type timeoutScenarioLightClient struct{}

func (m *timeoutScenarioLightClient) VerifyMembership(uint64, []byte, []byte, []byte) error {
	return nil
}

func (m *timeoutScenarioLightClient) VerifyNonMembership(uint64, []byte, []byte) error {
	return nil
}

func (m *timeoutScenarioLightClient) GetTimestamp() types.Timestamp {
	return types.Timestamp(2)
}

func (m *timeoutScenarioLightClient) GetTimestampAtHeight(uint64) (types.Timestamp, error) {
	return types.Timestamp(2), nil
}

func (m *timeoutScenarioLightClient) GetLatestHeight() uint64 {
	return 1
}

func (m *timeoutScenarioLightClient) GetCounterpartyChainID() string {
	return "timeout-scenario-chain"
}

func (m *timeoutScenarioLightClient) Status() lightclient.Status {
	return lightclient.Active
}

func (m *timeoutScenarioLightClient) VerifyHeader(_ address, header []byte, _ address) (types.StateUpdate, error) {
	return types.StateUpdate{Height: 1, ClientStateBytes: header, ConsensusStateBytes: header}, nil
}

func (m *timeoutScenarioLightClient) VerifyCreation(address, address) (types.ClientCreationResult, error) {
	return types.ClientCreationResult{}, nil
}

func (m *timeoutScenarioLightClient) Misbehaviour(address, []byte, address) (types.ClientState, error) {
	return nil, errors.New("mock: misbehaviour unsupported")
}

func main(cur realm) {
	impl.Register(cross(cur))
	pair := openTimeoutScenarioChannelPair(cross(cur))
	sender := string(testutils.TestAddress("timeout-sender"))
	marketMaker := "g1wymu47drhr0kuq2098m792lytgtj2nyx77yrsm"

	order := z.TokenOrderV2{
		Sender:      []byte(sender),
		Receiver:    []byte(marketMaker),
		BaseToken:   []byte("ibc/base"),
		BaseAmount:  u256.NewUint(21),
		QuoteToken:  []byte("ugnot"),
		QuoteAmount: u256.NewUint(21),
		Kind:        z.TOKEN_ORDER_KIND_UNESCROW,
	}
	packet := core.NewPacket(pair.Source, pair.Destination, e2e.MustPacketData(cross(cur), e2e.MustTokenOrderInstruction(cross(cur), order)), types.Timestamp(1))
	ack := e2e.MustSuccessAck(cross(cur), mustMarketMakerTokenOrderAck([]byte(marketMaker)))
	ackMsg := types.NewMsgPacketAcknowledgement([]types.Packet{packet}, [][]byte{ack}, nil, 1)

	// This file exercises core idempotency only. BatchSend plants the packet
	// commitment directly and intentionally bypasses the send-side voucher escrow.
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
	core.PacketTimeout(cross(cur), types.NewMsgPacketTimeout(packet, nil, 1))
	println("sender_after_timeout_after_ack", impl.VoucherBalanceOf(string(order.BaseToken), address(sender)))

	println("")
	println("[SCENARIO] 4. ack after timeout is skipped")
	e2e.BatchSend(cross(cur), packet)
	core.PacketTimeout(cross(cur), types.NewMsgPacketTimeout(packet, nil, 1))
	println("commitment_after_timeout", core.HasPacketCommitment(cross(cur), packet))
	println("sender_after_timeout", impl.VoucherBalanceOf(string(order.BaseToken), address(sender)))

	core.PacketAcknowledgement(cross(cur), ackMsg)
	println("market_maker_after_ack_after_timeout", impl.VoucherBalanceOf(string(order.BaseToken), address(marketMaker)))
	println("sender_after_ack_after_timeout", impl.VoucherBalanceOf(string(order.BaseToken), address(sender)))
	println("ack_timeout_noops", "ok")
}

func openTimeoutScenarioChannelPair(cur realm) e2e.ChannelPair {
	if !core.HasClient(timeoutScenarioClientType) {
		core.RegisterClient(cross(cur), timeoutScenarioClientType, &timeoutScenarioLightClient{})
	}
	clientId := core.CreateClient(cross(cur), types.NewMsgCreateClient(timeoutScenarioClientType, nil, nil))
	connectionId := types.ConnectionId(1)
	core.ConnectionOpenInit(cross(cur), types.NewMsgConnectionOpenInit(clientId, types.ClientId(99)))
	core.ConnectionOpenAck(cross(cur), types.NewMsgConnectionOpenAck(connectionId, types.ConnectionId(77), nil, 1))

	portId := []byte(zkgm.ProxyPkgPath())
	source := core.ChannelOpenInit(cross(cur), types.NewMsgChannelOpenInit(portId, portId, connectionId, zkgm.Version, "g1msgrelayer"))
	core.ChannelOpenAck(cross(cur), types.NewMsgChannelOpenAck(source, zkgm.Version, types.ChannelId(2), nil, 1, "g1msgrelayer"))
	return e2e.NewChannelPair(cross(cur), clientId, connectionId, source, types.ChannelId(2))
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
// commitment_after_first_ack false
// market_maker_after_first_ack 21
//
// [SCENARIO] 2. duplicate ack is skipped
// commitment_after_second_ack false
// market_maker_after_second_ack 21
//
// [SCENARIO] 3. timeout after ack is skipped
// sender_after_timeout_after_ack 0
//
// [SCENARIO] 4. ack after timeout is skipped
// commitment_after_timeout false
// sender_after_timeout 21
// market_maker_after_ack_after_timeout 21
// sender_after_ack_after_timeout 21
// ack_timeout_noops ok
