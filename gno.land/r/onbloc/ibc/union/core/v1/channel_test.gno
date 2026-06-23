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
	return setupChannelEnvWithLightClient(cur, v, &mockLightClient{})
}

func setupChannelEnvWithLightClient(cur realm, v *coreV1, lc *mockLightClient) (types.Bytes, *mockApp) {
	ms := v.store.(*mockStore)
	clientId := createClient(cur, v, lc, nil, nil)
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
	tests := []struct {
		name         string
		connectionId types.ConnectionId
		missingApp   bool
		wantAbort    string
		wantSaved    bool
		wantNotify   int
	}{
		{"opens init channel", types.ConnectionId(1), false, "", true, 1},
		// Connection 2 is never opened.
		{"requires open connection", types.ConnectionId(2), false, "not found", false, 0},
		{"missing app", types.ConnectionId(1), true, "port missing-port not found", true, 0},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			v := newTestImpl()
			var portId types.Bytes
			var mApp *mockApp
			if tc.missingApp {
				ms := v.store.(*mockStore)
				clientId := createClient(cur, v, &mockLightClient{}, nil, nil)
				ms.SaveConnection(0, cur, types.ConnectionId(1),
					core.NewConnection(types.ConnectionStateOpen, clientId, types.ClientId(7), types.ConnectionId(2)))
				portId = types.Bytes("missing-port")
				mApp = &mockApp{}
			} else {
				portId, mApp = setupChannelEnv(cur, v)
			}
			msg := types.MsgChannelOpenInit{
				PortId:             portId,
				ConnectionId:       tc.connectionId,
				CounterpartyPortId: types.Bytes("cp-port"),
				Version:            "v1",
			}

			run := func(cur realm) {
				v.ChannelOpenInit(0, cur, msg)
			}
			if tc.wantAbort != "" {
				uassert.AbortsContains(t, cur, tc.wantAbort, run)
			} else {
				uassert.NotAborts(t, cur, func() {
					v.ChannelOpenInit(0, cur, msg)
				})
			}

			chId := v.store.(*mockStore).currentChannelId()
			ch, ok := v.store.GetChannel(chId)
			uassert.Equal(t, tc.wantSaved, ok)
			if tc.wantSaved {
				uassert.True(t, ch.State == types.ChannelStateInit)
			}
			uassert.Equal(t, tc.wantNotify, mApp.openInit)
		})
	}
}

