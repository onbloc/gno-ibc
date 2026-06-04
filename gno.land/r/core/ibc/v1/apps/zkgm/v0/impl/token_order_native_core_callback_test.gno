package impl

import (
	"chain"
	"chain/banker"
	"testing"

	z "gno.land/p/onbloc/unionibc/zkgm"
	u256 "gno.land/p/gnoswap/uint256"
	"gno.land/p/nt/uassert/v0"
	core "gno.land/r/onbloc/unionibc/v1/core"
	zkgm "gno.land/r/onbloc/unionibc/v1/apps/zkgm"
	e2e "gno.land/r/onbloc/unionibc/v1/apps/zkgm/testing/e2e"
)

const timeoutMockClientType = core.ClientType("gno.land/r/onbloc/unionibc/v1/apps/zkgm/v0/impl/timeout-mock")

type timeoutMockLightClient struct{}

func (m *timeoutMockLightClient) CreateClient(_ realm, clientId core.ClientId, clientStateBytes, consensusStateBytes []byte) string {
	return "timeout-mock-chain"
}

func (m *timeoutMockLightClient) UpdateClient(_ realm, clientId core.ClientId, clientMessage []byte) core.ConsensusStateUpdate {
	return core.ConsensusStateUpdate{
		Height:              core.Height(1),
		ClientStateBytes:    clientMessage,
		ConsensusStateBytes: clientMessage,
	}
}

func (m *timeoutMockLightClient) VerifyMembership(clientId core.ClientId, height core.Height, proof []byte, key []byte, value []byte) {
}

func (m *timeoutMockLightClient) VerifyNonMembership(clientId core.ClientId, height core.Height, proof []byte, key []byte) {
}

func (m *timeoutMockLightClient) GetTimestamp(clientId core.ClientId, height core.Height) core.Timestamp {
	return core.Timestamp(2)
}

func (m *timeoutMockLightClient) GetLatestHeight(clientId core.ClientId) core.Height {
	return core.Height(1)
}

func (m *timeoutMockLightClient) GetStatus(clientId core.ClientId) core.Status {
	return core.StatusActive
}

func TestPacketAcknowledgementFailureRefundsNativeFromProxy(cur realm, t *testing.T) {
	packet, order := setupNativeRefundPacket(cross(cur), false, "ackrefund", "ucoreack", 11)
	ack := mustFailureAck()

	core.PacketAcknowledgement(cross(cur), core.NewMsgPacketAcknowledgement(cross(cur), []core.Packet{packet}, [][]byte{ack}, nil, core.Height(1)))

	assertNativeRefunded(cur, t, packet, order, int64(11))
}

func TestPacketTimeoutRefundsNativeFromProxy(cur realm, t *testing.T) {
	packet, order := setupNativeRefundPacket(cross(cur), true, "timerefund", "ucoretimeout", 13)

	core.PacketTimeout(cross(cur), core.NewMsgPacketTimeout(cross(cur), packet, nil, core.Height(1)))

	assertNativeRefunded(cur, t, packet, order, int64(13))
}

