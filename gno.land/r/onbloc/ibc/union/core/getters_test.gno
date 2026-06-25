package core

import (
	"testing"

	"gno.land/p/nt/uassert/v0"
	"gno.land/p/onbloc/ibc/union/lightclient"
	"gno.land/p/onbloc/ibc/union/types"
)

type rootGetterImpl struct {
	ICore
	lc        lightclient.Interface
	packet    types.H256
	receipt   types.H256
	proof     types.H256
	conn      types.Connection
	channel   types.Channel
	channels  []types.Channel
	clientErr error
}

func newRootGetterImpl() *rootGetterImpl {
	return &rootGetterImpl{
		lc:       &mockClient{status: types.StatusActive, height: types.NewHeight(0, 77), timestamp: types.Timestamp(123)},
		packet:   types.Keccak([]byte("packet-commitment")),
		receipt:  types.Keccak([]byte("receipt-commitment")),
		proof:    types.Keccak([]byte("membership-proof")),
		conn:     NewConnection(types.ConnectionStateOpen, types.ClientId(7), types.ClientId(8), types.ConnectionId(9)),
		channel:  NewChannel(types.ChannelStateOpen, types.ConnectionId(1), types.ChannelId(9), types.Bytes("counterparty"), "v1"),
		channels: []types.Channel{NewChannel(types.ChannelStateOpen, types.ConnectionId(1), types.ChannelId(9), types.Bytes("counterparty"), "v1")},
	}
}

func (i *rootGetterImpl) HasClient(typ types.ClientType) bool {
	return typ == mockType
}

func (i *rootGetterImpl) GetStatus(clientId types.ClientId) (types.Status, error) {
	if clientId != 7 {
		return types.StatusUnknown, makeError(ErrClientNotFound)
	}
	return types.StatusActive, nil
}

func (i *rootGetterImpl) GetLightClient(clientId types.ClientId) (lightclient.Interface, bool) {
	if clientId != 7 {
		return nil, false
	}
	return i.lc, true
}

func (i *rootGetterImpl) GetClientType(clientId types.ClientId) (types.ClientType, error) {
	if clientId != 7 {
		return "", makeError(ErrClientNotFound)
	}
	return mockType, nil
}

func (i *rootGetterImpl) GetClientImpl(clientId types.ClientId) (string, error) {
	if clientId != 7 {
		return "", makeError(ErrClientNotFound)
	}
	return mockType.String(), nil
}

func (i *rootGetterImpl) GetRegisteredClientType(typ types.ClientType) bool {
	return typ == mockType
}

func (i *rootGetterImpl) GetClientStateBytes(clientId types.ClientId) ([]byte, error) {
	if clientId != 7 {
		return nil, makeError(ErrClientStateNotFound)
	}
	return []byte("client-state"), nil
}

func (i *rootGetterImpl) GetConsensusStateBytes(clientId types.ClientId, height types.Height) ([]byte, error) {
	if clientId != 7 || height.RevisionHeight != 11 {
		return nil, makeError(ErrConsensusStateNotFound)
	}
	return []byte("consensus-state"), nil
}

func (i *rootGetterImpl) GetLatestHeight(clientId types.ClientId) (uint64, error) {
	if clientId != 7 {
		return 0, makeError(ErrClientNotFound)
	}
	return 77, nil
}

func (i *rootGetterImpl) GetTimestampAtHeight(clientId types.ClientId, height uint64) (types.Timestamp, error) {
	if clientId != 7 || height != 11 {
		return 0, makeError(ErrConsensusStateNotFound)
	}
	return types.Timestamp(123), nil
}

func (i *rootGetterImpl) GetConnection(connectionId types.ConnectionId) (types.Connection, error) {
	if connectionId != 3 {
		return types.Connection{}, makeError(ErrConnectionNotFound)
	}
	return i.conn, nil
}

func (i *rootGetterImpl) GetChannels() ([]types.Channel, error) {
	return i.channels, nil
}

func (i *rootGetterImpl) GetChannel(channelId types.ChannelId) (types.Channel, error) {
	if channelId != 4 {
		return types.Channel{}, makeError(ErrChannelNotFound)
	}
	return i.channel, nil
}