func TestChannelOpenTry(cur realm, t *testing.T) {
	tests := []struct {
		name       string
		lc         *mockLightClient
		verify     bool
		public     bool
		force      bool
		missingApp bool
		malleate   func(msg *types.MsgChannelOpenTry)
		wantAbort  string
		wantCalls  int
		wantSaved  bool
		wantNotify int
	}{
		{"verifies proof and saves try-open channel", &mockLightClient{}, true, false, false, false, func(msg *types.MsgChannelOpenTry) {}, "", 1, true, 1},
		{"force path skips proof verification", &mockLightClient{status: lightclient.Frozen}, false, false, false, false, func(msg *types.MsgChannelOpenTry) {}, "", 0, true, 1},
		{"force wrapper skips proof verification", &mockLightClient{status: lightclient.Frozen}, false, false, true, false, func(msg *types.MsgChannelOpenTry) {}, "", 0, true, 1},
		{"missing app", &mockLightClient{}, true, true, false, true, func(msg *types.MsgChannelOpenTry) {}, "port missing-port not found", 1, true, 0},
		{"invalid state aborts before proof", &mockLightClient{}, true, false, false, false, func(msg *types.MsgChannelOpenTry) { msg.Channel.State = types.ChannelStateOpen }, "invalid channel state", 0, false, 0},
		{"invalid counterparty aborts before proof", &mockLightClient{}, true, false, false, false, func(msg *types.MsgChannelOpenTry) { msg.Channel.CounterpartyChannelId = 0 }, "invalid counterparty channel id", 0, false, 0},
		{"proof failure aborts", &mockLightClient{membershipErr: "bad proof"}, true, false, false, false, func(msg *types.MsgChannelOpenTry) {}, "bad proof", 1, false, 0},
		{"public proof failure aborts", &mockLightClient{membershipErr: "bad proof"}, true, true, false, false, func(msg *types.MsgChannelOpenTry) {}, "bad proof", 1, false, 0},
		// Converted from Union channel_open_try_invalid_state.
		// Union reference:
		// https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/core/src/tests/channel/ibc_channel.rs#L275-L346
		{"public invalid state aborts", &mockLightClient{}, true, true, false, false, func(msg *types.MsgChannelOpenTry) {
			msg.Channel.State = types.ChannelStateOpen // must be TryOpen
		}, "invalid channel state", 0, false, 0},
		// Converted from Union channel_open_try_invalid_counterparty.
		// Union reference:
		// https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/core/src/tests/channel/ibc_channel.rs#L815-L878
		{"public invalid counterparty aborts", &mockLightClient{}, true, true, false, false, func(msg *types.MsgChannelOpenTry) {
			msg.Channel.CounterpartyChannelId = 0 // Union counterparty_channel_id is non-zero
		}, "invalid counterparty channel id", 0, false, 0},
		// Handler-level guard: ChannelOpenTry must reject an inactive client before it
		// persists the channel.
		{"public rejects inactive client", &mockLightClient{status: lightclient.Expired}, true, true, false, false, func(msg *types.MsgChannelOpenTry) {}, "client is not active", 0, false, 0},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			v := newTestImpl()
			ms := v.store.(*mockStore)
			clientId := createClient(cur, v, tc.lc, nil, nil)
			ms.SaveConnection(0, cur, types.ConnectionId(1),
				core.NewConnection(types.ConnectionStateOpen, clientId, types.ClientId(7), types.ConnectionId(2)))
			portId := types.Bytes("app-port")
			mApp := &mockApp{}
			if tc.missingApp {
				portId = types.Bytes("missing-port")
			} else {
				ms.registerApp(portId, mApp)
			}
			msg := openTryMsg(portId)
			tc.malleate(&msg)

			run := func(cur realm) {
				if tc.force {
					v.ForceChannelOpenTry(0, cur, msg)
				} else if tc.public {
					v.ChannelOpenTry(0, cur, msg)
				} else {
					v.channelOpenTry(0, cur, msg, tc.verify)
				}
			}
			if tc.wantAbort != "" {
				uassert.AbortsContains(t, cur, tc.wantAbort, run)
			} else {
				uassert.NotAborts(t, cur, func() {
					if tc.force {
						v.ForceChannelOpenTry(0, cur, msg)
					} else if tc.public {
						v.ChannelOpenTry(0, cur, msg)
					} else {
						v.channelOpenTry(0, cur, msg, tc.verify)
					}
				})
			}
			uassert.Equal(t, tc.wantCalls, tc.lc.membershipCalls)
			_, ok := v.store.GetChannel(types.ChannelId(1))
			if tc.name == "public rejects inactive client" {
				// The inactive client must not have persisted a new channel.
				uassert.False(t, ok)
			} else {
				uassert.Equal(t, tc.wantSaved, ok)
			}
			uassert.Equal(t, tc.wantNotify, mApp.openTry)
		})
	}
}

