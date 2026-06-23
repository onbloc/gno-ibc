package impl

import (
	"testing"

	"gno.land/p/nt/uassert/v0"
	"gno.land/p/onbloc/ibc/union/lightclient"
	"gno.land/p/onbloc/ibc/union/types"
	core "gno.land/r/onbloc/ibc/union/core"
)

func setupGetterClient(cur realm, v *coreV1, lc *mockLightClient) types.ClientId {
	clientId := createClient(cur, v, lc, nil, nil)
	v.store.SaveClientState(0, cur, clientId, []byte("client-state"))
	v.store.SaveConsensusState(0, cur, clientId, types.NewHeight(5), []byte("consensus-5"))
	return clientId
}

func TestGetStatus(cur realm, t *testing.T) {
	testCases := []struct {
		name    string
		status  lightclient.Status
		missing bool
		want    types.Status
		wantErr error
	}{
		{"active client", lightclient.Active, false, types.StatusActive, nil},
		{"frozen client", lightclient.Frozen, false, types.StatusFrozen, nil},
		{"missing client", "", true, types.StatusUnknown, core.ErrClientNotFound},
	}

	for _, tc := range testCases {
		t.Run(tc.name, func(t *testing.T) {
			v := newTestImpl()
			clientId := types.ClientId(99)
			if !tc.missing {
				clientId = setupGetterClient(cur, v, &mockLightClient{status: tc.status})
			}

			got, err := v.GetStatus(clientId)
			if tc.wantErr != nil {
				uassert.ErrorIs(t, err, tc.wantErr)
				return
			}
			uassert.NoError(t, err)
			uassert.True(t, got == tc.want)
		})
	}
}

func TestGetClientType(cur realm, t *testing.T) {
	testCases := []struct {
		name    string
		missing bool
		want    types.ClientType
		wantErr error
	}{
		{"registered client", false, types.ClientType("cometbls"), nil},
		{"missing client", true, "", core.ErrClientNotFound},
	}

	for _, tc := range testCases {
		t.Run(tc.name, func(t *testing.T) {
			v := newTestImpl()
			clientId := types.ClientId(99)
			if !tc.missing {
				clientId = setupGetterClient(cur, v, &mockLightClient{})
			}

			got, err := v.GetClientType(clientId)
			if tc.wantErr != nil {
				uassert.ErrorIs(t, err, tc.wantErr)
				return
			}
			uassert.NoError(t, err)
			uassert.Equal(t, string(tc.want), string(got))
		})
	}
}

func TestGetClientImpl(cur realm, t *testing.T) {
	testCases := []struct {
		name    string
		missing bool
		want    string
		wantErr error
	}{
		{"registered client", false, "cometbls", nil},
		{"missing client", true, "", core.ErrClientNotFound},
	}

	for _, tc := range testCases {
		t.Run(tc.name, func(t *testing.T) {
			v := newTestImpl()
			clientId := types.ClientId(99)
			if !tc.missing {
				clientId = setupGetterClient(cur, v, &mockLightClient{})
			}

			got, err := v.GetClientImpl(clientId)
			if tc.wantErr != nil {
				uassert.ErrorIs(t, err, tc.wantErr)
				return
			}
			uassert.NoError(t, err)
			uassert.Equal(t, tc.want, got)
		})
	}
}

func TestGetRegisteredClientType(t *testing.T) {
	testCases := []struct {
		name       string
		clientType types.ClientType
		want       bool
	}{
		// gno has no client-type registry.
		{"known-looking client type", types.ClientType("cometbls"), false},
		{"empty client type", "", false},
	}

	v := newTestImpl()
	for _, tc := range testCases {
		t.Run(tc.name, func(t *testing.T) {
			uassert.Equal(t, tc.want, v.GetRegisteredClientType(tc.clientType))
		})
	}
}

func TestGetClientStateBytes(cur realm, t *testing.T) {
	testCases := []struct {
		name    string
		setup   func(*coreV1) types.ClientId
		want    string
		wantErr error
	}{
		{
			"stored client state",
			func(v *coreV1) types.ClientId {
				return setupGetterClient(cur, v, &mockLightClient{})
			},
			"client-state",
			nil,
		},
		{
			"missing client state",
			func(v *coreV1) types.ClientId {
				return types.ClientId(99)
			},
			"",
			core.ErrClientStateNotFound,
		},
	}

	for _, tc := range testCases {
		t.Run(tc.name, func(t *testing.T) {
			v := newTestImpl()
			clientId := tc.setup(v)

			got, err := v.GetClientStateBytes(clientId)
			if tc.wantErr != nil {
				uassert.ErrorIs(t, err, tc.wantErr)
				return
			}
			uassert.NoError(t, err)
			uassert.Equal(t, tc.want, string(got))
		})
	}
}

