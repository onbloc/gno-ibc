package core

// State holds all the state for the Union IBC core module.
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
}

func (s State) generateClientId() ClientId {
	id := s.nextClientId
	s.nextClientId += 1
	return id
}

func (s State) generateConnectionId() ConnectionId {
	id := s.nextConnectionId
	s.nextConnectionId += 1
	return id
}

func (s State) generateChannelId() ChannelId {
	id := s.nextChannelId
	s.nextChannelId += 1
	return id
}

func (s State) registerClient(clientType ClientType, impl ILightClient) {
	if impl, ok := s.clientRegistry[clientType]; ok {
		panic(ErrClientTypeAlreadyRegistered)
	} else {
		s.clientRegistry[clientType] = impl
	}
}

func (s State) getClient(clientId ClientId) ILightClient {
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

// REVIEW: What should the port ID be?
func (s State) getAppByPortId(portId address) IApp {
	app, ok := s.ports[portId]

	if !ok {
		panic(ErrPortNotFound)
	}

	return app
}

// REVIEW: What should the port ID be?
func (s State) getChannelOwner(channelId ChannelId) address {
	portId, ok := s.channelOwners[channelId]

	if !ok {
		panic(ErrPortNotFound)
	}

	return portId
}

func (s State) getConnection(connectionId ConnectionId) Connection {
	connection, ok := s.connections[connectionId]

	if !ok {
		panic(ErrConnectionNotFound)
	}

	return connection
}

func (s State) getChannel(channelId ChannelId) Channel {
	channel, ok := s.channels[channelId]

	if !ok {
		panic(ErrChannelNotFound)
	}

	return channel
}

func (s State) saveClientState(clientId ClientId, clientStateBytes []byte) {
	commit(ClientStatePath(clientId), keccak(clientStateBytes))
}

func (s State) saveConsensusState(clientId ClientId, height Height, consensusStateBytes []byte) {
	commit(ClientStatePath(clientId), keccak(consensusStateBytes))
}

func (s State) saveConnection(connectionId ConnectionId, connection Connection) {
	s.connections[connectionId] = connection
	commit(ConnectionPath(connectionId), keccak(connection.EthAbiEncode()))
}

func (s State) saveChannel(channelId ChannelId, channel Channel) {
	s.channels[channelId] = channel
	commit(ChannelPath(channelId), keccak(channel.EthAbiEncode()))
}
