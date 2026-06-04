package core

type mockClient struct {
	chainId                string
	height                 Height
	status                 Status
	timestamp              Timestamp
	membershipClientIds    []ClientId
	membershipHeights      []Height
	membershipProofs       [][]byte
	membershipKeys         [][]byte
	membershipValues       [][]byte
	nonMembershipClientIds []ClientId
	nonMembershipHeights   []Height
	nonMembershipProofs    [][]byte
	nonMembershipKeys      [][]byte
}

func (m *mockClient) CreateClient(_ realm, _ ClientId, _, _ []byte) string { return m.chainId }
func (m *mockClient) UpdateClient(_ realm, _ ClientId, _ []byte) ConsensusStateUpdate {
	m.height++
	return ConsensusStateUpdate{
		Height:              m.height,
		ClientStateBytes:    []byte("cs"),
		ConsensusStateBytes: []byte("cons"),
	}
}

func (m *mockClient) VerifyMembership(clientId ClientId, height Height, proof []byte, key []byte, value []byte) {
	m.membershipClientIds = append(m.membershipClientIds, clientId)
	m.membershipHeights = append(m.membershipHeights, height)
	m.membershipProofs = append(m.membershipProofs, proof)
	m.membershipKeys = append(m.membershipKeys, key)
	m.membershipValues = append(m.membershipValues, value)
}

func (m *mockClient) VerifyNonMembership(clientId ClientId, height Height, proof []byte, key []byte) {
	m.nonMembershipClientIds = append(m.nonMembershipClientIds, clientId)
	m.nonMembershipHeights = append(m.nonMembershipHeights, height)
	m.nonMembershipProofs = append(m.nonMembershipProofs, proof)
	m.nonMembershipKeys = append(m.nonMembershipKeys, key)
}

func (m *mockClient) GetTimestamp(_ ClientId, _ Height) Timestamp {
	if m.timestamp != 0 {
		return m.timestamp
	}
	return Timestamp(1e9)
}
func (m *mockClient) GetLatestHeight(_ ClientId) Height { return m.height }
func (m *mockClient) GetStatus(_ ClientId) Status       { return m.status }

type mockForceClient struct {
	mockClient
	forceHeight Height
}

func (m *mockForceClient) ForceUpdateClient(cur realm, _ ClientId, csBytes, consBytes []byte) ConsensusStateUpdate {
	m.forceHeight++
	return NewConsensusStateUpdate(cross(cur), m.forceHeight, consBytes, csBytes)
}

type mockApp struct {
	initCalled     bool
	closedChannels []ChannelId
	recvPackets    []Packet
	intentPackets  []Packet
	intentMsgs     [][]byte
	ackPackets     []Packet
	timeoutPackets []Packet
	recvResult     RecvPacketResult
	intentResult   RecvPacketResult
}

func (a *mockApp) OnChannelOpenInit(_ realm, _ ConnectionId, _ ChannelId, _ string, _ address) {
	a.initCalled = true
}

func (a *mockApp) OnChannelOpenTry(_ realm, _ ConnectionId, _ ChannelId, _, _ string, _ address) {
}

func (a *mockApp) OnChannelOpenAck(_ realm, _ ChannelId, _ ChannelId, _ string, _ address) {
}
func (a *mockApp) OnChannelOpenConfirm(_ realm, _ ChannelId, _ address) {}
func (a *mockApp) OnChannelCloseInit(_ realm, ch ChannelId, _ address) {
	a.closedChannels = append(a.closedChannels, ch)
}

func (a *mockApp) OnChannelCloseConfirm(_ realm, ch ChannelId, _ address) {
	a.closedChannels = append(a.closedChannels, ch)
}

func (a *mockApp) OnRecvPacket(cur realm, p Packet, _ address, _ []byte) RecvPacketResult {
	a.recvPackets = append(a.recvPackets, p)
	if a.recvResult.Status != PacketStatusUnknown {
		return a.recvResult
	}
	return NewRecvPacketResult(cur, PacketStatusSuccess, []byte{0x01})
}

func (a *mockApp) OnIntentRecvPacket(cur realm, p Packet, _ address, msg []byte) RecvPacketResult {
	a.intentPackets = append(a.intentPackets, p)
	a.intentMsgs = append(a.intentMsgs, msg)
	if a.intentResult.Status != PacketStatusUnknown {
		return a.intentResult
	}
	return NewRecvPacketResult(cur, PacketStatusSuccess, []byte{0x02})
}

func (a *mockApp) OnAcknowledgementPacket(_ realm, p Packet, _ []byte, _ address) {
	a.ackPackets = append(a.ackPackets, p)
}

func (a *mockApp) OnTimeoutPacket(_ realm, p Packet, _ address) {
	a.timeoutPackets = append(a.timeoutPackets, p)
}

type mockNonIntentApp struct{}

func (*mockNonIntentApp) OnChannelOpenInit(_ realm, _ ConnectionId, _ ChannelId, _ string, _ address) {
}

func (*mockNonIntentApp) OnChannelOpenTry(_ realm, _ ConnectionId, _ ChannelId, _, _ string, _ address) {
}

func (*mockNonIntentApp) OnChannelOpenAck(_ realm, _ ChannelId, _ ChannelId, _ string, _ address) {
}
func (*mockNonIntentApp) OnChannelOpenConfirm(_ realm, _ ChannelId, _ address)  {}
func (*mockNonIntentApp) OnChannelCloseInit(_ realm, _ ChannelId, _ address)    {}
func (*mockNonIntentApp) OnChannelCloseConfirm(_ realm, _ ChannelId, _ address) {}

func (*mockNonIntentApp) OnRecvPacket(cur realm, _ Packet, _ address, _ []byte) RecvPacketResult {
	return NewRecvPacketResult(cur, PacketStatusSuccess, []byte{0x01})
}

func (*mockNonIntentApp) OnAcknowledgementPacket(_ realm, _ Packet, _ []byte, _ address) {
}

func (*mockNonIntentApp) OnTimeoutPacket(_ realm, _ Packet, _ address) {
}
