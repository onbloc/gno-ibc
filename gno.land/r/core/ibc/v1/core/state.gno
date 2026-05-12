package core

import "errors"

var (
	ErrClientTypeAlreadyRegistered   = errors.New("client type already registered")
	ErrClientTypeNotFound            = errors.New("client type not found")
	ErrClientNotFound                = errors.New("client not found")
	ErrConnectionNotFound            = errors.New("connection not found")
	ErrInvalidConnectionState        = errors.New("invalid connection state")
	ErrChannelNotFound               = errors.New("channel not found")
	ErrInvalidChannelState           = errors.New("invalid channel state")
	ErrPortNotFound                  = errors.New("port not found")
	ErrSyncAckEmpty                  = errors.New("sync ack cannot be empty")
	ErrUnknownPacketStatus           = errors.New("unknown packet status")
	ErrNoPendingAsyncAck             = errors.New("no pending async ack")
	ErrUnauthorizedAckWriter         = errors.New("caller not authorized to write ack")
	ErrAcknowledgementAlreadyWritten = errors.New("acknowledgement already written")
	ErrPendingAsyncAckExists         = errors.New("pending async ack already exists")
	ErrAcknowledgementEmpty          = errors.New("acknowledgement cannot be empty")
)

type State struct {
	nextClientId     ClientId
	nextConnectionId ConnectionId
	nextChannelId    ChannelId

	ports         map[address]IApp
	channelOwners map[ChannelId]address

	clientRegistry map[ClientType]ILightClient
	clientTypes    map[ClientId]ClientType

	connections map[ConnectionId]Connection
	channels    map[ChannelId]Channel

	nextSequenceSends map[ChannelId]Sequence
	packetCommitments map[H256]bool
	packetReceipts    map[H256]bool
	packetAcks        map[H256]bool
	packetAckHashes   map[H256]H256
	// Entries are not auto-expired; on child timeout, ZKGM Forward writes
	// a universal-error ACK.
	pendingAsyncAcks map[asyncAckKey]pendingAsyncAck
}

type asyncAckKey struct {
	ChannelId ChannelId
	Sequence  Sequence
}

type pendingAsyncAck struct {
	Packet         Packet
	AuthorizedPort address
}

func newState() State {
	return State{
		nextClientId:      ClientId(1),
		nextConnectionId:  ConnectionId(1),
		nextChannelId:     ChannelId(1),
		clientRegistry:    make(map[ClientType]ILightClient),
		clientTypes:       make(map[ClientId]ClientType),
		connections:       make(map[ConnectionId]Connection),
		channels:          make(map[ChannelId]Channel),
		ports:             make(map[address]IApp),
		channelOwners:     make(map[ChannelId]address),
		nextSequenceSends: make(map[ChannelId]Sequence),
		packetCommitments: make(map[H256]bool),
		packetReceipts:    make(map[H256]bool),
		packetAcks:        make(map[H256]bool),
		packetAckHashes:   make(map[H256]H256),
		pendingAsyncAcks:  make(map[asyncAckKey]pendingAsyncAck),
	}
}

func (s *State) generateClientId() ClientId {
	id := s.nextClientId
	s.nextClientId++
	return id
}

func (s *State) generateConnectionId() ConnectionId {
	id := s.nextConnectionId
	s.nextConnectionId++
	return id
}

func (s *State) generateChannelId() ChannelId {
	id := s.nextChannelId
	s.nextChannelId++
	return id
}

func (s *State) generatePacketSequence(channelId ChannelId) Sequence {
	sequence := s.nextSequenceSends[channelId]
	s.nextSequenceSends[channelId] = sequence + 1
	return sequence
}

func (s *State) registerClient(clientType ClientType, impl ILightClient) {
	if _, ok := s.clientRegistry[clientType]; ok {
		panic(ErrClientTypeAlreadyRegistered)
	}
	s.clientRegistry[clientType] = impl
}