func setupNativeRefundPacket(cur realm, expired bool, senderName string, denom string, amount int64) (core.Packet, z.TokenOrderV2) {
	resetTokenOrderTest(cur)
	zkgm.UpdateImpl(cross(cur), zkgm.NewUpdateRequest(cross(cur), nil, []string{
		"gno.land/r/onbloc/unionibc/v1/core",
		"gno.land/r/onbloc/unionibc/v1/apps/zkgm/v0/impl",
		"gno.land/r/onbloc/unionibc/v1/apps/zkgm/testing/e2e",
	}))
	ensureZkgmAppRegistered(cross(cur))
	var pair e2e.ChannelPair
	if expired {
		pair = openTimeoutChannelPair(cross(cur))
	} else {
		e2e.RegisterMockLightClient(cross(cur))
		pair = e2e.OpenE2EChannelPair(cross(cur))
	}

	sender := testAddress(senderName)
	order := z.TokenOrderV2{
		Sender:      []byte(sender),
		Receiver:    []byte(testAddress("receiver")),
		BaseToken:   []byte(denom),
		BaseAmount:  u256.NewUint(uint64(amount)),
		QuoteToken:  []byte("quote-" + denom),
		QuoteAmount: u256.NewUint(uint64(amount)),
		Kind:        z.TOKEN_ORDER_KIND_INITIALIZE,
	}
	packet := core.NewPacket(
		cross(cur),
		pair.Source,
		pair.Destination,
		e2e.MustPacketData(cross(cur), e2e.MustTokenOrderInstruction(cross(cur), order)),
		0,
		core.Timestamp(1),
	)

	testing.IssueCoins(zkgm.ProxyAddress(), chain.NewCoins(chain.NewCoin(denom, amount)))
	zkgm.SetChannelBalanceV2(cross(cur), ChannelBalanceKeyV2(packet.SourceChannelId, u256.Zero(), order.BaseToken, order.QuoteToken), u256.NewUint(uint64(amount)))
	e2e.BatchSend(cross(cur), packet)

	return packet, order
}

func ensureZkgmAppRegistered(cur realm) {
	if !core.HasApp([]byte(zkgm.ProxyPkgPath())) {
		zkgm.RegisterCoreApp(cross(cur))
	}
}

func openTimeoutChannelPair(cur realm) e2e.ChannelPair {
	ensureZkgmAppRegistered(cross(cur))
	if !core.HasClient(timeoutMockClientType) {
		core.RegisterClient(cross(cur), timeoutMockClientType, &timeoutMockLightClient{})
	}
	clientId := core.CreateClient(cross(cur), core.NewMsgCreateClient(cross(cur), timeoutMockClientType, nil, nil))
	connectionId := core.ConnectionOpenInit(cross(cur), core.NewMsgConnectionOpenInit(cross(cur), clientId, core.ClientId(99)))
	core.ConnectionOpenAck(cross(cur), core.NewMsgConnectionOpenAck(cross(cur), connectionId, core.ConnectionId(77), nil, core.Height(1)))

	portId := []byte(zkgm.ProxyPkgPath())
	source := core.ChannelOpenInit(cross(cur), core.NewMsgChannelOpenInit(cross(cur), portId, portId, connectionId, zkgm.Version))
	destination := core.ChannelOpenInit(cross(cur), core.NewMsgChannelOpenInit(cross(cur), portId, portId, connectionId, zkgm.Version))
	core.ChannelOpenAck(cross(cur), core.NewMsgChannelOpenAck(cross(cur), source, zkgm.Version, destination, nil, core.Height(1)))
	core.ChannelOpenAck(cross(cur), core.NewMsgChannelOpenAck(cross(cur), destination, zkgm.Version, source, nil, core.Height(1)))
	return e2e.NewChannelPair(cross(cur), clientId, connectionId, source, destination)
}

func mustFailureAck() []byte {
	ack, err := z.EncodeAck(z.Ack{Tag: tagAckFailure, InnerAck: []byte("failure")})
	if err != nil {
		panic(err)
	}
	return ack
}

func assertNativeRefunded(cur realm, t *testing.T, packet core.Packet, order z.TokenOrderV2, amount int64) {
	t.Helper()

	denom := string(order.BaseToken)
	recipient := address(order.Sender)
	key := ChannelBalanceKeyV2(packet.SourceChannelId, u256.Zero(), order.BaseToken, order.QuoteToken)

	bk := banker.NewReadonlyBanker()
	uassert.Equal(t, false, core.HasPacketCommitment(cross(cur), packet))
	uassert.Equal(t, amount, bk.GetCoins(recipient).AmountOf(denom))
	uassert.Equal(t, int64(0), bk.GetCoins(zkgm.ProxyAddress()).AmountOf(denom))

	finalBalance := zkgm.GetChannelBalanceV2(key)
	uassert.True(t, finalBalance == nil || finalBalance.IsZero())
}
