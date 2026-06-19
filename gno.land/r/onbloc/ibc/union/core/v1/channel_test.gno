package impl

import (
	"testing"

	"gno.land/p/nt/uassert/v0"
	"gno.land/p/onbloc/ibc/union/types"
	core "gno.land/r/onbloc/ibc/union/core"
)

// setupChannelEnv seeds an active client, an open connection (id 1), and a
// registered app at "app-port", returning the port id and the app.
func setupChannelEnv(cur realm, v *coreV1) (types.Bytes, *mockApp) {
	ms := v.store.(*mockStore)
	clientId := v.CreateClient(0, cur, types.ClientType("cometbls"), &mockLightClient{})
	ms.SaveConnection(0, cur, types.ConnectionId(1),
		core.NewConnection(types.ConnectionStateOpen, clientId, types.ClientId(7), types.ConnectionId(2)))
	portId := types.Bytes("app-port")
	mApp := &mockApp{}
	ms.registerApp(portId, mApp)
	return portId, mApp
}

func openTryMsg(portId types.Bytes) types.MsgChannelOpenTry {
	return types.MsgChannelOpenTry{
		PortId: portId,
		Channel: types.Channel{
			State:                 types.ChannelStateTryOpen,
			ConnectionId:          types.ConnectionId(1),
			CounterpartyChannelId: types.ChannelId(9),
			CounterpartyPortId:    types.Bytes("cp-port"),
			Version:               "v1",
		},
		CounterpartyVersion: "v1",
		ProofHeight:         10,
		ProofInit:           []byte("proof"),
	}
}

func TestChannelOpenInit(cur realm, t *testing.T) {
	v := newTestImpl()
	portId, mApp := setupChannelEnv(cur, v)

	chId := v.ChannelOpenInit(0, cur, types.MsgChannelOpenInit{
		PortId:             portId,
		ConnectionId:       types.ConnectionId(1),
		CounterpartyPortId: types.Bytes("cp-port"),
		Version:            "v1",
	})

	ch, ok := v.store.GetChannel(chId)
	uassert.True(t, ok)
	uassert.True(t, ch.State == types.ChannelStateInit)
	uassert.Equal(t, 1, mApp.openInit)
}

func TestChannelOpenInitRequiresOpenConnection(cur realm, t *testing.T) {
	v := newTestImpl()
	portId, _ := setupChannelEnv(cur, v)
	// Connection 2 is never opened.
	uassert.AbortsContains(t, cur, "not found", func(cur realm) {
		v.ChannelOpenInit(0, cur, types.MsgChannelOpenInit{
			PortId:       portId,
			ConnectionId: types.ConnectionId(2),
			Version:      "v1",
		})
	})
}

func TestChannelOpenTry(cur realm, t *testing.T) {
	v := newTestImpl()
	portId, mApp := setupChannelEnv(cur, v)

	chId := v.ChannelOpenTry(0, cur, openTryMsg(portId))

	ch, ok := v.store.GetChannel(chId)
	uassert.True(t, ok)
	uassert.True(t, ch.State == types.ChannelStateTryOpen)
	uassert.Equal(t, 1, mApp.openTry)
}

func TestChannelOpenTryProofFailureAborts(cur realm, t *testing.T) {
	v := newTestImpl()
	ms := v.store.(*mockStore)
	clientId := v.CreateClient(0, cur, types.ClientType("cometbls"), &mockLightClient{membershipErr: "bad proof"})
	ms.SaveConnection(0, cur, types.ConnectionId(1),
		core.NewConnection(types.ConnectionStateOpen, clientId, types.ClientId(7), types.ConnectionId(2)))
	portId := types.Bytes("app-port")
	ms.registerApp(portId, &mockApp{})

	uassert.AbortsContains(t, cur, "bad proof", func(cur realm) {
		v.ChannelOpenTry(0, cur, openTryMsg(portId))
	})
}