func TestChannelOpenAck(cur realm, t *testing.T) {
	tests := []struct {
		name                  string
		lc                    *mockLightClient
		verify                bool
		public                bool
		force                 bool
		seedState             types.ChannelState
		counterpartyChannelId types.ChannelId
		counterpartyVersion   string
		missing               bool
		missingApp            bool
		wantAbort             string
		wantCalls             int
		wantOpen              bool
	}{
		{"verifies proof and opens init channel", &mockLightClient{}, true, false, false, types.ChannelStateInit, types.ChannelId(9), "counterparty-v1", false, false, "", 1, true},
		{"public moves init to open", &mockLightClient{}, true, true, false, types.ChannelStateInit, types.ChannelId(9), "v1", false, false, "", 1, true},
		{"force path skips proof verification", &mockLightClient{status: lightclient.Frozen}, false, false, false, types.ChannelStateInit, 0, "counterparty-v1", false, false, "", 0, true},
		{"force wrapper skips proof verification", &mockLightClient{status: lightclient.Frozen}, false, false, true, types.ChannelStateInit, types.ChannelId(123), "counterparty-v1", false, false, "", 0, true},
		{"missing app", &mockLightClient{}, true, true, false, types.ChannelStateInit, types.ChannelId(9), "v1", false, true, "port missing-port not found", 1, false},
		// Converted from Union channel_open_ack_not_found.
		// Union reference:
		// https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/core/src/tests/channel/ibc_channel.rs#L591-L650
		{"public missing channel aborts", &mockLightClient{}, true, true, false, types.ChannelStateInit, types.ChannelId(9), "v1", true, false, "channel 1 not found", 0, false},
		{"missing channel aborts", &mockLightClient{}, true, false, false, types.ChannelStateInit, types.ChannelId(9), "counterparty-v1", true, false, "channel 1 not found", 0, false},
		// TryOpen is the wrong state for an ack.
		{"public wrong state aborts", &mockLightClient{}, true, true, false, types.ChannelStateTryOpen, types.ChannelId(9), "v1", false, false, "invalid channel state", 0, false},
		{"wrong state aborts before proof", &mockLightClient{}, true, false, false, types.ChannelStateTryOpen, types.ChannelId(9), "counterparty-v1", false, false, "invalid channel state", 0, false},
		{"proof failure aborts", &mockLightClient{membershipErr: "bad proof"}, true, false, false, types.ChannelStateInit, types.ChannelId(9), "counterparty-v1", false, false, "bad proof", 1, false},
		// Local regression: Union MsgChannelOpenAck carries a concrete ChannelId, not an
		// Option, so the host must not reject a zero counterparty id before verification.
		// Force path (verify=false) so no proof is needed.
		{"force wrapper allows zero counterparty channel id", &mockLightClient{}, false, false, true, types.ChannelStateInit, 0, "v1", false, false, "", 0, true},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			v := newTestImpl()
			portId, mApp := setupChannelEnvWithLightClient(cur, v, tc.lc)
			if tc.missingApp {
				portId = types.Bytes("missing-port")
			}
			chId := types.ChannelId(1)
			if !tc.missing {
				v.store.CreateChannel(0, cur, chId, types.Channel{
					State:              tc.seedState,
					ConnectionId:       types.ConnectionId(1),
					CounterpartyPortId: types.Bytes("cp-port"),
					Version:            "v1",
				}, portId)
			}
			msg := types.MsgChannelOpenAck{
				ChannelId:             chId,
				CounterpartyChannelId: tc.counterpartyChannelId,
				CounterpartyVersion:   tc.counterpartyVersion,
				ProofHeight:           10,
				ProofTry:              []byte("proof"),
			}

			run := func(cur realm) {
				if tc.force {
					v.ForceChannelOpenAck(0, cur, msg)
				} else if tc.public {
					v.ChannelOpenAck(0, cur, msg)
				} else {
					v.channelOpenAck(0, cur, msg, tc.verify)
				}
			}
			if tc.wantAbort != "" {
				uassert.AbortsContains(t, cur, tc.wantAbort, run)
			} else {
				uassert.NotAborts(t, cur, func() {
					if tc.force {
						v.ForceChannelOpenAck(0, cur, msg)
					} else if tc.public {
						v.ChannelOpenAck(0, cur, msg)
					} else {
						v.channelOpenAck(0, cur, msg, tc.verify)
					}
				})
			}
			uassert.Equal(t, tc.wantCalls, tc.lc.membershipCalls)
			if tc.wantOpen {
				ch, _ := v.store.GetChannel(chId)
				uassert.True(t, ch.State == types.ChannelStateOpen)
				uassert.Equal(t, uint32(tc.counterpartyChannelId), uint32(ch.CounterpartyChannelId))
				uassert.Equal(t, tc.counterpartyVersion, ch.Version)
				uassert.Equal(t, 1, mApp.openAck)
				owner, _ := v.store.GetChannelOwner(chId)
				uassert.Equal(t, string(portId), string(owner))
			}
		})
	}
}

