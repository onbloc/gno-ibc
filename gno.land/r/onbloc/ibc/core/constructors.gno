package core

// Constructors for domain types are crossing functions (they take `cur realm`),
// which gno requires to live in a realm package. The types themselves are
// defined in the pure package gno.land/p/onbloc/ibc/types and re-exported via
// aliases.gno. Bodies do not touch realm state; the realm parameter only
// marks the cross-realm call boundary callers already use.

func NewPacket(cur realm, sourceChannelId, destinationChannelId ChannelId, data []byte, timeoutHeight Height, timeoutTimestamp Timestamp) Packet {
	return Packet{SourceChannelId: sourceChannelId, DestinationChannelId: destinationChannelId, Data: data, TimeoutHeight: timeoutHeight, TimeoutTimestamp: timeoutTimestamp}
}

func NewRecvPacketResult(cur realm, status PacketStatus, ack []byte) RecvPacketResult {
	return RecvPacketResult{Status: status, Ack: ack}
}

func NewConnection(cur realm, state ConnectionState, clientId, counterpartyClientId ClientId, counterpartyConnectionId ConnectionId) Connection {
	return Connection{State: state, ClientId: clientId, CounterpartyClientId: counterpartyClientId, CounterpartyConnectionId: counterpartyConnectionId}
}

func NewConsensusStateUpdate(cur realm, height Height, consensusStateBytes, clientStateBytes []byte) ConsensusStateUpdate {
	return ConsensusStateUpdate{Height: height, ConsensusStateBytes: consensusStateBytes, ClientStateBytes: clientStateBytes}
}
