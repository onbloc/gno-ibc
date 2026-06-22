package impl

import (
	"testing"

	"gno.land/p/nt/uassert/v0"
	"gno.land/p/onbloc/ibc/union/lightclient"
	"gno.land/p/onbloc/ibc/union/types"
	core "gno.land/r/onbloc/ibc/union/core"
)

// setupChannelEnv seeds an active client, an open connection (id 1), and a
// registered app at "app-port", returning the port id and the app.
func setupChannelEnv(cur realm, v *coreV1) (types.Bytes, *mockApp) {
	ms := v.store.(*mockStore)
	clientId := createClient(cur, v, &mockLightClient{}, nil, nil)
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

	v.ChannelOpenInit(0, cur, types.MsgChannelOpenInit{
		PortId:             portId,
		ConnectionId:       types.ConnectionId(1),
		CounterpartyPortId: types.Bytes("cp-port"),
		Version:            "v1",
	})
	chId := v.store.(*mockStore).currentChannelId()

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

	v.ChannelOpenTry(0, cur, openTryMsg(portId))
	chId := v.store.(*mockStore).currentChannelId()

	ch, ok := v.store.GetChannel(chId)
	uassert.True(t, ok)
	uassert.True(t, ch.State == types.ChannelStateTryOpen)
	uassert.Equal(t, 1, mApp.openTry)
}

func TestChannelOpenTryProofFailureAborts(cur realm, t *testing.T) {
	v := newTestImpl()
	ms := v.store.(*mockStore)
	clientId := createClient(cur, v, &mockLightClient{membershipErr: "bad proof"}, nil, nil)
	ms.SaveConnection(0, cur, types.ConnectionId(1),
		core.NewConnection(types.ConnectionStateOpen, clientId, types.ClientId(7), types.ConnectionId(2)))
	portId := types.Bytes("app-port")
	ms.registerApp(portId, &mockApp{})

	uassert.AbortsContains(t, cur, "bad proof", func(cur realm) {
		v.ChannelOpenTry(0, cur, openTryMsg(portId))
	})
}

// Converted from Union channel_open_try_invalid_state.
// Union reference:
// https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/core/src/tests/channel/ibc_channel.rs#L275-L346
func TestChannelOpenTryInvalidState(cur realm, t *testing.T) {
	v := newTestImpl()
	portId, _ := setupChannelEnv(cur, v)
	msg := openTryMsg(portId)
	msg.Channel.State = types.ChannelStateOpen // must be TryOpen

	uassert.AbortsContains(t, cur, "invalid channel state", func(cur realm) {
		v.ChannelOpenTry(0, cur, msg)
	})
}

// Converted from Union channel_open_try_invalid_counterparty.
// Union reference:
// https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/core/src/tests/channel/ibc_channel.rs#L815-L878
func TestChannelOpenTryInvalidCounterparty(cur realm, t *testing.T) {
	v := newTestImpl()
	portId, _ := setupChannelEnv(cur, v)
	msg := openTryMsg(portId)
	msg.Channel.CounterpartyChannelId = 0 // Union counterparty_channel_id is non-zero

	uassert.AbortsContains(t, cur, "invalid counterparty channel id", func(cur realm) {
		v.ChannelOpenTry(0, cur, msg)
	})
}

// Handler-level guard: ChannelOpenTry must reject an inactive client before it
// persists the channel.
func TestChannelOpenTryRejectsInactiveClient(cur realm, t *testing.T) {
	v := newTestImpl()
	ms := v.store.(*mockStore)
	lc := &mockLightClient{status: lightclient.Expired}
	clientId := createClient(cur, v, lc, nil, nil)
	ms.SaveConnection(0, cur, types.ConnectionId(1),
		core.NewConnection(types.ConnectionStateOpen, clientId, types.ClientId(7), types.ConnectionId(2)))
	portId := types.Bytes("app-port")
	ms.registerApp(portId, &mockApp{})

	uassert.AbortsContains(t, cur, "client is not active", func(cur realm) {
		v.ChannelOpenTry(0, cur, openTryMsg(portId))
	})

	// The inactive client must not have persisted a new channel.
	_, ok := v.store.GetChannel(types.ChannelId(1))
	uassert.False(t, ok)
}