func (i *rootGetterImpl) GetBatchPacketsCommitment(batchHash types.H256) (types.H256, error) {
	if batchHash != types.Keccak([]byte("batch-packets")) {
		return types.H256{}, makeError(ErrBatchPacketsNotFound)
	}
	return i.packet, nil
}

func (i *rootGetterImpl) GetBatchReceiptsCommitment(batchHash types.H256) (types.H256, error) {
	if batchHash != types.Keccak([]byte("batch-receipts")) {
		return types.H256{}, makeError(ErrBatchReceiptsNotFound)
	}
	return i.receipt, nil
}

func (i *rootGetterImpl) GetCommittedMembershipProofCommitment(clientId types.ClientId, proofHeight uint64, path []byte) (types.H256, error) {
	if clientId != 7 || proofHeight != 11 || string(path) != "path" {
		return types.H256{}, makeError(ErrMembershipProofNotFound)
	}
	return i.proof, nil
}

func (i *rootGetterImpl) GetCommittedNonMembershipProof(clientId types.ClientId, proofHeight uint64, path []byte) bool {
	return clientId == 7 && proofHeight == 11 && string(path) == "path"
}

func TestRootClientPresenceWrappers(cur realm, t *testing.T) {
	resetImplForTest(cur)
	currentImpl = newRootGetterImpl()

	cases := []struct {
		name string
		run  func() bool
		want bool
	}{
		{"has client true", func() bool { return HasClient(mockType) }, true},
		{"has client false", func() bool { return HasClient(types.ClientType("missing")) }, false},
		{"registered client true", func() bool { return GetRegisteredClientType(mockType) }, true},
		{"registered client false", func() bool { return GetRegisteredClientType(types.ClientType("missing")) }, false},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			uassert.Equal(t, tc.want, tc.run())
		})
	}
}

func TestRootScalarGetterWrappers(cur realm, t *testing.T) {
	resetImplForTest(cur)
	currentImpl = newRootGetterImpl()

	cases := []struct {
		name      string
		run       func() (string, error)
		want      string
		wantError string
	}{
		{"status", func() (string, error) {
			got, err := GetStatus(types.ClientId(7))
			return types.Height{RevisionHeight: uint64(got)}.String(), err
		}, types.Height{RevisionHeight: uint64(types.StatusActive)}.String(), ""},
		{"status missing", func() (string, error) {
			got, err := GetStatus(types.ClientId(8))
			return types.Height{RevisionHeight: uint64(got)}.String(), err
		}, "", ErrClientNotFound},
		{"client type", func() (string, error) {
			got, err := GetClientType(types.ClientId(7))
			return got.String(), err
		}, mockType.String(), ""},
		{"client type missing", func() (string, error) {
			got, err := GetClientType(types.ClientId(8))
			return got.String(), err
		}, "", ErrClientNotFound},
		{"client impl", func() (string, error) {
			return GetClientImpl(types.ClientId(7))
		}, mockType.String(), ""},
		{"client impl missing", func() (string, error) {
			return GetClientImpl(types.ClientId(8))
		}, "", ErrClientNotFound},
		{"latest height", func() (string, error) {
			got, err := GetLatestHeight(types.ClientId(7))
			return types.NewHeight(0, got).String(), err
		}, types.NewHeight(0, 77).String(), ""},
		{"latest height missing", func() (string, error) {
			got, err := GetLatestHeight(types.ClientId(8))
			return types.NewHeight(0, got).String(), err
		}, "", ErrClientNotFound},
		{"timestamp", func() (string, error) {
			got, err := GetTimestampAtHeight(types.ClientId(7), 11)
			return got.String(), err
		}, types.Timestamp(123).String(), ""},
		{"timestamp missing", func() (string, error) {
			got, err := GetTimestampAtHeight(types.ClientId(7), 12)
			return got.String(), err
		}, "", ErrConsensusStateNotFound},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got, err := tc.run()
			if tc.wantError != "" {
				uassert.ErrorContains(t, err, tc.wantError)
				return
			}
			uassert.NoError(t, err)
			uassert.Equal(t, tc.want, got)
		})
	}
}

