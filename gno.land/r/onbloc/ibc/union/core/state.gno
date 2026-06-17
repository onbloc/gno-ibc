package core

import (
	"errors"

	"gno.land/p/onbloc/ibc/union/app"
	"gno.land/p/onbloc/ibc/union/lightclient"
	"gno.land/p/onbloc/ibc/union/types"
)

var (
	ErrClientTypeAlreadyRegistered   = errors.New("client type already registered")
	ErrClientTypeNotFound            = errors.New("client type not found")
	ErrClientNotFound                = errors.New("client not found")
	ErrClientNotActive               = errors.New("client is not active")
	ErrConsensusStateNotFound        = errors.New("consensus state not found")
	ErrConnectionNotFound            = errors.New("connection not found")
	ErrInvalidConnectionState        = errors.New("invalid connection state")
	ErrChannelNotFound               = errors.New("channel not found")
	ErrInvalidChannelState           = errors.New("invalid channel state")
	ErrPortNotFound                  = errors.New("port not found")
	ErrSyncAckEmpty                  = errors.New("sync ack cannot be empty")
	ErrUnknownPacketStatus           = errors.New("unknown packet status")
	ErrUnauthorizedAckWriter         = errors.New("caller not authorized to write ack")
	ErrAcknowledgementAlreadyWritten = errors.New("acknowledgement already written")
	ErrAcknowledgementEmpty          = errors.New("acknowledgement cannot be empty")
	ErrAcknowledgementMismatch       = errors.New("acknowledgement commitment mismatch")
	ErrUnauthorizedPacketSender      = errors.New("caller not authorized to send packet")
	ErrPacketCommitmentExists        = errors.New("packet commitment already exists")
	ErrPacketReceiptNotFound         = errors.New("packet receipt not found")
	ErrNotEnoughPackets              = errors.New("not enough packets")
	ErrBatchSameChannelOnly          = errors.New("batch must use the same channel")
	ErrAcknowledgementCountMismatch  = errors.New("acknowledgement count mismatch")
	ErrPortAlreadyRegistered         = errors.New("port already registered")
	ErrBatchPacketsNotFound          = errors.New("batch packets not found")
	ErrBatchReceiptsNotFound         = errors.New("batch receipts not found")
	ErrPacketTimeoutExpired          = errors.New("packet timeout expired")
	ErrPacketTimeoutNotReached       = errors.New("packet timeout not reached")
	ErrIntentNotSupported            = errors.New("intent receive not supported")
)

type State struct {
	nextClientId     types.ClientId
	nextConnectionId types.ConnectionId
	nextChannelId    types.ChannelId

	ports         map[string]app.IApp
	channelOwners map[types.ChannelId]types.Bytes

	clientRegistry map[types.ClientType]lightclient.ILightClient
	clientTypes    map[types.ClientId]types.ClientType
	clientStates   map[types.ClientId][]byte

	consensusStates map[types.ClientId]map[types.Height][]byte

	connections map[types.ConnectionId]types.Connection
	channels    map[types.ChannelId]types.Channel

	batchPackets  map[types.H256]types.H256
	batchReceipts map[types.H256]types.H256
}

func newState() State {
	return State{
		nextClientId:     types.ClientId(1),
		nextConnectionId: types.ConnectionId(1),
		nextChannelId:    types.ChannelId(1),
		clientRegistry:   make(map[types.ClientType]lightclient.ILightClient),
		clientTypes:      make(map[types.ClientId]types.ClientType),
		clientStates:     make(map[types.ClientId][]byte),
		consensusStates:  make(map[types.ClientId]map[types.Height][]byte),
		connections:      make(map[types.ConnectionId]types.Connection),
		channels:         make(map[types.ChannelId]types.Channel),
		batchPackets:     make(map[types.H256]types.H256),
		batchReceipts:    make(map[types.H256]types.H256),
		ports:            make(map[string]app.IApp),
		channelOwners:    make(map[types.ChannelId]types.Bytes),
	}
}

func (s *State) generateClientId() types.ClientId {
	id := s.nextClientId
	s.nextClientId++
	return id
}

func (s *State) generateConnectionId() types.ConnectionId {
	id := s.nextConnectionId
	s.nextConnectionId++
	return id
}

func (s *State) generateChannelId() types.ChannelId {
	id := s.nextChannelId
	s.nextChannelId++
	return id
}

func (s *State) registerClient(clientType types.ClientType, impl lightclient.ILightClient) {
	if _, ok := s.clientRegistry[clientType]; ok {
		panic(ErrClientTypeAlreadyRegistered)
	}
	s.clientRegistry[clientType] = impl
}

func (s *State) getClient(clientId types.ClientId) lightclient.ILightClient {
	ty, ok := s.clientTypes[clientId]
	if !ok {
		panic(ErrClientNotFound)
	}
	impl, ok := s.clientRegistry[ty]
	if !ok {
		panic("invariant: clientTypes only maps to existing clientRegistry entries")
	}
	return impl
}

func portKey(portId types.Bytes) string {
	return string(portId)
}

func (s *State) getAppByPortId(portId types.Bytes) app.IApp {
	app, ok := s.ports[portKey(portId)]
	if !ok {
		panic(ErrPortNotFound)
	}
	return app
}