func TestChannelOpenAckMovesInitToOpen(cur realm, t *testing.T) {
	v := newTestImpl()
	portId, mApp := setupChannelEnv(cur, v)
	v.ChannelOpenInit(0, cur, types.MsgChannelOpenInit{
		PortId: portId, ConnectionId: types.ConnectionId(1), Version: "v1",
	})
	chId := v.store.(*mockStore).currentChannelId()

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

// Converted from Union channel_open_ack_not_found.
// Union reference:
// https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/core/src/tests/channel/ibc_channel.rs#L591-L650
func TestChannelOpenAckNotFound(cur realm, t *testing.T) {
	v := newTestImpl()

	uassert.AbortsContains(t, cur, "channel 1 not found", func(cur realm) {
		v.ChannelOpenAck(0, cur, types.MsgChannelOpenAck{
			ChannelId: types.ChannelId(1), CounterpartyChannelId: types.ChannelId(9),
			CounterpartyVersion: "v1", ProofHeight: 10, ProofTry: []byte("p"),
		})
	})
}

// Local regression: Union MsgChannelOpenAck carries a concrete ChannelId, not an
// Option, so the host must not reject a zero counterparty id before verification.
// Force path (verify=false) so no proof is needed.
func TestForceChannelOpenAckAllowsZeroCounterpartyChannelId(cur realm, t *testing.T) {
	v := newTestImpl()
	portId, _ := setupChannelEnv(cur, v)
	v.ChannelOpenInit(0, cur, types.MsgChannelOpenInit{
		PortId: portId, ConnectionId: types.ConnectionId(1), Version: "v1",
	})
	chId := v.store.(*mockStore).currentChannelId()

	v.ForceChannelOpenAck(0, cur, types.MsgChannelOpenAck{
		ChannelId:             chId,
		CounterpartyChannelId: 0,
		CounterpartyVersion:   "v1",
		ProofTry:              []byte("proof"),
		ProofHeight:           10,
	})

	ch, _ := v.store.GetChannel(chId)
	uassert.True(t, ch.State == types.ChannelStateOpen)
	uassert.Equal(t, uint32(0), uint32(ch.CounterpartyChannelId))
}

func TestChannelOpenAckWrongStateAborts(cur realm, t *testing.T) {
	v := newTestImpl()
	portId, _ := setupChannelEnv(cur, v)
	// TryOpen is the wrong state for an ack.
	v.ChannelOpenTry(0, cur, openTryMsg(portId))
	chId := v.store.(*mockStore).currentChannelId()

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
	v.ChannelOpenTry(0, cur, openTryMsg(portId))
	chId := v.store.(*mockStore).currentChannelId()

	v.ChannelOpenConfirm(0, cur, types.MsgChannelOpenConfirm{
		ChannelId: chId, ProofHeight: 11, ProofAck: []byte("proof"),
	})

	ch, _ := v.store.GetChannel(chId)
	uassert.True(t, ch.State == types.ChannelStateOpen)
	uassert.Equal(t, 1, mApp.openConfirm)
}

// Converted from Union channel_open_confirm_not_found.
// Union reference:
// https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/core/src/tests/channel/ibc_channel.rs#L879-L938
func TestChannelOpenConfirmNotFound(cur realm, t *testing.T) {
	v := newTestImpl()

	uassert.AbortsContains(t, cur, "channel 1 not found", func(cur realm) {
		v.ChannelOpenConfirm(0, cur, types.MsgChannelOpenConfirm{
			ChannelId: types.ChannelId(1), ProofHeight: 11, ProofAck: []byte("proof"),
		})
	})
}

// Local regression for Gno's zero-as-None representation of Union
// counterparty_channel_id: a TryOpen channel with a zero counterparty id must be
// rejected before the membership proof is checked.
func TestChannelOpenConfirmRejectsInvalidCounterpartyChannelId(cur realm, t *testing.T) {
	v := newTestImpl()
	portId, _ := setupChannelEnv(cur, v)
	chId := v.store.NextChannelId(0, cur)
	v.store.CreateChannel(0, cur, chId, types.Channel{
		State:                 types.ChannelStateTryOpen,
		ConnectionId:          types.ConnectionId(1),
		CounterpartyChannelId: 0,
		CounterpartyPortId:    types.Bytes("cp-port"),
		Version:               "v1",
	}, portId)

	uassert.AbortsContains(t, cur, "invalid counterparty channel id", func(cur realm) {
		v.ChannelOpenConfirm(0, cur, types.MsgChannelOpenConfirm{
			ChannelId: chId, ProofHeight: 11, ProofAck: []byte("proof"),
		})
	})
}

// A channel that is not in TryOpen must be rejected by ChannelOpenConfirm.
func TestChannelOpenConfirmWrongStateAborts(cur realm, t *testing.T) {
	v := newTestImpl()
	portId, _ := setupChannelEnv(cur, v)
	chId := v.store.NextChannelId(0, cur)
	v.store.CreateChannel(0, cur, chId, types.Channel{
		State:                 types.ChannelStateOpen, // not TryOpen
		ConnectionId:          types.ConnectionId(1),
		CounterpartyChannelId: types.ChannelId(9),
		CounterpartyPortId:    types.Bytes("cp-port"),
		Version:               "v1",
	}, portId)

	uassert.AbortsContains(t, cur, "invalid channel state", func(cur realm) {
		v.ChannelOpenConfirm(0, cur, types.MsgChannelOpenConfirm{
			ChannelId: chId, ProofHeight: 11, ProofAck: []byte("proof"),
		})
	})
}

func TestChannelOpenRejectsMissingPortApp(cur realm, t *testing.T) {
	tests := []struct {
		name string
		want string
		run  func(cur realm)
	}{
		{
			name: "open init missing app",
			want: "port missing-port not found",
			run: func(cur realm) {
				v := newTestImpl()
				ms := v.store.(*mockStore)
				clientId := createClient(cur, v, &mockLightClient{}, nil, nil)
				ms.SaveConnection(0, cur, types.ConnectionId(1),
					core.NewConnection(types.ConnectionStateOpen, clientId, types.ClientId(7), types.ConnectionId(2)))
				v.ChannelOpenInit(0, cur, types.MsgChannelOpenInit{
					PortId:       types.Bytes("missing-port"),
					ConnectionId: types.ConnectionId(1),
					Version:      "v1",
				})
			},
		},
		{
			name: "open try missing app",
			want: "port missing-port not found",
			run: func(cur realm) {
				v := newTestImpl()
				ms := v.store.(*mockStore)
				clientId := createClient(cur, v, &mockLightClient{}, nil, nil)
				ms.SaveConnection(0, cur, types.ConnectionId(1),
					core.NewConnection(types.ConnectionStateOpen, clientId, types.ClientId(7), types.ConnectionId(2)))
				v.ChannelOpenTry(0, cur, openTryMsg(types.Bytes("missing-port")))
			},
		},
		{
			name: "open ack missing app",
			want: "port missing-port not found",
			run: func(cur realm) {
				v := newTestImpl()
				ms := v.store.(*mockStore)
				clientId := createClient(cur, v, &mockLightClient{}, nil, nil)
				ms.SaveConnection(0, cur, types.ConnectionId(1),
					core.NewConnection(types.ConnectionStateOpen, clientId, types.ClientId(7), types.ConnectionId(2)))
				chId := v.store.NextChannelId(0, cur)
				v.store.CreateChannel(0, cur, chId, types.Channel{
					State:        types.ChannelStateInit,
					ConnectionId: types.ConnectionId(1),
					Version:      "v1",
				}, types.Bytes("missing-port"))
				v.ChannelOpenAck(0, cur, types.MsgChannelOpenAck{
					ChannelId:             chId,
					CounterpartyChannelId: types.ChannelId(9),
					CounterpartyVersion:   "v1",
					ProofHeight:           10,
					ProofTry:              []byte("proof"),
				})
			},
		},
		{
			name: "open confirm missing app",
			want: "port missing-port not found",
			run: func(cur realm) {
				v := newTestImpl()
				ms := v.store.(*mockStore)
				clientId := createClient(cur, v, &mockLightClient{}, nil, nil)
				ms.SaveConnection(0, cur, types.ConnectionId(1),
					core.NewConnection(types.ConnectionStateOpen, clientId, types.ClientId(7), types.ConnectionId(2)))
				chId := v.store.NextChannelId(0, cur)
				v.store.CreateChannel(0, cur, chId, types.Channel{
					State:                 types.ChannelStateTryOpen,
					ConnectionId:          types.ConnectionId(1),
					CounterpartyChannelId: types.ChannelId(9),
					Version:               "v1",
				}, types.Bytes("missing-port"))
				v.ChannelOpenConfirm(0, cur, types.MsgChannelOpenConfirm{
					ChannelId:   chId,
					ProofHeight: 11,
					ProofAck:    []byte("proof"),
				})
			},
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			uassert.AbortsContains(t, cur, tc.want, tc.run)
		})
	}
}