func TestChannelOpenConfirm(cur realm, t *testing.T) {
	tests := []struct {
		name                  string
		lc                    *mockLightClient
		verify                bool
		public                bool
		force                 bool
		seedState             types.ChannelState
		counterpartyChannelId types.ChannelId
		missing               bool
		missingApp            bool
		wantAbort             string
		wantCalls             int
		wantOpen              bool
	}{
		{"verifies proof and opens try-open channel", &mockLightClient{}, true, false, false, types.ChannelStateTryOpen, types.ChannelId(9), false, false, "", 1, true},
		{"public moves try-open to open", &mockLightClient{}, true, true, false, types.ChannelStateTryOpen, types.ChannelId(9), false, false, "", 1, true},
		{"force path skips proof verification", &mockLightClient{status: lightclient.Frozen}, false, false, false, types.ChannelStateTryOpen, types.ChannelId(9), false, false, "", 0, true},
		{"force wrapper skips proof verification", &mockLightClient{status: lightclient.Frozen}, false, false, true, types.ChannelStateTryOpen, types.ChannelId(123), false, false, "", 0, true},
		{"missing app", &mockLightClient{}, true, true, false, types.ChannelStateTryOpen, types.ChannelId(9), false, true, "port missing-port not found", 1, false},
		// Converted from Union channel_open_confirm_not_found.
		// Union reference:
		// https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/core/src/tests/channel/ibc_channel.rs#L879-L938
		{"public missing channel aborts", &mockLightClient{}, true, true, false, types.ChannelStateTryOpen, types.ChannelId(9), true, false, "channel 1 not found", 0, false},
		{"missing channel aborts", &mockLightClient{}, true, false, false, types.ChannelStateTryOpen, types.ChannelId(9), true, false, "channel 1 not found", 0, false},
		// A channel that is not in TryOpen must be rejected by ChannelOpenConfirm.
		// not TryOpen
		{"public wrong state aborts", &mockLightClient{}, true, true, false, types.ChannelStateOpen, types.ChannelId(9), false, false, "invalid channel state", 0, false},
		{"wrong state aborts before proof", &mockLightClient{}, true, false, false, types.ChannelStateOpen, types.ChannelId(9), false, false, "invalid channel state", 0, false},
		// Local regression for Gno's zero-as-None representation of Union
		// counterparty_channel_id: a TryOpen channel with a zero counterparty id must be
		// rejected before the membership proof is checked.
		{"public rejects invalid counterparty channel id", &mockLightClient{}, true, true, false, types.ChannelStateTryOpen, 0, false, false, "invalid counterparty channel id", 0, false},
		{"zero counterparty channel aborts before proof", &mockLightClient{}, true, false, false, types.ChannelStateTryOpen, 0, false, false, "invalid counterparty channel id", 0, false},
		{"proof failure aborts", &mockLightClient{membershipErr: "bad proof"}, true, false, false, types.ChannelStateTryOpen, types.ChannelId(9), false, false, "bad proof", 1, false},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			v := newTestImpl()
			portId, mApp := setupChannelEnvWithLightClient(cur, v, tc.lc)
			if tc.missingApp {
				portId = types.Bytes("missing-port")
			}
			chId := types.ChannelId(1)
			if !tc.missing {
				v.store.CreateChannel(0, cur, chId, types.Channel{
					State:                 tc.seedState,
					ConnectionId:          types.ConnectionId(1),
					CounterpartyChannelId: tc.counterpartyChannelId,
					CounterpartyPortId:    types.Bytes("cp-port"),
					Version:               "v1",
				}, portId)
			}
			msg := types.MsgChannelOpenConfirm{
				ChannelId:   chId,
				ProofHeight: 10,
				ProofAck:    []byte("proof"),
			}

			run := func(cur realm) {
				if tc.force {
					v.ForceChannelOpenConfirm(0, cur, msg)
				} else if tc.public {
					v.ChannelOpenConfirm(0, cur, msg)
				} else {
					v.channelOpenConfirm(0, cur, msg, tc.verify)
				}
			}
			if tc.wantAbort != "" {
				uassert.AbortsContains(t, cur, tc.wantAbort, run)
			} else {
				uassert.NotAborts(t, cur, func() {
					if tc.force {
						v.ForceChannelOpenConfirm(0, cur, msg)
					} else if tc.public {
						v.ChannelOpenConfirm(0, cur, msg)
					} else {
						v.channelOpenConfirm(0, cur, msg, tc.verify)
					}
				})
			}
			uassert.Equal(t, tc.wantCalls, tc.lc.membershipCalls)
			if tc.wantOpen {
				ch, _ := v.store.GetChannel(chId)
				uassert.True(t, ch.State == types.ChannelStateOpen)
				uassert.Equal(t, 1, mApp.openConfirm)
			}
		})
	}
}