func (s *State) getChannelOwner(channelId types.ChannelId) types.Bytes {
	portId, ok := s.channelOwners[channelId]
	if !ok {
		panic(ErrPortNotFound)
	}
	return portId
}

func (s *State) getConnection(connectionId types.ConnectionId) types.Connection {
	connection, ok := s.connections[connectionId]
	if !ok {
		panic(ErrConnectionNotFound)
	}
	return connection
}

func (s *State) getChannel(channelId types.ChannelId) types.Channel {
	channel, ok := s.channels[channelId]
	if !ok {
		panic(ErrChannelNotFound)
	}
	return channel
}

func (s *State) saveClientState(clientId types.ClientId, clientStateBytes []byte) {
	s.clientStates[clientId] = cloneBytes(clientStateBytes)
	commit(types.ClientStatePath(clientId), keccak(clientStateBytes))
}

func (s *State) getClientState(clientId types.ClientId) []byte {
	state, ok := s.clientStates[clientId]
	if !ok {
		panic(ErrClientNotFound)
	}
	return cloneBytes(state)
}

func (s *State) saveConsensusState(clientId types.ClientId, height types.Height, consensusStateBytes []byte) {
	byHeight, ok := s.consensusStates[clientId]
	if !ok {
		byHeight = make(map[types.Height][]byte)
		s.consensusStates[clientId] = byHeight
	}
	byHeight[height] = cloneBytes(consensusStateBytes)
	commit(types.ConsensusStatePath(clientId, height), keccak(consensusStateBytes))
}

func (s *State) getConsensusState(clientId types.ClientId, height types.Height) []byte {
	byHeight, ok := s.consensusStates[clientId]
	if !ok {
		panic(ErrClientNotFound)
	}
	state, ok := byHeight[height]
	if !ok {
		panic(ErrConsensusStateNotFound)
	}
	return cloneBytes(state)
}

func (s *State) saveConnection(connectionId types.ConnectionId, connection types.Connection) {
	s.connections[connectionId] = connection
	commit(types.ConnectionPath(connectionId), connectionValue(connection))
}

func (s *State) saveChannel(channelId types.ChannelId, channel types.Channel) {
	s.channels[channelId] = channel
	commit(types.ChannelPath(channelId), channelValue(channel))
}

func (s *State) saveBatchPackets(batchHash types.H256, value types.H256) {
	path := types.BatchPacketsPath(batchHash)
	s.batchPackets[path] = value
	commit(path, value)
}

func (s *State) setBatchPackets(batchHash types.H256, value types.H256) {
	s.batchPackets[types.BatchPacketsPath(batchHash)] = value
}

func (s *State) getBatchPackets(batchHash types.H256) types.H256 {
	value, ok := s.batchPackets[types.BatchPacketsPath(batchHash)]
	if !ok {
		panic(ErrBatchPacketsNotFound)
	}
	return value
}

func (s *State) deleteBatchPackets(batchHash types.H256) {
	var zero types.H256
	path := types.BatchPacketsPath(batchHash)
	delete(s.batchPackets, path)
	commit(path, zero)
}

func (s *State) saveBatchReceipts(batchHash types.H256, value types.H256) {
	path := types.BatchReceiptsPath(batchHash)
	s.batchReceipts[path] = value
	commit(path, value)
}

func (s *State) getBatchReceipts(batchHash types.H256) types.H256 {
	value, ok := s.batchReceipts[types.BatchReceiptsPath(batchHash)]
	if !ok {
		panic(ErrBatchReceiptsNotFound)
	}
	return value
}

func (s *State) commitPacket(packet types.Packet) {
	s.saveBatchPackets(commitPacketHash(packet), types.COMMITMENT_MAGIC)
}

func (s *State) deletePacketCommitment(packet types.Packet) {
	var zero types.H256
	path := packetCommitmentPath(packet)
	delete(s.batchPackets, path)
	commit(path, zero)
}

func (s *State) hasPacketCommitment(packet types.Packet) bool {
	_, ok := s.batchPackets[packetCommitmentPath(packet)]
	return ok
}

func (s *State) commitAcknowledgement(packet types.Packet, ack []byte) {
	s.saveBatchReceipts(commitPacketHash(packet), types.CommitAcks([][]byte{ack}))
}

func (s *State) hasAcknowledgement(packet types.Packet) bool {
	value, ok := s.batchReceipts[packetAcknowledgementPath(packet)]
	return ok && value != types.COMMITMENT_MAGIC_ACK
}

func (s *State) acknowledgementHash(packet types.Packet) types.H256 {
	return s.batchReceipts[packetAcknowledgementPath(packet)]
}

func (s *State) setPacketReceipt(packet types.Packet) {
	s.saveBatchReceipts(commitPacketHash(packet), types.COMMITMENT_MAGIC_ACK)
}

func (s *State) hasPacketReceipt(packet types.Packet) bool {
	_, ok := s.batchReceipts[packetAcknowledgementPath(packet)]
	return ok
}

func (s *State) deletePacketReceipt(packet types.Packet) {
	var zero types.H256
	path := packetAcknowledgementPath(packet)
	delete(s.batchReceipts, path)
	commit(path, zero)
}