func TestChannelCloseInit(cur realm, t *testing.T) {
	v := newTestImpl()
	portId, mApp := setupChannelEnv(cur, v)
	// Open the channel: Init -> Ack -> Open.
	v.ChannelOpenInit(0, cur, types.MsgChannelOpenInit{PortId: portId, ConnectionId: types.ConnectionId(1), Version: "v1"})
	chId := v.store.(*mockStore).currentChannelId()
	v.ChannelOpenAck(0, cur, types.MsgChannelOpenAck{ChannelId: chId, CounterpartyChannelId: types.ChannelId(9), CounterpartyVersion: "v1", ProofHeight: 10, ProofTry: []byte("p")})

	v.ChannelCloseInit(0, cur, types.MsgChannelCloseInit{ChannelId: chId})

	ch, _ := v.store.GetChannel(chId)
	uassert.True(t, ch.State == types.ChannelStateClosed)
	uassert.Equal(t, 1, mApp.closeInit)
}

func TestChannelCloseConfirm(cur realm, t *testing.T) {
	v := newTestImpl()
	portId, mApp := setupChannelEnv(cur, v)
	v.ChannelOpenInit(0, cur, types.MsgChannelOpenInit{PortId: portId, ConnectionId: types.ConnectionId(1), Version: "v1"})
	chId := v.store.(*mockStore).currentChannelId()
	v.ChannelOpenAck(0, cur, types.MsgChannelOpenAck{ChannelId: chId, CounterpartyChannelId: types.ChannelId(9), CounterpartyVersion: "v1", ProofHeight: 10, ProofTry: []byte("p")})

	v.ChannelCloseConfirm(0, cur, types.MsgChannelCloseConfirm{ChannelId: chId, ProofHeight: 12, ProofInit: []byte("proof")})

	ch, _ := v.store.GetChannel(chId)
	uassert.True(t, ch.State == types.ChannelStateClosed)
	uassert.Equal(t, 1, mApp.closeConfirm)
}