func TestGetConsensusStateBytes(cur realm, t *testing.T) {
	testCases := []struct {
		name    string
		setup   func(*coreV1) (types.ClientId, types.Height)
		want    string
		wantErr error
	}{
		{
			"stored consensus state",
			func(v *coreV1) (types.ClientId, types.Height) {
				return setupGetterClient(cur, v, &mockLightClient{}), types.NewHeight(5)
			},
			"consensus-5",
			nil,
		},
		{
			"missing height",
			func(v *coreV1) (types.ClientId, types.Height) {
				return setupGetterClient(cur, v, &mockLightClient{}), types.NewHeight(6)
			},
			"",
			core.ErrConsensusStateNotFound,
		},
		{
			"missing client",
			func(v *coreV1) (types.ClientId, types.Height) {
				return types.ClientId(99), types.NewHeight(5)
			},
			"",
			core.ErrConsensusStateNotFound,
		},
	}

	for _, tc := range testCases {
		t.Run(tc.name, func(t *testing.T) {
			v := newTestImpl()
			clientId, height := tc.setup(v)

			got, err := v.GetConsensusStateBytes(clientId, height)
			if tc.wantErr != nil {
				uassert.ErrorIs(t, err, tc.wantErr)
				return
			}
			uassert.NoError(t, err)
			uassert.Equal(t, tc.want, string(got))
		})
	}
}

func TestGetLatestHeight(cur realm, t *testing.T) {
	testCases := []struct {
		name    string
		missing bool
		want    uint64
		wantErr error
	}{
		{"stored light client", false, 42, nil},
		{"missing client", true, 0, core.ErrClientNotFound},
	}

	for _, tc := range testCases {
		t.Run(tc.name, func(t *testing.T) {
			v := newTestImpl()
			clientId := types.ClientId(99)
			if !tc.missing {
				clientId = setupGetterClient(cur, v, &mockLightClient{latestHeight: tc.want})
			}

			got, err := v.GetLatestHeight(clientId)
			if tc.wantErr != nil {
				uassert.ErrorIs(t, err, tc.wantErr)
				return
			}
			uassert.NoError(t, err)
			uassert.Equal(t, tc.want, got)
		})
	}
}

func TestGetTimestampAtHeight(cur realm, t *testing.T) {
	testCases := []struct {
		name       string
		missing    bool
		timestamp  types.Timestamp
		lcErr      string
		want       types.Timestamp
		wantErr    error
		wantErrMsg string
	}{
		{"stored light client timestamp", false, types.Timestamp(123), "", types.Timestamp(123), nil, ""},
		{"missing client", true, 0, "", 0, core.ErrClientNotFound, ""},
		{"light client error", false, 0, "missing timestamp", 0, nil, "missing timestamp"},
	}

	for _, tc := range testCases {
		t.Run(tc.name, func(t *testing.T) {
			v := newTestImpl()
			clientId := types.ClientId(99)
			if !tc.missing {
				clientId = setupGetterClient(cur, v, &mockLightClient{
					timestampAtHt: tc.timestamp,
					timestampErr:  tc.lcErr,
				})
			}

			got, err := v.GetTimestampAtHeight(clientId, 5)
			if tc.wantErr != nil {
				uassert.ErrorIs(t, err, tc.wantErr)
				return
			}
			if tc.wantErrMsg != "" {
				uassert.ErrorContains(t, err, tc.wantErrMsg)
				return
			}
			uassert.NoError(t, err)
			uassert.Equal(t, uint64(tc.want), uint64(got))
		})
	}
}

func TestGetConnection(cur realm, t *testing.T) {
	testCases := []struct {
		name    string
		setup   func(*coreV1)
		id      types.ConnectionId
		want    types.ConnectionState
		wantErr error
	}{
		{
			"stored connection",
			func(v *coreV1) {
				v.store.SaveConnection(0, cur, types.ConnectionId(1),
					core.NewConnection(types.ConnectionStateOpen, types.ClientId(1), types.ClientId(7), types.ConnectionId(2)))
			},
			types.ConnectionId(1),
			types.ConnectionStateOpen,
			nil,
		},
		{
			"missing connection",
			func(v *coreV1) {},
			types.ConnectionId(99),
			types.ConnectionStateUnknown,
			core.ErrConnectionNotFound,
		},
	}

	for _, tc := range testCases {
		t.Run(tc.name, func(t *testing.T) {
			v := newTestImpl()
			tc.setup(v)

			got, err := v.GetConnection(tc.id)
			if tc.wantErr != nil {
				uassert.ErrorIs(t, err, tc.wantErr)
				return
			}
			uassert.NoError(t, err)
			uassert.True(t, got.State == tc.want)
		})
	}
}

