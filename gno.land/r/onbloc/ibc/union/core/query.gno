package core

import (
	"gno.land/p/onbloc/ibc/union/types"
)

func QueryClientState(clientId types.ClientId) string {
	bz, err := GetClientState(clientId)
	if err != nil {
		return ""
	}
	return hexString(bz)
}

func QueryConsensusState(clientId types.ClientId, height uint64) string {
	bz, err := GetConsensusState(clientId, types.NewHeight(height))
	if err != nil {
		return ""
	}
	return hexString(bz)
}

func QueryConnection(connectionId types.ConnectionId) string {
	conn, err := GetConnection(connectionId)
	if err != nil {
		return ""
	}
	bz, err := conn.EncodeABI()
	if err != nil {
		return ""
	}
	return hexString(bz)
}

func QueryChannel(channelId types.ChannelId) string {
	channel, err := GetChannel(channelId)
	if err != nil {
		return ""
	}
	bz, err := channel.EncodeABI()
	if err != nil {
		return ""
	}
	return hexString(bz)
}

func GetClientStatus(clientId types.ClientId) string {
	status, err := GetStatus(clientId)
	if err != nil {
		return "0"
	}
	switch status {
	case types.StatusActive:
		return "1"
	case types.StatusExpired:
		return "2"
	case types.StatusFrozen:
		return "3"
	default:
		return "0"
	}
}