func TestRootByteGetterWrappers(cur realm, t *testing.T) {
	resetImplForTest(cur)
	currentImpl = newRootGetterImpl()

	cases := []struct {
		name      string
		run       func() ([]byte, error)
		want      string
		wantError string
	}{
		{"client state", func() ([]byte, error) {
			return GetClientState(types.ClientId(7))
		}, "client-state", ""},
		{"client state missing", func() ([]byte, error) {
			return GetClientState(types.ClientId(8))
		}, "", ErrClientStateNotFound},
		{"consensus state", func() ([]byte, error) {
			return GetConsensusState(types.ClientId(7), types.NewHeight(0, 11))
		}, "consensus-state", ""},
		{"consensus state missing", func() ([]byte, error) {
			return GetConsensusState(types.ClientId(7), types.NewHeight(0, 12))
		}, "", ErrConsensusStateNotFound},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got, err := tc.run()
			if tc.wantError != "" {
				uassert.ErrorContains(t, err, tc.wantError)
				return
			}
			uassert.NoError(t, err)
			uassert.Equal(t, tc.want, string(got))
		})
	}
}

func TestRootObjectGetterWrappers(cur realm, t *testing.T) {
	resetImplForTest(cur)
	impl := newRootGetterImpl()
	currentImpl = impl

	lc, ok := GetLightClient(types.ClientId(7))
	uassert.True(t, ok)
	uassert.True(t, lc == impl.lc)
	_, ok = GetLightClient(types.ClientId(8))
	uassert.False(t, ok)

	conn, err := GetConnection(types.ConnectionId(3))
	uassert.NoError(t, err)
	uassert.True(t, conn.State == types.ConnectionStateOpen)
	_, err = GetConnection(types.ConnectionId(99))
	uassert.ErrorContains(t, err, ErrConnectionNotFound)

	channels, err := GetChannels()
	uassert.NoError(t, err)
	uassert.Equal(t, 1, len(channels))

	channel, err := GetChannel(types.ChannelId(4))
	uassert.NoError(t, err)
	uassert.True(t, channel.State == types.ChannelStateOpen)
	_, err = GetChannel(types.ChannelId(99))
	uassert.ErrorContains(t, err, ErrChannelNotFound)
}

func TestRootCommitmentGetterWrappers(cur realm, t *testing.T) {
	resetImplForTest(cur)
	impl := newRootGetterImpl()
	currentImpl = impl

	cases := []struct {
		name      string
		run       func() (types.H256, error)
		want      types.H256
		wantError string
	}{
		{"batch packets", func() (types.H256, error) {
			return GetBatchPackets(types.Keccak([]byte("batch-packets")))
		}, impl.packet, ""},
		{"batch packets missing", func() (types.H256, error) {
			return GetBatchPackets(types.Keccak([]byte("missing")))
		}, types.H256{}, ErrBatchPacketsNotFound},
		{"batch receipts", func() (types.H256, error) {
			return GetBatchReceipts(types.Keccak([]byte("batch-receipts")))
		}, impl.receipt, ""},
		{"batch receipts missing", func() (types.H256, error) {
			return GetBatchReceipts(types.Keccak([]byte("missing")))
		}, types.H256{}, ErrBatchReceiptsNotFound},
		{"membership proof", func() (types.H256, error) {
			return GetCommittedMembershipProof(types.ClientId(7), 11, []byte("path"))
		}, impl.proof, ""},
		{"membership proof missing", func() (types.H256, error) {
			return GetCommittedMembershipProof(types.ClientId(7), 12, []byte("path"))
		}, types.H256{}, ErrMembershipProofNotFound},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got, err := tc.run()
			if tc.wantError != "" {
				uassert.ErrorContains(t, err, tc.wantError)
				return
			}
			uassert.NoError(t, err)
			uassert.True(t, got == tc.want)
		})
	}

	uassert.True(t, GetCommittedNonMembershipProof(types.ClientId(7), 11, []byte("path")))
	uassert.False(t, GetCommittedNonMembershipProof(types.ClientId(7), 12, []byte("path")))
}