func TestChannelCloseInit(cur realm, t *testing.T) {
	testCases := []struct {
		name   string
		want   string
		run    func(cur realm) (*coreV1, types.ChannelId, *mockApp)
		assert func(v *coreV1, chId types.ChannelId, mApp *mockApp)
	}{
		{
			name: "closes open channel",
			run: func(cur realm) (*coreV1, types.ChannelId, *mockApp) {
				v := newTestImpl()
				portId, mApp := setupChannelEnv(cur, v)
				// Open the channel: Init -> Ack -> Open.
				v.ChannelOpenInit(0, cur, types.MsgChannelOpenInit{PortId: portId, ConnectionId: types.ConnectionId(1), Version: "v1"})
				chId := v.store.(*mockStore).currentChannelId()
				v.ChannelOpenAck(0, cur, types.MsgChannelOpenAck{ChannelId: chId, CounterpartyChannelId: types.ChannelId(9), CounterpartyVersion: "v1", ProofHeight: 10, ProofTry: []byte("p")})

				v.ChannelCloseInit(0, cur, types.MsgChannelCloseInit{ChannelId: chId})
				return v, chId, mApp
			},
			assert: func(v *coreV1, chId types.ChannelId, mApp *mockApp) {
				ch, _ := v.store.GetChannel(chId)
				uassert.True(t, ch.State == types.ChannelStateClosed)
				uassert.Equal(t, 1, mApp.closeInit)
			},
		},
		{
			name: "missing channel",
			want: "channel 1 not found",
			run: func(cur realm) (*coreV1, types.ChannelId, *mockApp) {
				v := newTestImpl()
				v.ChannelCloseInit(0, cur, types.MsgChannelCloseInit{ChannelId: types.ChannelId(1)})
				return v, types.ChannelId(1), nil
			},
		},
		{
			name: "invalid counterparty channel",
			want: "invalid counterparty channel id",
			run: func(cur realm) (*coreV1, types.ChannelId, *mockApp) {
				v := newTestImpl()
				portId, _ := setupChannelEnv(cur, v)
				chId := v.store.NextChannelId(0, cur)
				v.store.CreateChannel(0, cur, chId, types.Channel{
					State:        types.ChannelStateOpen,
					ConnectionId: types.ConnectionId(1),
					Version:      "v1",
				}, portId)
				v.ChannelCloseInit(0, cur, types.MsgChannelCloseInit{ChannelId: chId})
				return v, chId, nil
			},
		},
		{
			name: "missing app",
			want: "port missing-port not found",
			run: func(cur realm) (*coreV1, types.ChannelId, *mockApp) {
				v := newTestImpl()
				ms := v.store.(*mockStore)
				clientId := createClient(cur, v, &mockLightClient{}, nil, nil)
				ms.SaveConnection(0, cur, types.ConnectionId(1),
					core.NewConnection(types.ConnectionStateOpen, clientId, types.ClientId(7), types.ConnectionId(2)))
				chId := v.store.NextChannelId(0, cur)
				v.store.CreateChannel(0, cur, chId, types.Channel{
					State:                 types.ChannelStateOpen,
					ConnectionId:          types.ConnectionId(1),
					CounterpartyChannelId: types.ChannelId(9),
					CounterpartyPortId:    types.Bytes("cp-port"),
					Version:               "v1",
				}, types.Bytes("missing-port"))
				v.ChannelCloseInit(0, cur, types.MsgChannelCloseInit{ChannelId: chId})
				return v, chId, nil
			},
		},
	}

	for _, tc := range testCases {
		t.Run(tc.name, func(t *testing.T) {
			run := func(cur realm) {
				tc.run(cur)
			}
			if tc.want != "" {
				uassert.AbortsContains(t, cur, tc.want, run)
			} else {
				var v *coreV1
				var chId types.ChannelId
				var mApp *mockApp
				uassert.NotAborts(t, cur, func() {
					v, chId, mApp = tc.run(cur)
				})
				tc.assert(v, chId, mApp)
			}
		})
	}
}