func TestChannelCloseRejectsInvalidMessages(cur realm, t *testing.T) {
	testCases := []struct {
		name string
		want string
		run  func(cur realm)
	}{
		{
			name: "close init missing channel",
			want: "channel 1 not found",
			run: func(cur realm) {
				v := newTestImpl()
				v.ChannelCloseInit(0, cur, types.MsgChannelCloseInit{ChannelId: types.ChannelId(1)})
			},
		},
		{
			name: "close init invalid counterparty channel",
			want: "invalid counterparty channel id",
			run: func(cur realm) {
				v := newTestImpl()
				portId, _ := setupChannelEnv(cur, v)
				chId := v.store.NextChannelId(0, cur)
				v.store.CreateChannel(0, cur, chId, types.Channel{
					State:        types.ChannelStateOpen,
					ConnectionId: types.ConnectionId(1),
					Version:      "v1",
				}, portId)
				v.ChannelCloseInit(0, cur, types.MsgChannelCloseInit{ChannelId: chId})
			},
		},
		{
			name: "close confirm missing channel",
			want: "channel 1 not found",
			run: func(cur realm) {
				v := newTestImpl()
				v.ChannelCloseConfirm(0, cur, types.MsgChannelCloseConfirm{ChannelId: types.ChannelId(1), ProofHeight: 12, ProofInit: []byte("proof")})
			},
		},
		{
			name: "close confirm wrong state",
			want: "invalid channel state",
			run: func(cur realm) {
				v := newTestImpl()
				portId, _ := setupChannelEnv(cur, v)
				chId := v.store.NextChannelId(0, cur)
				v.store.CreateChannel(0, cur, chId, types.Channel{
					State:                 types.ChannelStateClosed,
					ConnectionId:          types.ConnectionId(1),
					CounterpartyChannelId: types.ChannelId(9),
					CounterpartyPortId:    types.Bytes("cp-port"),
					Version:               "v1",
				}, portId)
				v.ChannelCloseConfirm(0, cur, types.MsgChannelCloseConfirm{ChannelId: chId, ProofHeight: 12, ProofInit: []byte("proof")})
			},
		},
		{
			name: "close confirm invalid counterparty channel",
			want: "invalid counterparty channel id",
			run: func(cur realm) {
				v := newTestImpl()
				portId, _ := setupChannelEnv(cur, v)
				chId := v.store.NextChannelId(0, cur)
				v.store.CreateChannel(0, cur, chId, types.Channel{
					State:        types.ChannelStateOpen,
					ConnectionId: types.ConnectionId(1),
					Version:      "v1",
				}, portId)
				v.ChannelCloseConfirm(0, cur, types.MsgChannelCloseConfirm{ChannelId: chId, ProofHeight: 12, ProofInit: []byte("proof")})
			},
		},
		{
			name: "close confirm proof failure",
			want: "bad close proof",
			run: func(cur realm) {
				v := newTestImpl()
				ms := v.store.(*mockStore)
				clientId := createClient(cur, v, &mockLightClient{membershipErr: "bad close proof"}, nil, nil)
				ms.SaveConnection(0, cur, types.ConnectionId(1),
					core.NewConnection(types.ConnectionStateOpen, clientId, types.ClientId(7), types.ConnectionId(2)))
				portId := types.Bytes("app-port")
				ms.registerApp(portId, &mockApp{})
				chId := v.store.NextChannelId(0, cur)
				v.store.CreateChannel(0, cur, chId, types.Channel{
					State:                 types.ChannelStateOpen,
					ConnectionId:          types.ConnectionId(1),
					CounterpartyChannelId: types.ChannelId(9),
					CounterpartyPortId:    types.Bytes("cp-port"),
					Version:               "v1",
				}, portId)
				v.ChannelCloseConfirm(0, cur, types.MsgChannelCloseConfirm{ChannelId: chId, ProofHeight: 12, ProofInit: []byte("proof")})
			},
		},
	}

	for _, tc := range testCases {
		t.Run(tc.name, func(t *testing.T) {
			uassert.AbortsContains(t, cur, tc.want, tc.run)
		})
	}
}

