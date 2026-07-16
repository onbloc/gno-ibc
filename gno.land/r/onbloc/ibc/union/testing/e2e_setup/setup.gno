package e2e_setup

import (
	"chain"
	"chain/runtime"
	"chain/runtime/unsafe"

	"gno.land/p/onbloc/access/manager"
	"gno.land/p/onbloc/ibc/union/types"
	"gno.land/r/onbloc/ibc/union/access"
	zkgm "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm"
	core "gno.land/r/onbloc/ibc/union/core"
	cometbls "gno.land/r/onbloc/ibc/union/lightclients/cometbls"
	statelens "gno.land/r/onbloc/ibc/union/lightclients/statelensics23mpt"
)

const (
	PkgPath = "gno.land/r/onbloc/ibc/union/testing/e2e_setup"

	gnoClientId       = types.ClientId(1)
	unionClientId     = types.ClientId(1)
	gnoConnectionId   = types.ConnectionId(5)
	unionConnectionId = types.ConnectionId(3)
	gnoChannelId      = types.ChannelId(3)
	unionChannelId    = types.ChannelId(2)
	portId            = "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm"
)

func Address() string { return PackageAddress(PkgPath) }

func PackageAddress(path string) string { return chain.PackageAddress(path).String() }

func Bootstrap(cur realm) {
	runtime.AssertOriginCall()
	requireAdmin()
	core.UpdateImpl(cross(cur), "gno.land/r/onbloc/ibc/union/core/v1")
	zkgm.UpdateImpl(cross(cur), "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/v1")
	if !core.HasApp([]byte(zkgm.ProxyPkgPath())) {
		zkgm.RegisterCoreApp(cross(cur))
	}
	if !core.HasClient(cometbls.ClientType) {
		cometbls.RegisterClient(cross(cur))
	}
	if !core.HasClient(statelens.ClientType) {
		statelens.RegisterClient(cross(cur))
	}
}

func Recover(cur realm) {
	runtime.AssertOriginCall()
	admin := requireAdmin()
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
				core.ChannelOpenInit(cross(cur), core.NewMsgChannelOpenInit([]byte(portId), []byte(portId), gnoConnectionId, zkgm.Version, admin.String()))
			}
		}
		requireChannelInit()
		core.ForceChannelOpenAck(cross(cur), core.NewMsgChannelOpenAck(gnoChannelId, zkgm.Version, unionChannelId, nil, 0, admin.String()))
	}
	requireChannel()
}

func requireAdmin() address {
	// SAFE: setup authorization is intentionally bound to the transaction origin.
	caller := unsafe.OriginCaller()
	if !access.HasRole(manager.AdminRole, caller).IsMember {
		panic("e2e setup caller is not admin")
	}
	return caller
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