func TestGetChannels(t *testing.T) {
	testCases := []struct {
		name       string
		setup      func(*mockStore)
		wantCount  int
		wantOpen   int
		wantClosed int
	}{
		{
			"empty store",
			func(ms *mockStore) {},
			0,
			0,
			0,
		},
		{
			"stored channels",
			func(ms *mockStore) {
				ms.channels[1] = types.Channel{State: types.ChannelStateOpen, ConnectionId: types.ConnectionId(1)}
				ms.channels[2] = types.Channel{State: types.ChannelStateClosed, ConnectionId: types.ConnectionId(1)}
			},
			2,
			1,
			1,
		},
	}

	for _, tc := range testCases {
		t.Run(tc.name, func(t *testing.T) {
			v := newTestImpl()
			ms := v.store.(*mockStore)
			tc.setup(ms)

			got, err := v.GetChannels()
			uassert.NoError(t, err)
			uassert.Equal(t, tc.wantCount, len(got))

			openCount := 0
			closedCount := 0
			for _, ch := range got {
				if ch.State == types.ChannelStateOpen {
					openCount++
				}
				if ch.State == types.ChannelStateClosed {
					closedCount++
				}
			}
			uassert.Equal(t, tc.wantOpen, openCount)
			uassert.Equal(t, tc.wantClosed, closedCount)
		})
	}
}

func TestGetChannel(t *testing.T) {
	testCases := []struct {
		name    string
		setup   func(*mockStore)
		id      types.ChannelId
		want    types.ChannelState
		wantErr error
	}{
		{
			"stored channel",
			func(ms *mockStore) {
				ms.channels[3] = types.Channel{State: types.ChannelStateOpen, ConnectionId: types.ConnectionId(1)}
			},
			types.ChannelId(3),
			types.ChannelStateOpen,
			nil,
		},
		{
			"missing channel",
			func(ms *mockStore) {},
			types.ChannelId(99),
			types.ChannelStateUnknown,
			core.ErrChannelNotFound,
		},
	}

	for _, tc := range testCases {
		t.Run(tc.name, func(t *testing.T) {
			v := newTestImpl()
			ms := v.store.(*mockStore)
			tc.setup(ms)

			got, err := v.GetChannel(tc.id)
			if tc.wantErr != nil {
				uassert.ErrorIs(t, err, tc.wantErr)
				return
			}
			uassert.NoError(t, err)
			uassert.True(t, got.State == tc.want)
		})
	}
}

func TestGetBatchPacketsCommitment(cur realm, t *testing.T) {
	testCases := []struct {
		name    string
		setup   func(*coreV1, types.H256) types.H256
		wantErr error
	}{
		{
			"stored batch packets commitment",
			func(v *coreV1, batchHash types.H256) types.H256 {
				value := types.Keccak([]byte("packets"))
				v.store.SaveBatchPackets(0, cur, types.ChannelId(7), batchHash, value)
				return value
			},
			nil,
		},
		{
			"missing batch packets commitment",
			func(v *coreV1, batchHash types.H256) types.H256 {
				return types.H256{}
			},
			core.ErrBatchPacketsNotFound,
		},
	}

	for _, tc := range testCases {
		t.Run(tc.name, func(t *testing.T) {
			v := newTestImpl()
			batchHash := types.Keccak([]byte(tc.name))
			want := tc.setup(v, batchHash)

			got, err := v.GetBatchPacketsCommitment(batchHash)
			if tc.wantErr != nil {
				uassert.ErrorIs(t, err, tc.wantErr)
				return
			}
			uassert.NoError(t, err)
			uassert.True(t, got == want)
		})
	}
}

func TestGetBatchReceiptsCommitment(cur realm, t *testing.T) {
	testCases := []struct {
		name    string
		setup   func(*coreV1, types.H256) types.H256
		wantErr error
	}{
		{
			"stored batch receipts commitment",
			func(v *coreV1, batchHash types.H256) types.H256 {
				value := types.Keccak([]byte("receipts"))
				v.store.SaveBatchReceipts(0, cur, types.ChannelId(7), batchHash, value)
				return value
			},
			nil,
		},
		{
			"missing batch receipts commitment",
			func(v *coreV1, batchHash types.H256) types.H256 {
				return types.H256{}
			},
			core.ErrBatchReceiptsNotFound,
		},
	}

	for _, tc := range testCases {
		t.Run(tc.name, func(t *testing.T) {
			v := newTestImpl()
			batchHash := types.Keccak([]byte(tc.name))
			want := tc.setup(v, batchHash)

			got, err := v.GetBatchReceiptsCommitment(batchHash)
			if tc.wantErr != nil {
				uassert.ErrorIs(t, err, tc.wantErr)
				return
			}
			uassert.NoError(t, err)
			uassert.True(t, got == want)
		})
	}
}