// setupFrozenChannelEnv mirrors setupChannelEnv but registers a frozen client, so
// the proof-verifying handshake path would abort ("client is not active"). The
// Force* variants must skip verification and still succeed.
func setupFrozenChannelEnv(cur realm, v *coreV1) (types.Bytes, *mockApp) {
	ms := v.store.(*mockStore)
	clientId := createClient(cur, v, &mockLightClient{status: lightclient.Frozen}, nil, nil)
	ms.SaveConnection(0, cur, types.ConnectionId(1),
		core.NewConnection(types.ConnectionStateOpen, clientId, types.ClientId(7), types.ConnectionId(2)))
	portId := types.Bytes("app-port")
	mApp := &mockApp{}
	ms.registerApp(portId, mApp)
	return portId, mApp
}

func TestForceChannelOpenTrySkipsProofVerification(cur realm, t *testing.T) {
	v := newTestImpl()
	portId, mApp := setupFrozenChannelEnv(cur, v)

	v.ForceChannelOpenTry(0, cur, openTryMsg(portId))
	chId := v.store.(*mockStore).currentChannelId()

	ch, ok := v.store.GetChannel(chId)
	uassert.True(t, ok)
	uassert.True(t, ch.State == types.ChannelStateTryOpen)
	uassert.Equal(t, 1, mApp.openTry)
}

func TestForceChannelOpenAckSkipsProofVerification(cur realm, t *testing.T) {
	v := newTestImpl()
	portId, mApp := setupFrozenChannelEnv(cur, v)
	chId := v.store.NextChannelId(0, cur)
	v.store.CreateChannel(0, cur, chId, types.Channel{
		State:              types.ChannelStateInit,
		ConnectionId:       types.ConnectionId(1),
		CounterpartyPortId: types.Bytes("cp-port"),
		Version:            "v1",
	}, portId)

	v.ForceChannelOpenAck(0, cur, types.MsgChannelOpenAck{
		ChannelId:             chId,
		CounterpartyChannelId: types.ChannelId(123),
		CounterpartyVersion:   "counterparty-v1",
		ProofTry:              []byte("ignored-proof"),
		ProofHeight:           10,
	})

	ch, _ := v.store.GetChannel(chId)
	uassert.True(t, ch.State == types.ChannelStateOpen)
	uassert.Equal(t, "counterparty-v1", ch.Version)
	uassert.Equal(t, uint32(123), uint32(ch.CounterpartyChannelId))
	uassert.Equal(t, 1, mApp.openAck)
}

func TestForceChannelOpenConfirmSkipsProofVerification(cur realm, t *testing.T) {
	v := newTestImpl()
	portId, mApp := setupFrozenChannelEnv(cur, v)
	chId := v.store.NextChannelId(0, cur)
	v.store.CreateChannel(0, cur, chId, types.Channel{
		State:                 types.ChannelStateTryOpen,
		ConnectionId:          types.ConnectionId(1),
		CounterpartyChannelId: types.ChannelId(123),
		CounterpartyPortId:    types.Bytes("cp-port"),
		Version:               "v1",
	}, portId)

	v.ForceChannelOpenConfirm(0, cur, types.MsgChannelOpenConfirm{
		ChannelId:   chId,
		ProofAck:    []byte("ignored-proof"),
		ProofHeight: 10,
	})

	ch, _ := v.store.GetChannel(chId)
	uassert.True(t, ch.State == types.ChannelStateOpen)
	uassert.Equal(t, 1, mApp.openConfirm)
}
