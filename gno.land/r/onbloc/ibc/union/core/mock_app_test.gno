package core

import (
	"errors"

	"gno.land/p/onbloc/ibc/union/lightclient"
	"gno.land/p/onbloc/ibc/union/types"
)

// mockClient is a lightclient.Interface. Tests build a mockClient and hand it
// to core.CreateClient directly, then inspect the same object core stores and
// calls.
type mockClient struct {
	chainId   string
	height    types.Height
	status    types.Status
	timestamp types.Timestamp

	// recorded calls
	membershipHeights    []types.Height
	membershipProofs     [][]byte
	membershipKeys       [][]byte
	membershipValues     [][]byte
	nonMembershipHeights []types.Height
	nonMembershipProofs  [][]byte
	nonMembershipKeys    [][]byte
	headerMessages       [][]byte
}

func (m *mockClient) VerifyMembership(height uint64, key, proof, value []byte) error {
	m.membershipHeights = append(m.membershipHeights, types.NewHeight(height))
	m.membershipKeys = append(m.membershipKeys, key)
	m.membershipProofs = append(m.membershipProofs, proof)
	m.membershipValues = append(m.membershipValues, value)
	return nil
}

func (m *mockClient) VerifyNonMembership(height uint64, key, proof []byte) error {
	m.nonMembershipHeights = append(m.nonMembershipHeights, types.NewHeight(height))
	m.nonMembershipKeys = append(m.nonMembershipKeys, key)
	m.nonMembershipProofs = append(m.nonMembershipProofs, proof)
	return nil
}

func (m *mockClient) GetTimestamp() types.Timestamp {
	if m.timestamp != 0 {
		return m.timestamp
	}
	return types.Timestamp(1e9)
}

func (m *mockClient) GetTimestampAtHeight(uint64) (types.Timestamp, error) {
	return m.GetTimestamp(), nil
}

func (m *mockClient) GetLatestHeight() uint64        { return m.height.RevisionHeight }
func (m *mockClient) GetCounterpartyChainID() string { return m.chainId }

func (m *mockClient) Status() lightclient.Status {
	switch m.status {
	case types.StatusActive:
		return lightclient.Active
	case types.StatusExpired:
		return lightclient.Expired
	case types.StatusFrozen:
		return lightclient.Frozen
	default:
		return lightclient.Unknown
	}
}

func (m *mockClient) VerifyHeader(_ address, header []byte, _ address) (types.StateUpdate, error) {
	m.headerMessages = append(m.headerMessages, header)
	m.height = m.height.Increment()
	return types.StateUpdate{
		Height:              m.height.RevisionHeight,
		ClientStateBytes:    []byte("cs"),
		ConsensusStateBytes: []byte("cons"),
	}, nil
}

func (m *mockClient) VerifyCreation(_ address, _ address) (types.ClientCreationResult, error) {
	return types.ClientCreationResult{}, nil
}

func (m *mockClient) Misbehaviour(_ address, _ []byte, _ address) (types.ClientState, error) {
	return nil, errors.New("mock: misbehaviour unsupported")
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

func (a *mockApp) OnRecvPacket(_ realm, p types.Packet, _ address, _ []byte) types.RecvPacketResult {
	a.recvPackets = append(a.recvPackets, p)
	if a.recvResult.Status != types.PacketStatusUnknown {
		return a.recvResult
	}
	return NewRecvPacketResult(types.PacketStatusSuccess, []byte{0x01})
}

func (a *mockApp) OnIntentRecvPacket(_ realm, p types.Packet, _ address, msg []byte) types.RecvPacketResult {
	a.intentPackets = append(a.intentPackets, p)
	a.intentMsgs = append(a.intentMsgs, msg)
	if a.intentResult.Status != types.PacketStatusUnknown {
		return a.intentResult
	}
	return NewRecvPacketResult(types.PacketStatusSuccess, []byte{0x02})
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

func (*mockNonIntentApp) OnRecvPacket(_ realm, _ types.Packet, _ address, _ []byte) types.RecvPacketResult {
	return NewRecvPacketResult(types.PacketStatusSuccess, []byte{0x01})
}

func (*mockNonIntentApp) OnAcknowledgementPacket(_ realm, _ types.Packet, _ []byte, _ address) {
}

func (*mockNonIntentApp) OnTimeoutPacket(_ realm, _ types.Packet, _ address) {
}
