package impl

import (
	"chain"
	"chain/banker"
	"testing"

	types "gno.land/p/onbloc/ibc/union/types"

	u256 "gno.land/p/gnoswap/uint256"
	"gno.land/p/nt/uassert/v0"
	z "gno.land/p/onbloc/ibc/union/zkgm"
	zkgm "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm"
	e2e "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/testing/e2e"
	core "gno.land/r/onbloc/ibc/union/core"
)

const timeoutMockClientType = types.ClientType("gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/v1/timeout-mock")

type timeoutMockLightClient struct{}

func (m *timeoutMockLightClient) CreateClient(_ realm, clientId types.ClientId, clientStateBytes, consensusStateBytes []byte) string {
	return "timeout-mock-chain"
}

func (m *timeoutMockLightClient) UpdateClient(_ realm, clientId types.ClientId, clientMessage []byte) types.ConsensusStateUpdate {
	return types.ConsensusStateUpdate{
		Height:              types.NewHeight(1),
		ClientStateBytes:    clientMessage,
		ConsensusStateBytes: clientMessage,
	}
}

func (m *timeoutMockLightClient) VerifyMembership(clientId types.ClientId, height types.Height, proof []byte, key []byte, value []byte) {
}

func (m *timeoutMockLightClient) VerifyNonMembership(clientId types.ClientId, height types.Height, proof []byte, key []byte) {
}

func (m *timeoutMockLightClient) GetTimestamp(clientId types.ClientId, height types.Height) types.Timestamp {
	return types.Timestamp(2)
}

func (m *timeoutMockLightClient) GetLatestHeight(clientId types.ClientId) types.Height {
	return types.NewHeight(1)
}

func (m *timeoutMockLightClient) GetStatus(clientId types.ClientId) types.Status {
	return types.StatusActive
}

func TestPacketAcknowledgementFailureRefundsNativeFromProxy(cur realm, t *testing.T) {
	packet, order := setupNativeRefundPacket(cross(cur), false, "ackrefund", "ucoreack", 11)
	ack := mustFailureAck()

	core.PacketAcknowledgement(cross(cur), types.NewMsgPacketAcknowledgement([]types.Packet{packet}, [][]byte{ack}, nil, 1))

	assertNativeRefunded(cur, t, packet, order, int64(11))
}

func TestPacketTimeoutRefundsNativeFromProxy(cur realm, t *testing.T) {
	packet, order := setupNativeRefundPacket(cross(cur), true, "timerefund", "ucoretimeout", 13)

	core.PacketTimeout(cross(cur), types.NewMsgPacketTimeout(packet, nil, 1))

	assertNativeRefunded(cur, t, packet, order, int64(13))
}

func setupNativeRefundPacket(cur realm, expired bool, senderName string, denom string, amount int64) (types.Packet, z.TokenOrderV2) {
	resetTokenOrderTest(cur)
	zkgm.UpdateImpl(cross(cur), zkgm.NewUpdateRequest(cross(cur), nil, []string{
		"gno.land/r/onbloc/ibc/union/core",
		"gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/v1",
		"gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/testing/e2e",
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
		types.Timestamp(1),
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
	clientId := core.CreateClient(cross(cur), types.NewMsgCreateClient(timeoutMockClientType, nil, nil))
	connectionId := core.NextConnectionId()
	core.ConnectionOpenInit(cross(cur), types.NewMsgConnectionOpenInit(clientId, types.ClientId(99)))
	core.ConnectionOpenAck(cross(cur), types.NewMsgConnectionOpenAck(connectionId, types.ConnectionId(77), nil, 1))

	portId := []byte(zkgm.ProxyPkgPath())
	source := core.ChannelOpenInit(cross(cur), types.NewMsgChannelOpenInit(portId, portId, connectionId, zkgm.Version))
	destination := core.ChannelOpenInit(cross(cur), types.NewMsgChannelOpenInit(portId, portId, connectionId, zkgm.Version))
	core.ChannelOpenAck(cross(cur), types.NewMsgChannelOpenAck(source, zkgm.Version, destination, nil, 1))
	core.ChannelOpenAck(cross(cur), types.NewMsgChannelOpenAck(destination, zkgm.Version, source, nil, 1))
	return e2e.NewChannelPair(cross(cur), clientId, connectionId, source, destination)
}

func mustFailureAck() []byte {
	ack, err := z.EncodeAck(z.Ack{Tag: tagAckFailure(), InnerAck: []byte("failure")})
	if err != nil {
		panic(err)
	}
	return ack
}

func assertNativeRefunded(cur realm, t *testing.T, packet types.Packet, order z.TokenOrderV2, amount int64) {
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
