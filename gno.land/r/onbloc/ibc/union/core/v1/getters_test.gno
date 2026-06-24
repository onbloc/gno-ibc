package impl

import (
	"testing"

	"gno.land/p/nt/uassert/v0"
	"gno.land/p/onbloc/ibc/union/lightclient"
	"gno.land/p/onbloc/ibc/union/types"
	core "gno.land/r/onbloc/ibc/union/core"
)

func TestGetClientGetters(cur realm, t *testing.T) {
	v := newTestImpl()
	lc := &mockLightClient{latestHeight: 42, timestampAtHt: types.Timestamp(123)}
	clientId := createClient(cur, v, lc, nil, nil)
	v.UpdateClient(0, cur, types.MsgUpdateClient{
		ClientId:      clientId,
		ClientMessage: []byte("h"),
	})
	// UpdateClient with a zero-height update writes nothing; set state explicitly.
	v.store.SaveClientState(0, cur, clientId, []byte("client-state"))
	v.store.SaveConsensusState(0, cur, clientId, types.NewHeight(5), []byte("consensus-5"))

	gotLc, ok := v.GetLightClient(clientId)
	uassert.True(t, ok)
	uassert.True(t, gotLc == lc)
	uassert.True(t, v.GetRegisteredClientType(testClientType))
	uassert.False(t, v.GetRegisteredClientType(types.ClientType("missing")))

	status, err := v.GetStatus(clientId)
	uassert.NoError(t, err)
	uassert.True(t, status == types.StatusActive)

	typ, err := v.GetClientType(clientId)
	uassert.NoError(t, err)
	uassert.Equal(t, "cometbls", string(typ))

	implId, err := v.GetClientImpl(clientId)
	uassert.NoError(t, err)
	uassert.Equal(t, "cometbls", implId)

	cs, err := v.GetClientStateBytes(clientId)
	uassert.NoError(t, err)
	uassert.Equal(t, "client-state", string(cs))

	cons, err := v.GetConsensusStateBytes(clientId, types.NewHeight(5))
	uassert.NoError(t, err)
	uassert.Equal(t, "consensus-5", string(cons))

	h, err := v.GetLatestHeight(clientId)
	uassert.NoError(t, err)
	uassert.Equal(t, uint64(42), h)

	ts, err := v.GetTimestampAtHeight(clientId, 5)
	uassert.NoError(t, err)
	uassert.Equal(t, uint64(123), uint64(ts))
}

func TestGetMissingClient(cur realm, t *testing.T) {
	v := newTestImpl()

	cases := []struct {
		name string
		run  func() error
		want error
	}{
		{"status", func() error {
			_, err := v.GetStatus(types.ClientId(99))
			return err
		}, makeError(core.ErrClientNotFound)},
		{"client type", func() error {
			_, err := v.GetClientType(types.ClientId(99))
			return err
		}, makeError(core.ErrClientNotFound)},
		{"client impl", func() error {
			_, err := v.GetClientImpl(types.ClientId(99))
			return err
		}, makeError(core.ErrClientNotFound)},
		{"latest height", func() error {
			_, err := v.GetLatestHeight(types.ClientId(99))
			return err
		}, makeError(core.ErrClientNotFound)},
		{"timestamp at height", func() error {
			_, err := v.GetTimestampAtHeight(types.ClientId(99), 7)
			return err
		}, makeError(core.ErrClientNotFound)},
		{"client state", func() error {
			_, err := v.GetClientStateBytes(types.ClientId(99))
			return err
		}, makeError(core.ErrClientStateNotFound)},
		{"consensus state", func() error {
			_, err := v.GetConsensusStateBytes(types.ClientId(99), types.NewHeight(7))
			return err
		}, makeError(core.ErrConsensusStateNotFound)},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			uassert.ErrorIs(t, tc.run(), tc.want)
		})
	}

	_, ok := v.GetLightClient(types.ClientId(99))
	uassert.False(t, ok)
}

func TestGetTimestampAtHeightPropagatesClientError(cur realm, t *testing.T) {
	v := newTestImpl()
	clientId := createClient(cur, v, &mockLightClient{timestampErr: "height missing"}, nil, nil)

	_, err := v.GetTimestampAtHeight(clientId, 7)

	uassert.ErrorContains(t, err, "height missing")
}

func TestGetFrozenStatus(cur realm, t *testing.T) {
	v := newTestImpl()
	clientId := createClient(cur, v, &mockLightClient{status: lightclient.Frozen}, nil, nil)

	status, err := v.GetStatus(clientId)
	uassert.NoError(t, err)
	uassert.True(t, status == types.StatusFrozen)
}

