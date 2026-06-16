package core

// Constructors for domain types are crossing functions (they take `cur realm`),
// which gno requires to live in a realm package. The types themselves are
// defined in the pure package gno.land/p/onbloc/ibc/union/types and re-exported
// via aliases.gno. Bodies do not touch realm state; the realm parameter only
// marks the cross-realm call boundary callers already use.

import "gno.land/p/onbloc/ibc/union/types"

// NewPacket builds a Union packet. Per the ibc-union-spec the timeout height is
// always zero (types.MustBeZero); only the timeout timestamp is meaningful.
func NewPacket(cur realm, sourceChannelId, destinationChannelId types.ChannelId, data []byte, timeoutTimestamp types.Timestamp) types.Packet {
	return types.Packet{SourceChannelId: sourceChannelId, DestinationChannelId: destinationChannelId, Data: data, TimeoutHeight: 0, TimeoutTimestamp: timeoutTimestamp}
}

func NewRecvPacketResult(cur realm, status types.PacketStatus, acknowledgement []byte) types.RecvPacketResult {
	return types.RecvPacketResult{Status: status, Acknowledgement: acknowledgement}
}

func NewConnection(cur realm, state types.ConnectionState, clientId, counterpartyClientId types.ClientId, counterpartyConnectionId types.ConnectionId) types.Connection {
	return types.Connection{State: state, ClientId: clientId, CounterpartyClientId: counterpartyClientId, CounterpartyConnectionId: counterpartyConnectionId}
}

func NewConsensusStateUpdate(cur realm, height types.Height, consensusStateBytes, clientStateBytes []byte) types.ConsensusStateUpdate {
	return types.ConsensusStateUpdate{Height: height, ConsensusStateBytes: consensusStateBytes, ClientStateBytes: clientStateBytes}
}