func (s *State) getClient(clientId ClientId) ILightClient {
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

func (s *State) getAppByPortId(portId address) IApp {
	app, ok := s.ports[portId]
	if !ok {
		panic(ErrPortNotFound)
	}
	return app
}

func (s *State) getChannelOwner(channelId ChannelId) address {
	portId, ok := s.channelOwners[channelId]
	if !ok {
		panic(ErrPortNotFound)
	}
	return portId
}

func (s *State) getConnection(connectionId ConnectionId) Connection {
	connection, ok := s.connections[connectionId]
	if !ok {
		panic(ErrConnectionNotFound)
	}
	return connection
}

func (s *State) getChannel(channelId ChannelId) Channel {
	channel, ok := s.channels[channelId]
	if !ok {
		panic(ErrChannelNotFound)
	}
	return channel
}

func (s *State) saveClientState(clientId ClientId, clientStateBytes []byte) {
	commit(ClientStatePath(clientId), keccak(clientStateBytes))
}

func (s *State) saveConsensusState(clientId ClientId, height Height, consensusStateBytes []byte) {
	commit(ConsensusStatePath(clientId, height), keccak(consensusStateBytes))
}

func (s *State) saveConnection(connectionId ConnectionId, connection Connection) {
	s.connections[connectionId] = connection
	commit(ConnectionPath(connectionId), keccak(connection.EthAbiEncode()))
}

func (s *State) saveChannel(channelId ChannelId, channel Channel) {
	s.channels[channelId] = channel
	commit(ChannelPath(channelId), keccak(channel.EthAbiEncode()))
}

func (s *State) commitPacket(packet Packet) {
	key := PacketCommitmentPath(packet)
	s.packetCommitments[key] = true
	commit(key, COMMITMENT_MAGIC)
}

func (s *State) deletePacketCommitment(packet Packet) {
	var zero H256
	key := PacketCommitmentPath(packet)
	delete(s.packetCommitments, key)
	commit(key, zero)
}

func (s *State) hasPacketCommitment(packet Packet) bool {
	return s.packetCommitments[PacketCommitmentPath(packet)]
}

func (s *State) commitAcknowledgement(packet Packet, ack []byte) {
	key := PacketAcknowledgementPath(packet)
	ackHash := keccak(ack)
	s.packetAcks[key] = true
	s.packetAckHashes[key] = ackHash
	commit(key, ackHash)
}

func (s *State) hasAcknowledgement(packet Packet) bool {
	return s.packetAcks[PacketAcknowledgementPath(packet)]
}

func (s *State) acknowledgementHash(packet Packet) H256 {
	return s.packetAckHashes[PacketAcknowledgementPath(packet)]
}

func (s *State) setPacketReceipt(packet Packet) {
	key := PacketReceiptPath(packet)
	s.packetReceipts[key] = true
	commit(key, COMMITMENT_MAGIC_ACK)
}

func (s *State) hasPacketReceipt(packet Packet) bool {
	return s.packetReceipts[PacketReceiptPath(packet)]
}

func (s *State) deletePacketReceipt(packet Packet) {
	var zero H256
	key := PacketReceiptPath(packet)
	delete(s.packetReceipts, key)
	commit(key, zero)
}

func (s *State) savePendingAsyncAck(packet Packet, authorizedPort address) {
	key := asyncAckKey{ChannelId: packet.DestinationChannelId, Sequence: packet.Sequence}
	if _, exists := s.pendingAsyncAcks[key]; exists {
		panic(ErrPendingAsyncAckExists)
	}
	if s.hasAcknowledgement(packet) {
		panic(ErrAcknowledgementAlreadyWritten)
	}
	s.pendingAsyncAcks[key] = pendingAsyncAck{
		Packet:         packet,
		AuthorizedPort: authorizedPort,
	}
}

func (s *State) getPendingAsyncAck(channelId ChannelId, sequence Sequence) (pendingAsyncAck, bool) {
	v, ok := s.pendingAsyncAcks[asyncAckKey{ChannelId: channelId, Sequence: sequence}]
	return v, ok
}

func (s *State) deletePendingAsyncAck(channelId ChannelId, sequence Sequence) {
	delete(s.pendingAsyncAcks, asyncAckKey{ChannelId: channelId, Sequence: sequence})
}

func (s *State) hasPendingAsyncAck(channelId ChannelId, sequence Sequence) bool {
	_, ok := s.pendingAsyncAcks[asyncAckKey{ChannelId: channelId, Sequence: sequence}]
	return ok
}
