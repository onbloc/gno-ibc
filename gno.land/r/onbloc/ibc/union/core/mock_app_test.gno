package core

import "gno.land/p/onbloc/ibc/union/types"

type mockClient struct {
	chainId                string
	height                 types.Height
	status                 types.Status
	timestamp              types.Timestamp
	membershipClientIds    []types.ClientId
	membershipHeights      []types.Height
	membershipProofs       [][]byte
	membershipKeys         [][]byte
	membershipValues       [][]byte
	nonMembershipClientIds []types.ClientId
	nonMembershipHeights   []types.Height
	nonMembershipProofs    [][]byte
	nonMembershipKeys      [][]byte
	createClientIds        []types.ClientId
	createClientStates     [][]byte
	createConsensusStates  [][]byte
}

func (m *mockClient) CreateClient(_ realm, clientId types.ClientId, clientStateBytes, consensusStateBytes []byte) string {
	m.createClientIds = append(m.createClientIds, clientId)
	m.createClientStates = append(m.createClientStates, clientStateBytes)
	m.createConsensusStates = append(m.createConsensusStates, consensusStateBytes)
	return m.chainId
}
func (m *mockClient) UpdateClient(_ realm, _ types.ClientId, _ []byte) types.ConsensusStateUpdate {
	m.height = m.height.Increment()
	return types.ConsensusStateUpdate{
		Height:              m.height,
		ClientStateBytes:    []byte("cs"),
		ConsensusStateBytes: []byte("cons"),
	}
}

func (m *mockClient) VerifyMembership(clientId types.ClientId, height types.Height, proof []byte, key []byte, value []byte) {
	m.membershipClientIds = append(m.membershipClientIds, clientId)
	m.membershipHeights = append(m.membershipHeights, height)
	m.membershipProofs = append(m.membershipProofs, proof)
	m.membershipKeys = append(m.membershipKeys, key)
	m.membershipValues = append(m.membershipValues, value)
}

func (m *mockClient) VerifyNonMembership(clientId types.ClientId, height types.Height, proof []byte, key []byte) {
	m.nonMembershipClientIds = append(m.nonMembershipClientIds, clientId)
	m.nonMembershipHeights = append(m.nonMembershipHeights, height)
	m.nonMembershipProofs = append(m.nonMembershipProofs, proof)
	m.nonMembershipKeys = append(m.nonMembershipKeys, key)
}

func (m *mockClient) GetTimestamp(_ types.ClientId, _ types.Height) types.Timestamp {
	if m.timestamp != 0 {
		return m.timestamp
	}
	return types.Timestamp(1e9)
}
func (m *mockClient) GetStatus(_ types.ClientId) types.Status { return m.status }

type mockForceClient struct {
	mockClient
	forceHeight types.Height
}

func (m *mockForceClient) ForceUpdateClient(cur realm, _ types.ClientId, csBytes, consBytes []byte) types.ConsensusStateUpdate {
	m.forceHeight = m.forceHeight.Increment()
	return NewConsensusStateUpdate(cross(cur), m.forceHeight, consBytes, csBytes)
}

type mockApp struct {
	initCalled     bool
	closedChannels []types.ChannelId
	recvPackets    []types.Packet
	intentPackets  []types.Packet
	intentMsgs     [][]byte
	ackPackets     []types.Packet
	timeoutPackets []types.Packet
	recvResult     types.RecvPacketResult
	intentResult   types.RecvPacketResult
}

func (a *mockApp) OnChannelOpenInit(_ realm, _ types.ConnectionId, _ types.ChannelId, _ string, _ address) {
	a.initCalled = true
}

func (a *mockApp) OnChannelOpenTry(_ realm, _ types.ConnectionId, _ types.ChannelId, _, _ string, _ address) {
}

func (a *mockApp) OnChannelOpenAck(_ realm, _ types.ChannelId, _ types.ChannelId, _ string, _ address) {
}
func (a *mockApp) OnChannelOpenConfirm(_ realm, _ types.ChannelId, _ address) {}
func (a *mockApp) OnChannelCloseInit(_ realm, ch types.ChannelId, _ address) {
	a.closedChannels = append(a.closedChannels, ch)
}

func (a *mockApp) OnChannelCloseConfirm(_ realm, ch types.ChannelId, _ address) {
	a.closedChannels = append(a.closedChannels, ch)
}

func (a *mockApp) OnRecvPacket(cur realm, p types.Packet, _ address, _ []byte) types.RecvPacketResult {
	a.recvPackets = append(a.recvPackets, p)
	if a.recvResult.Status != types.PacketStatusUnknown {
		return a.recvResult
	}
	return NewRecvPacketResult(cur, types.PacketStatusSuccess, []byte{0x01})
}

func (a *mockApp) OnIntentRecvPacket(cur realm, p types.Packet, _ address, msg []byte) types.RecvPacketResult {
	a.intentPackets = append(a.intentPackets, p)
	a.intentMsgs = append(a.intentMsgs, msg)
	if a.intentResult.Status != types.PacketStatusUnknown {
		return a.intentResult
	}
	return NewRecvPacketResult(cur, types.PacketStatusSuccess, []byte{0x02})
}

func (a *mockApp) OnAcknowledgementPacket(_ realm, p types.Packet, _ []byte, _ address) {
	a.ackPackets = append(a.ackPackets, p)
}

func (a *mockApp) OnTimeoutPacket(_ realm, p types.Packet, _ address) {
	a.timeoutPackets = append(a.timeoutPackets, p)
}

type mockNonIntentApp struct{}

func (*mockNonIntentApp) OnChannelOpenInit(_ realm, _ types.ConnectionId, _ types.ChannelId, _ string, _ address) {
}

func (*mockNonIntentApp) OnChannelOpenTry(_ realm, _ types.ConnectionId, _ types.ChannelId, _, _ string, _ address) {
}

func (*mockNonIntentApp) OnChannelOpenAck(_ realm, _ types.ChannelId, _ types.ChannelId, _ string, _ address) {
}
func (*mockNonIntentApp) OnChannelOpenConfirm(_ realm, _ types.ChannelId, _ address)  {}
func (*mockNonIntentApp) OnChannelCloseInit(_ realm, _ types.ChannelId, _ address)    {}
func (*mockNonIntentApp) OnChannelCloseConfirm(_ realm, _ types.ChannelId, _ address) {}

func (*mockNonIntentApp) OnRecvPacket(cur realm, _ types.Packet, _ address, _ []byte) types.RecvPacketResult {
	return NewRecvPacketResult(cur, types.PacketStatusSuccess, []byte{0x01})
}

func (*mockNonIntentApp) OnAcknowledgementPacket(_ realm, _ types.Packet, _ []byte, _ address) {
}

func (*mockNonIntentApp) OnTimeoutPacket(_ realm, _ types.Packet, _ address) {
}
