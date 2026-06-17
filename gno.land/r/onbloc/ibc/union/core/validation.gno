package core

import "gno.land/p/onbloc/ibc/union/types"

func requireClientId(id types.ClientId) {
	if id == 0 {
		panic(ErrInvalidIdentifier)
	}
}

func requireConnectionId(id types.ConnectionId) {
	if id == 0 {
		panic(ErrInvalidIdentifier)
	}
}

func requireChannelId(id types.ChannelId) {
	if id == 0 {
		panic(ErrInvalidIdentifier)
	}
}

func validatePacket(packet types.Packet) {
	if packet.SourceChannelId == 0 || packet.DestinationChannelId == 0 {
		panic(ErrInvalidPacket)
	}
	if packet.TimeoutHeight != 0 {
		panic(ErrInvalidPacket)
	}
	if packet.TimeoutTimestamp == 0 {
		panic(ErrPacketTimeoutNotReached)
	}
}