func TestGetBestEffortGetters(cur realm, t *testing.T) {
	v := newTestImpl()
	ms := v.store.(*mockStore)
	ms.channels[1] = types.Channel{State: types.ChannelStateOpen, ConnectionId: types.ConnectionId(1)}
	ms.channels[2] = types.Channel{State: types.ChannelStateClosed, ConnectionId: types.ConnectionId(2)}

	channels, _ := v.GetChannels()
	uassert.Equal(t, 2, len(channels))
}

func TestGetConnectionAndChannel(cur realm, t *testing.T) {
	v := newTestImpl()
	ms := v.store.(*mockStore)
	ms.SaveConnection(0, cur, types.ConnectionId(1),
		core.NewConnection(types.ConnectionStateOpen, types.ClientId(1), types.ClientId(7), types.ConnectionId(2)))
	ms.channels[3] = types.Channel{State: types.ChannelStateOpen, ConnectionId: types.ConnectionId(1)}

	conn, err := v.GetConnection(types.ConnectionId(1))
	uassert.NoError(t, err)
	uassert.True(t, conn.State == types.ConnectionStateOpen)

	ch, err := v.GetChannel(types.ChannelId(3))
	uassert.NoError(t, err)
	uassert.True(t, ch.State == types.ChannelStateOpen)

	_, err = v.GetConnection(types.ConnectionId(99))
	uassert.ErrorIs(t, err, makeError(core.ErrConnectionNotFound))

	_, err = v.GetChannel(types.ChannelId(99))
	uassert.ErrorIs(t, err, makeError(core.ErrChannelNotFound))
}

func TestGetBatchCommitmentGetters(cur realm, t *testing.T) {
	v := newTestImpl()
	ms := v.store.(*mockStore)
	packetHash := types.Keccak([]byte("batch-packets"))
	receiptHash := types.Keccak([]byte("batch-receipts"))
	packetValue := types.Keccak([]byte("packet-value"))
	receiptValue := types.Keccak([]byte("receipt-value"))

	cases := []struct {
		name      string
		seed      func()
		run       func() (types.H256, error)
		want      types.H256
		wantError error
	}{
		{
			name: "batch packets",
			seed: func() {
				ms.SaveBatchPackets(0, cur, types.ChannelId(1), packetHash, packetValue)
			},
			run:  func() (types.H256, error) { return v.GetBatchPacketsCommitment(packetHash) },
			want: packetValue,
		},
		{
			name:      "missing batch packets",
			run:       func() (types.H256, error) { return v.GetBatchPacketsCommitment(packetHash) },
			wantError: makeError(core.ErrBatchPacketsNotFound),
		},
		{
			name: "batch receipts",
			seed: func() {
				ms.SaveBatchReceipts(0, cur, types.ChannelId(1), receiptHash, receiptValue)
			},
			run:  func() (types.H256, error) { return v.GetBatchReceiptsCommitment(receiptHash) },
			want: receiptValue,
		},
		{
			name:      "missing batch receipts",
			run:       func() (types.H256, error) { return v.GetBatchReceiptsCommitment(receiptHash) },
			wantError: makeError(core.ErrBatchReceiptsNotFound),
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			v = newTestImpl()
			ms = v.store.(*mockStore)
			if tc.seed != nil {
				tc.seed()
			}

			got, err := tc.run()
			if tc.wantError != nil {
				uassert.ErrorIs(t, err, tc.wantError)
				return
			}
			uassert.NoError(t, err)
			uassert.True(t, got == tc.want)
		})
	}
}

func TestGetCommittedProofGetters(cur realm, t *testing.T) {
	v := newTestImpl()
	clientId := types.ClientId(7)
	path := types.Bytes("clients/7/consensusStates/11")
	value := types.Keccak(types.Bytes("consensus-state"))
	v.store.SaveMembershipProof(0, cur, clientId, 10, path, value)
	v.store.SaveNonMembershipProof(0, cur, clientId, 10, path, types.NON_MEMBERSHIP_COMMITMENT_VALUE)

	got, err := v.GetCommittedMembershipProofCommitment(clientId, 10, path)
	uassert.NoError(t, err)
	uassert.Equal(t, value.String(), got.String())
	uassert.True(t, v.GetCommittedNonMembershipProof(clientId, 10, path))

	_, err = v.GetCommittedMembershipProofCommitment(clientId, 11, path)
	uassert.ErrorIs(t, err, makeError(core.ErrMembershipProofNotFound))
	uassert.False(t, v.GetCommittedNonMembershipProof(clientId, 11, path))
}
