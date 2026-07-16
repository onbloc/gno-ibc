package main

import (
	"gno.land/p/onbloc/ibc/union/types"
	zkgm "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm"
	core "gno.land/r/onbloc/ibc/union/core"
)

const (
	gnoClientId = types.ClientId(1)
	unionClientId = types.ClientId(4)
	gnoConnectionId = types.ConnectionId(5)
	unionConnectionId = types.ConnectionId(3)
	gnoChannelId = types.ChannelId(3)
	unionChannelId = types.ChannelId(2)
	portId = "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm"
)

func main(cur realm) {
	if core.QueryConnection(gnoConnectionId) == "" {
		for id := types.ConnectionId(1); id <= gnoConnectionId; id++ {
			if core.QueryConnection(id) == "" {
				core.ConnectionOpenInit(cross(cur), core.NewMsgConnectionOpenInit(gnoClientId, unionClientId))
			}
		}
		requireConnectionInit()
		core.ForceConnectionOpenAck(cross(cur), core.NewMsgConnectionOpenAck(gnoConnectionId, unionConnectionId, nil, 0))
	}
	requireConnection()

	if core.QueryChannel(gnoChannelId) == "" {
		for id := types.ChannelId(1); id <= gnoChannelId; id++ {
			if core.QueryChannel(id) == "" {
				core.ChannelOpenInit(cross(cur), core.NewMsgChannelOpenInit([]byte(portId), []byte(portId), gnoConnectionId, zkgm.Version, cur.Previous().Address().String()))
			}
		}
		requireChannelInit()
		core.ForceChannelOpenAck(cross(cur), core.NewMsgChannelOpenAck(gnoChannelId, zkgm.Version, unionChannelId, nil, 0, cur.Previous().Address().String()))
	}
	requireChannel()
}

func requireConnectionInit() {
	conn, err := core.GetConnection(gnoConnectionId)
	if err != nil || conn.State != types.ConnectionStateInit || conn.ClientId != gnoClientId || conn.CounterpartyClientId != unionClientId {
		panic("new Gno connection id is not 5")
	}
}

func requireChannelInit() {
	channel, err := core.GetChannel(gnoChannelId)
	if err != nil || channel.State != types.ChannelStateInit || channel.ConnectionId != gnoConnectionId ||
		string(channel.CounterpartyPortId) != portId || channel.Version != zkgm.Version {
		panic("new Gno channel id is not 3")
	}
}

func requireConnection() {
	conn, err := core.GetConnection(gnoConnectionId)
	if err != nil || conn.State != types.ConnectionStateOpen || conn.ClientId != gnoClientId ||
		conn.CounterpartyClientId != unionClientId || conn.CounterpartyConnectionId != unionConnectionId {
		panic("Gno connection 5 already exists but differs")
	}
}

func requireChannel() {
	channel, err := core.GetChannel(gnoChannelId)
	if err != nil || channel.State != types.ChannelStateOpen || channel.ConnectionId != gnoConnectionId ||
		channel.CounterpartyChannelId != unionChannelId || string(channel.CounterpartyPortId) != portId || channel.Version != zkgm.Version {
		panic("Gno channel 3 already exists but differs")
	}
}
