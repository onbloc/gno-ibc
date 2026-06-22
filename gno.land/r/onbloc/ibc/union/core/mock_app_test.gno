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
	zeroTime  bool

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
	if m.zeroTime {
		return 0, nil
	}
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
	initCalled           bool
	openTryChannels      []types.ChannelId
	openTryStates        []types.ChannelState
	openAckChannels      []types.ChannelId
	openAckStates        []types.ChannelState
	openConfirmChannels  []types.ChannelId
	openConfirmStates    []types.ChannelState
	closedChannels       []types.ChannelId
	closeInitStates      []types.ChannelState
	closeConfirmStates   []types.ChannelState
	closeInitRelayers    []address
	closeConfirmRelayers []address
	recvPackets          []types.Packet
	recvRelayers         []address
	intentPackets        []types.Packet
	intentMakers         []address
	intentMsgs           [][]byte
	ackPackets           []types.Packet
	timeoutPackets       []types.Packet
	timeoutRelayers      []address
	recvResult           types.RecvPacketResult
	intentResult         types.RecvPacketResult
}

func (a *mockApp) OnChannelOpenInit(_ realm, _ types.ConnectionId, _ types.ChannelId, _ string, _ address) {
	a.initCalled = true
}

func (a *mockApp) OnChannelOpenTry(_ realm, _ types.ConnectionId, channelId types.ChannelId, _, _ string, _ address) {
	a.openTryChannels = append(a.openTryChannels, channelId)
	a.openTryStates = append(a.openTryStates, store.getChannel(channelId).State)
}

func (a *mockApp) OnChannelOpenAck(_ realm, channelId types.ChannelId, _ types.ChannelId, _ string, _ address) {
	a.openAckChannels = append(a.openAckChannels, channelId)
	a.openAckStates = append(a.openAckStates, store.getChannel(channelId).State)
}

func (a *mockApp) OnChannelOpenConfirm(_ realm, channelId types.ChannelId, _ address) {
	a.openConfirmChannels = append(a.openConfirmChannels, channelId)
	a.openConfirmStates = append(a.openConfirmStates, store.getChannel(channelId).State)
}

func (a *mockApp) OnChannelCloseInit(_ realm, ch types.ChannelId, relayer address) {
	a.closedChannels = append(a.closedChannels, ch)
	a.closeInitStates = append(a.closeInitStates, store.getChannel(ch).State)
	a.closeInitRelayers = append(a.closeInitRelayers, relayer)
}

func (a *mockApp) OnChannelCloseConfirm(_ realm, ch types.ChannelId, relayer address) {
	a.closedChannels = append(a.closedChannels, ch)
	a.closeConfirmStates = append(a.closeConfirmStates, store.getChannel(ch).State)
	a.closeConfirmRelayers = append(a.closeConfirmRelayers, relayer)
}

func (a *mockApp) OnRecvPacket(_ realm, p types.Packet, relayer address, _ []byte) types.RecvPacketResult {
	a.recvPackets = append(a.recvPackets, p)
	a.recvRelayers = append(a.recvRelayers, relayer)
	if a.recvResult.Status != types.PacketStatusUnknown {
		return a.recvResult
	}
	return NewRecvPacketResult(types.PacketStatusSuccess, []byte{0x01})
}

func (a *mockApp) OnIntentRecvPacket(_ realm, p types.Packet, maker address, msg []byte) types.RecvPacketResult {
	a.intentPackets = append(a.intentPackets, p)
	a.intentMakers = append(a.intentMakers, maker)
	a.intentMsgs = append(a.intentMsgs, msg)
	if a.intentResult.Status != types.PacketStatusUnknown {
		return a.intentResult
	}
	return NewRecvPacketResult(types.PacketStatusSuccess, []byte{0x02})
}

func (a *mockApp) OnAcknowledgementPacket(_ realm, p types.Packet, _ []byte, _ address) {
	a.ackPackets = append(a.ackPackets, p)
}

func (a *mockApp) OnTimeoutPacket(_ realm, p types.Packet, relayer address) {
	a.timeoutPackets = append(a.timeoutPackets, p)
	a.timeoutRelayers = append(a.timeoutRelayers, relayer)
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

func (*mockNonIntentApp) OnIntentRecvPacket(_ realm, _ types.Packet, _ address, _ []byte) types.RecvPacketResult {
	panic(ErrIntentNotSupported)
}

func (*mockNonIntentApp) OnAcknowledgementPacket(_ realm, _ types.Packet, _ []byte, _ address) {
}

func (*mockNonIntentApp) OnTimeoutPacket(_ realm, _ types.Packet, _ address) {
}