func TestChannelOpenAckMovesInitToOpen(cur realm, t *testing.T) {
	v := newTestImpl()
	portId, mApp := setupChannelEnv(cur, v)
	chId := v.ChannelOpenInit(0, cur, types.MsgChannelOpenInit{
		PortId: portId, ConnectionId: types.ConnectionId(1), Version: "v1",
	})

	v.ChannelOpenAck(0, cur, types.MsgChannelOpenAck{
		ChannelId:             chId,
		CounterpartyChannelId: types.ChannelId(9),
		CounterpartyVersion:   "v1",
		ProofHeight:           10,
		ProofTry:              []byte("proof"),
	})

	ch, _ := v.store.GetChannel(chId)
	uassert.True(t, ch.State == types.ChannelStateOpen)
	uassert.Equal(t, uint32(9), uint32(ch.CounterpartyChannelId))
	uassert.Equal(t, 1, mApp.openAck)
}

func TestChannelOpenAckWrongStateAborts(cur realm, t *testing.T) {
	v := newTestImpl()
	portId, _ := setupChannelEnv(cur, v)
	// TryOpen is the wrong state for an ack.
	chId := v.ChannelOpenTry(0, cur, openTryMsg(portId))

	uassert.AbortsContains(t, cur, "invalid channel state", func(cur realm) {
		v.ChannelOpenAck(0, cur, types.MsgChannelOpenAck{
			ChannelId: chId, CounterpartyChannelId: types.ChannelId(9),
			CounterpartyVersion: "v1", ProofHeight: 10, ProofTry: []byte("p"),
		})
	})
}

func TestChannelOpenConfirmMovesTryOpenToOpen(cur realm, t *testing.T) {
	v := newTestImpl()
	portId, mApp := setupChannelEnv(cur, v)
	chId := v.ChannelOpenTry(0, cur, openTryMsg(portId))

	v.ChannelOpenConfirm(0, cur, types.MsgChannelOpenConfirm{
		ChannelId: chId, ProofHeight: 11, ProofAck: []byte("proof"),
	})

	ch, _ := v.store.GetChannel(chId)
	uassert.True(t, ch.State == types.ChannelStateOpen)
	uassert.Equal(t, 1, mApp.openConfirm)
}

func TestChannelCloseInit(cur realm, t *testing.T) {
	v := newTestImpl()
	portId, mApp := setupChannelEnv(cur, v)
	// Open the channel: Init -> Ack -> Open.
	chId := v.ChannelOpenInit(0, cur, types.MsgChannelOpenInit{PortId: portId, ConnectionId: types.ConnectionId(1), Version: "v1"})
	v.ChannelOpenAck(0, cur, types.MsgChannelOpenAck{ChannelId: chId, CounterpartyChannelId: types.ChannelId(9), CounterpartyVersion: "v1", ProofHeight: 10, ProofTry: []byte("p")})

	v.ChannelCloseInit(0, cur, types.MsgChannelCloseInit{ChannelId: chId})

	ch, _ := v.store.GetChannel(chId)
	uassert.True(t, ch.State == types.ChannelStateClosed)
	uassert.Equal(t, 1, mApp.closeInit)
}

func TestChannelCloseConfirm(cur realm, t *testing.T) {
	v := newTestImpl()
	portId, mApp := setupChannelEnv(cur, v)
	chId := v.ChannelOpenInit(0, cur, types.MsgChannelOpenInit{PortId: portId, ConnectionId: types.ConnectionId(1), Version: "v1"})
	v.ChannelOpenAck(0, cur, types.MsgChannelOpenAck{ChannelId: chId, CounterpartyChannelId: types.ChannelId(9), CounterpartyVersion: "v1", ProofHeight: 10, ProofTry: []byte("p")})

	v.ChannelCloseConfirm(0, cur, types.MsgChannelCloseConfirm{ChannelId: chId, ProofHeight: 12, ProofInit: []byte("proof")})

	ch, _ := v.store.GetChannel(chId)
	uassert.True(t, ch.State == types.ChannelStateClosed)
	uassert.Equal(t, 1, mApp.closeConfirm)
}