func TestChannelCloseConfirm(cur realm, t *testing.T) {
	testCases := []struct {
		name   string
		want   string
		run    func(cur realm) (*coreV1, types.ChannelId, *mockApp)
		assert func(v *coreV1, chId types.ChannelId, mApp *mockApp)
	}{
		{
			name: "closes open channel",
			run: func(cur realm) (*coreV1, types.ChannelId, *mockApp) {
				v := newTestImpl()
				portId, mApp := setupChannelEnv(cur, v)
				v.ChannelOpenInit(0, cur, types.MsgChannelOpenInit{PortId: portId, ConnectionId: types.ConnectionId(1), Version: "v1"})
				chId := v.store.(*mockStore).currentChannelId()
				v.ChannelOpenAck(0, cur, types.MsgChannelOpenAck{ChannelId: chId, CounterpartyChannelId: types.ChannelId(9), CounterpartyVersion: "v1", ProofHeight: 10, ProofTry: []byte("p")})

				v.ChannelCloseConfirm(0, cur, types.MsgChannelCloseConfirm{ChannelId: chId, ProofHeight: 12, ProofInit: []byte("proof")})
				return v, chId, mApp
			},
			assert: func(v *coreV1, chId types.ChannelId, mApp *mockApp) {
				ch, _ := v.store.GetChannel(chId)
				uassert.True(t, ch.State == types.ChannelStateClosed)
				uassert.Equal(t, 1, mApp.closeConfirm)
			},
		},
		{
			name: "missing channel",
			want: "channel 1 not found",
			run: func(cur realm) (*coreV1, types.ChannelId, *mockApp) {
				v := newTestImpl()
				v.ChannelCloseConfirm(0, cur, types.MsgChannelCloseConfirm{ChannelId: types.ChannelId(1), ProofHeight: 12, ProofInit: []byte("proof")})
				return v, types.ChannelId(1), nil
			},
		},
		{
			name: "wrong state",
			want: "invalid channel state",
			run: func(cur realm) (*coreV1, types.ChannelId, *mockApp) {
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
				return v, chId, nil
			},
		},
		{
			name: "invalid counterparty channel",
			want: "invalid counterparty channel id",
			run: func(cur realm) (*coreV1, types.ChannelId, *mockApp) {
				v := newTestImpl()
				portId, _ := setupChannelEnv(cur, v)
				chId := v.store.NextChannelId(0, cur)
				v.store.CreateChannel(0, cur, chId, types.Channel{
					State:        types.ChannelStateOpen,
					ConnectionId: types.ConnectionId(1),
					Version:      "v1",
				}, portId)
				v.ChannelCloseConfirm(0, cur, types.MsgChannelCloseConfirm{ChannelId: chId, ProofHeight: 12, ProofInit: []byte("proof")})
				return v, chId, nil
			},
		},
		{
			name: "proof failure",
			want: "bad close proof",
			run: func(cur realm) (*coreV1, types.ChannelId, *mockApp) {
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
				return v, chId, nil
			},
		},
		{
			name: "missing app",
			want: "port missing-port not found",
			run: func(cur realm) (*coreV1, types.ChannelId, *mockApp) {
				v := newTestImpl()
				ms := v.store.(*mockStore)
				clientId := createClient(cur, v, &mockLightClient{}, nil, nil)
				ms.SaveConnection(0, cur, types.ConnectionId(1),
					core.NewConnection(types.ConnectionStateOpen, clientId, types.ClientId(7), types.ConnectionId(2)))
				chId := v.store.NextChannelId(0, cur)
				v.store.CreateChannel(0, cur, chId, types.Channel{
					State:                 types.ChannelStateOpen,
					ConnectionId:          types.ConnectionId(1),
					CounterpartyChannelId: types.ChannelId(9),
					CounterpartyPortId:    types.Bytes("cp-port"),
					Version:               "v1",
				}, types.Bytes("missing-port"))
				v.ChannelCloseConfirm(0, cur, types.MsgChannelCloseConfirm{ChannelId: chId, ProofHeight: 12, ProofInit: []byte("proof")})
				return v, chId, nil
			},
		},
	}

	for _, tc := range testCases {
		t.Run(tc.name, func(t *testing.T) {
			run := func(cur realm) {
				tc.run(cur)
			}
			if tc.want != "" {
				uassert.AbortsContains(t, cur, tc.want, run)
			} else {
				var v *coreV1
				var chId types.ChannelId
				var mApp *mockApp
				uassert.NotAborts(t, cur, func() {
					v, chId, mApp = tc.run(cur)
				})
				tc.assert(v, chId, mApp)
			}
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

func TestClosedChannel(t *testing.T) {
	v := newTestImpl()
	original := types.Channel{
		State:                 types.ChannelStateOpen,
		ConnectionId:          types.ConnectionId(1),
		CounterpartyChannelId: types.ChannelId(9),
		CounterpartyPortId:    types.Bytes("cp-port"),
		Version:               "v1",
	}

	closed := v.closedChannel(original)

	uassert.True(t, closed.State == types.ChannelStateClosed)
	uassert.Equal(t, uint32(original.ConnectionId), uint32(closed.ConnectionId))
	uassert.Equal(t, uint32(original.CounterpartyChannelId), uint32(closed.CounterpartyChannelId))
	uassert.Equal(t, string(original.CounterpartyPortId), string(closed.CounterpartyPortId))
	uassert.Equal(t, original.Version, closed.Version)

	uassert.Equal(t, "cp-port", string(original.CounterpartyPortId))
}
