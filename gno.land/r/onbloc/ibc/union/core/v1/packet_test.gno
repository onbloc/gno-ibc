package impl

import (
	"testing"

	"gno.land/p/nt/uassert/v0"
	"gno.land/p/onbloc/ibc/union/types"
	core "gno.land/r/onbloc/ibc/union/core"
)

const farFuture = types.Timestamp(1 << 62)

// setupOpenChannel seeds a client + open connection, registers an app at the
// caller's own port, and opens a channel (id 1) owned by that port.
func setupOpenChannel(cur realm, v *coreV1) (types.ChannelId, types.Bytes, *mockApp) {
	return setupOpenChannelWithLightClient(cur, v, &mockLightClient{timestampAtHt: farFuture})
}

func setupOpenChannelWithLightClient(cur realm, v *coreV1, lc *mockLightClient) (types.ChannelId, types.Bytes, *mockApp) {
	ms := v.store.(*mockStore)
	clientId := createClient(cur, v, lc, nil, nil)
	ms.SaveConnection(0, cur, types.ConnectionId(1),
		core.NewConnection(types.ConnectionStateOpen, clientId, types.ClientId(7), types.ConnectionId(2)))
	port := types.Bytes(cur.Previous().PkgPath())
	mApp := &mockApp{}
	ms.registerApp(port, mApp)
	v.ChannelOpenInit(0, cur, types.MsgChannelOpenInit{PortId: port, ConnectionId: types.ConnectionId(1), Version: "v1"})
	chId := v.store.(*mockStore).currentChannelId()
	v.ChannelOpenAck(0, cur, types.MsgChannelOpenAck{ChannelId: chId, CounterpartyChannelId: types.ChannelId(9), CounterpartyVersion: "v1", ProofHeight: 10, ProofTry: []byte("p")})
	return chId, port, mApp
}

func recvPacket(chId types.ChannelId, data string) types.Packet {
	return types.Packet{
		SourceChannelId:      types.ChannelId(9),
		DestinationChannelId: chId,
		Data:                 []byte(data),
		TimeoutTimestamp:     farFuture,
	}
}

func setupOpenChannelWithoutApp(cur realm, v *coreV1, portId types.Bytes) types.ChannelId {
	ms := v.store.(*mockStore)
	clientId := createClient(cur, v, &mockLightClient{timestampAtHt: farFuture}, nil, nil)
	ms.SaveConnection(0, cur, types.ConnectionId(1),
		core.NewConnection(types.ConnectionStateOpen, clientId, types.ClientId(7), types.ConnectionId(2)))
	chId := v.store.NextChannelId(0, cur)
	v.store.CreateChannel(0, cur, chId, types.Channel{
		State:                 types.ChannelStateOpen,
		ConnectionId:          types.ConnectionId(1),
		CounterpartyChannelId: types.ChannelId(9),
		Version:               "v1",
	}, portId)
	return chId
}

func TestSendPacketCommits(cur realm, t *testing.T) {
	v := newTestImpl()
	chId, _, _ := setupOpenChannel(cur, v)

	packet := v.SendPacket(0, cur, chId, types.Timestamp(1000), []byte("data"))

	uassert.Equal(t, uint32(chId), uint32(packet.SourceChannelId))
	uassert.Equal(t, uint32(9), uint32(packet.DestinationChannelId))
	uassert.True(t, v.store.HasPacketCommitment(packet))
}

func TestSendPacketTimeoutMustBeSet(cur realm, t *testing.T) {
	v := newTestImpl()
	chId, _, _ := setupOpenChannel(cur, v)

	uassert.AbortsContains(t, cur, "timeout must be set", func(cur realm) {
		v.SendPacket(0, cur, chId, types.Timestamp(0), []byte("data"))
	})
}

func TestSendPacketUnauthorizedSender(cur realm, t *testing.T) {
	v := newTestImpl()
	ms := v.store.(*mockStore)
	clientId := createClient(cur, v, &mockLightClient{}, nil, nil)
	ms.SaveConnection(0, cur, types.ConnectionId(1),
		core.NewConnection(types.ConnectionStateOpen, clientId, types.ClientId(7), types.ConnectionId(2)))
	// Channel owned by a port other than the caller.
	other := types.Bytes("other-port")
	ms.registerApp(other, &mockApp{})
	v.ChannelOpenInit(0, cur, types.MsgChannelOpenInit{PortId: other, ConnectionId: types.ConnectionId(1), Version: "v1"})
	chId := v.store.(*mockStore).currentChannelId()
	v.ChannelOpenAck(0, cur, types.MsgChannelOpenAck{ChannelId: chId, CounterpartyChannelId: types.ChannelId(9), CounterpartyVersion: "v1", ProofHeight: 10, ProofTry: []byte("p")})

	uassert.AbortsContains(t, cur, "authorized to send", func(cur realm) {
		v.SendPacket(0, cur, chId, types.Timestamp(1000), []byte("data"))
	})
}

func TestPacketRecvDispatchesAndReceipts(cur realm, t *testing.T) {
	v := newTestImpl()
	chId, _, mApp := setupOpenChannel(cur, v)
	packet := types.Packet{
		SourceChannelId:      types.ChannelId(9),
		DestinationChannelId: chId,
		Data:                 []byte("recv-data"),
		TimeoutTimestamp:     farFuture,
	}

	v.PacketRecv(0, cur, types.MsgPacketRecv{
		Packets:     []types.Packet{packet},
		RelayerMsgs: [][]byte{[]byte("rm")},
		Proof:       []byte("proof"),
		ProofHeight: 10,
	})

	uassert.Equal(t, 1, mApp.recvCalls)
	uassert.True(t, v.store.HasPacketReceipt(packet))
}

// TestPacketRecvShorterRelayerMsgsDropsUnpaired pins union's zip semantics
// (contract.rs L1751, packets.into_iter().zip(relayer_msgs)): a packet without a
// matching relayer msg is not dispatched. With two packets and one relayer msg,
// only the first packet is received; the second is left undispatched.
func TestPacketRecvShorterRelayerMsgsDropsUnpaired(cur realm, t *testing.T) {
	v := newTestImpl()
	chId, _, mApp := setupOpenChannel(cur, v)
	packet0 := types.Packet{
		SourceChannelId:      types.ChannelId(9),
		DestinationChannelId: chId,
		Data:                 []byte("recv-0"),
		TimeoutTimestamp:     farFuture,
	}
	packet1 := types.Packet{
		SourceChannelId:      types.ChannelId(9),
		DestinationChannelId: chId,
		Data:                 []byte("recv-1"),
		TimeoutTimestamp:     farFuture,
	}

	// Two packets, but only one relayer msg: the second packet has no match.
	v.PacketRecv(0, cur, types.MsgPacketRecv{
		Packets:     []types.Packet{packet0, packet1},
		RelayerMsgs: [][]byte{[]byte("rm0")},
		Proof:       []byte("proof"),
		ProofHeight: 10,
	})

	// Only the paired packet is dispatched and receipted; the unpaired one is dropped.
	uassert.Equal(t, 1, mApp.recvCalls)
	uassert.True(t, v.store.HasPacketReceipt(packet0))
	uassert.False(t, v.store.HasPacketReceipt(packet1))
}

func TestPacketRecvDuplicateSkipped(cur realm, t *testing.T) {
	v := newTestImpl()
	chId, _, mApp := setupOpenChannel(cur, v)
	packet := types.Packet{
		SourceChannelId:      types.ChannelId(9),
		DestinationChannelId: chId,
		Data:                 []byte("dup-data"),
		TimeoutTimestamp:     farFuture,
	}
	msg := types.MsgPacketRecv{Packets: []types.Packet{packet}, RelayerMsgs: [][]byte{[]byte("rm")}, Proof: []byte("p"), ProofHeight: 10}

	v.PacketRecv(0, cur, msg)
	v.PacketRecv(0, cur, msg) // replay

	uassert.Equal(t, 1, mApp.recvCalls) // only dispatched once
}

func TestPacketRecvRejectsInvalidMessages(cur realm, t *testing.T) {
	tests := []struct {
		name string
		want string
		run  func(cur realm)
	}{
		{
			name: "empty packet batch",
			want: "not enough packets",
			run: func(cur realm) {
				v := newTestImpl()
				v.PacketRecv(0, cur, types.MsgPacketRecv{})
			},
		},
		{
			name: "mixed destination channels",
			want: "batch must use the same channel",
			run: func(cur realm) {
				v := newTestImpl()
				chId, _, _ := setupOpenChannel(cur, v)
				p1 := recvPacket(chId, "mixed-1")
				p2 := recvPacket(types.ChannelId(uint32(chId)+1), "mixed-2")
				v.PacketRecv(0, cur, types.MsgPacketRecv{
					Packets:     []types.Packet{p1, p2},
					RelayerMsgs: [][]byte{[]byte("rm1"), []byte("rm2")},
					Proof:       []byte("p"),
					ProofHeight: 10,
				})
			},
		},
		{
			name: "expired packet",
			want: "packet timeout expired",
			run: func(cur realm) {
				v := newTestImpl()
				chId, _, _ := setupOpenChannel(cur, v)
				packet := recvPacket(chId, "expired")
				packet.TimeoutTimestamp = 1
				v.PacketRecv(0, cur, types.MsgPacketRecv{
					Packets:     []types.Packet{packet},
					RelayerMsgs: [][]byte{[]byte("rm")},
					Proof:       []byte("p"),
					ProofHeight: 10,
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

func TestPacketRecvRelayerMessageLengthMismatchIsPartial(cur realm, t *testing.T) {
	tests := []struct {
		name      string
		msgs      [][]byte
		wantCalls int
		wantP1    bool
		wantP2    bool
	}{
		{"fewer relayer messages than packets", [][]byte{[]byte("rm1")}, 1, true, false},
		{"more relayer messages than packets", [][]byte{[]byte("rm1"), []byte("rm2"), []byte("extra")}, 2, true, true},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			v := newTestImpl()
			chId, _, mApp := setupOpenChannel(cur, v)
			p1 := recvPacket(chId, "recv-len-1")
			p2 := recvPacket(chId, "recv-len-2")

			v.PacketRecv(0, cur, types.MsgPacketRecv{
				Packets:     []types.Packet{p1, p2},
				RelayerMsgs: tc.msgs,
				Proof:       []byte("p"),
				ProofHeight: 10,
			})

			uassert.Equal(t, tc.wantCalls, mApp.recvCalls)
			uassert.Equal(t, tc.wantP1, v.store.HasPacketReceipt(p1))
			uassert.Equal(t, tc.wantP2, v.store.HasPacketReceipt(p2))
		})
	}
}

func TestPacketRecvAsyncLeavesMagicReceipt(cur realm, t *testing.T) {
	v := newTestImpl()
	chId, _, mApp := setupOpenChannel(cur, v)
	mApp.recvStatus = types.PacketStatusAsync
	packet := recvPacket(chId, "async-recv")

	v.PacketRecv(0, cur, types.MsgPacketRecv{
		Packets:     []types.Packet{packet},
		RelayerMsgs: [][]byte{[]byte("rm")},
		Proof:       []byte("p"),
		ProofHeight: 10,
	})

	receipt, ok := v.store.AcknowledgementReceipt(chId, packet)
	uassert.True(t, ok)
	uassert.True(t, receipt == types.COMMITMENT_MAGIC)
}

func TestIntentPacketRecvDispatchesAndReceipts(cur realm, t *testing.T) {
	v := newTestImpl()
	chId, _, mApp := setupOpenChannel(cur, v)
	packet := recvPacket(chId, "intent")

	v.IntentPacketRecv(0, cur, types.MsgIntentPacketRecv{
		Packets:             []types.Packet{packet},
		MarketMakerMessages: [][]byte{[]byte("mm")},
	})

	uassert.Equal(t, 1, mApp.intentRecvCalls)
	uassert.True(t, v.store.HasPacketReceipt(packet))
	receipt, ok := v.store.AcknowledgementReceipt(chId, packet)
	uassert.True(t, ok)
	uassert.True(t, receipt == types.CommitAcks([][]byte{[]byte("ack")}))
}

func TestIntentPacketRecvMarketMakerMessageLengthMismatchIsPartial(cur realm, t *testing.T) {
	tests := []struct {
		name      string
		msgs      [][]byte
		wantCalls int
		wantP1    bool
		wantP2    bool
	}{
		{"fewer market maker messages than packets", [][]byte{[]byte("mm1")}, 1, true, false},
		{"more market maker messages than packets", [][]byte{[]byte("mm1"), []byte("mm2"), []byte("extra")}, 2, true, true},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			v := newTestImpl()
			chId, _, mApp := setupOpenChannel(cur, v)
			p1 := recvPacket(chId, "intent-len-1")
			p2 := recvPacket(chId, "intent-len-2")

			v.IntentPacketRecv(0, cur, types.MsgIntentPacketRecv{
				Packets:             []types.Packet{p1, p2},
				MarketMakerMessages: tc.msgs,
			})

			uassert.Equal(t, tc.wantCalls, mApp.intentRecvCalls)
			uassert.Equal(t, tc.wantP1, v.store.HasPacketReceipt(p1))
			uassert.Equal(t, tc.wantP2, v.store.HasPacketReceipt(p2))
		})
	}
}

func TestIntentPacketRecvDuplicateSkipped(cur realm, t *testing.T) {
	v := newTestImpl()
	chId, _, mApp := setupOpenChannel(cur, v)
	packet := recvPacket(chId, "intent-dup")
	msg := types.MsgIntentPacketRecv{
		Packets:             []types.Packet{packet},
		MarketMakerMessages: [][]byte{[]byte("mm")},
	}

	v.IntentPacketRecv(0, cur, msg)
	v.IntentPacketRecv(0, cur, msg)

	uassert.Equal(t, 1, mApp.intentRecvCalls)
}

func TestIntentPacketRecvRejectsInvalidSyncResult(cur realm, t *testing.T) {
	tests := []struct {
		name      string
		status    types.PacketStatus
		ackSet    bool
		want      string
		packetKey string
	}{
		{"empty sync ack", types.PacketStatusSuccess, true, "sync ack cannot be empty", "intent-empty-ack"},
		{"unknown status", types.PacketStatus(99), false, "unknown packet status", "intent-unknown"},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			v := newTestImpl()
			chId, _, mApp := setupOpenChannel(cur, v)
			mApp.recvStatus = tc.status
			mApp.recvAckSet = tc.ackSet
			packet := recvPacket(chId, tc.packetKey)

			uassert.AbortsContains(t, cur, tc.want, func(cur realm) {
				v.IntentPacketRecv(0, cur, types.MsgIntentPacketRecv{
					Packets:             []types.Packet{packet},
					MarketMakerMessages: [][]byte{[]byte("mm")},
				})
			})
		})
	}
}

func TestPacketRecvProofFailureAborts(cur realm, t *testing.T) {
	v := newTestImpl()
	ms := v.store.(*mockStore)
	clientId := createClient(cur, v, &mockLightClient{membershipErr: "bad proof"}, nil, nil)
	ms.SaveConnection(0, cur, types.ConnectionId(1),
		core.NewConnection(types.ConnectionStateOpen, clientId, types.ClientId(7), types.ConnectionId(2)))
	port := types.Bytes(cur.Previous().PkgPath())
	ms.registerApp(port, &mockApp{})
	v.ChannelOpenInit(0, cur, types.MsgChannelOpenInit{PortId: port, ConnectionId: types.ConnectionId(1), Version: "v1"})
	chId := v.store.(*mockStore).currentChannelId()
	// channel stays Init (ack would need a separate good client); recv only needs it Open.
	ms.SaveChannel(0, cur, chId, types.Channel{State: types.ChannelStateOpen, ConnectionId: types.ConnectionId(1), CounterpartyChannelId: types.ChannelId(9), Version: "v1"})

	packet := types.Packet{SourceChannelId: types.ChannelId(9), DestinationChannelId: chId, Data: []byte("d"), TimeoutTimestamp: farFuture}
	uassert.AbortsContains(t, cur, "bad proof", func(cur realm) {
		v.PacketRecv(0, cur, types.MsgPacketRecv{Packets: []types.Packet{packet}, RelayerMsgs: [][]byte{[]byte("rm")}, Proof: []byte("p"), ProofHeight: 10})
	})
}

func setupOpenChannelWithClient(cur realm, v *coreV1, lc *mockLightClient, portId types.Bytes) types.ChannelId {
	ms := v.store.(*mockStore)
	clientId := createClient(cur, v, lc, nil, nil)
	ms.SaveConnection(0, cur, types.ConnectionId(1),
		core.NewConnection(types.ConnectionStateOpen, clientId, types.ClientId(7), types.ConnectionId(2)))
	ms.registerApp(portId, &mockApp{})
	chId := v.store.NextChannelId(0, cur)
	v.store.CreateChannel(0, cur, chId, types.Channel{
		State:                 types.ChannelStateOpen,
		ConnectionId:          types.ConnectionId(1),
		CounterpartyChannelId: types.ChannelId(9),
		Version:               "v1",
	}, portId)
	return chId
}

func TestPacketMembershipEntrypointsInactiveClientAbortBeforeVerification(cur realm, t *testing.T) {
	tests := []struct {
		name string
		run  func(cur realm, v *coreV1, lc *mockLightClient)
	}{
		{
			name: "packet recv",
			run: func(cur realm, v *coreV1, lc *mockLightClient) {
				chId := setupOpenChannelWithClient(cur, v, lc, types.Bytes(cur.Previous().PkgPath()))
				packet := recvPacket(chId, "inactive-recv")
				v.PacketRecv(0, cur, types.MsgPacketRecv{
					Packets:     []types.Packet{packet},
					RelayerMsgs: [][]byte{[]byte("rm")},
					Proof:       []byte("proof"),
					ProofHeight: 10,
				})
			},
		},
		{
			name: "packet acknowledgement",
			run: func(cur realm, v *coreV1, lc *mockLightClient) {
				chId := setupOpenChannelWithClient(cur, v, lc, types.Bytes(cur.Previous().PkgPath()))
				packet := v.SendPacket(0, cur, chId, types.Timestamp(1000), []byte("inactive-ack"))
				v.PacketAcknowledgement(0, cur, types.MsgPacketAcknowledgement{
					Packets:          []types.Packet{packet},
					Acknowledgements: [][]byte{[]byte("ack")},
					Proof:            []byte("proof"),
					ProofHeight:      10,
				})
			},
		},
		{
			name: "commit membership proof",
			run: func(cur realm, v *coreV1, lc *mockLightClient) {
				clientId := createClient(cur, v, lc, nil, nil)
				v.CommitMembershipProof(0, cur, types.MsgCommitMembershipProof{
					ClientId:    clientId,
					ProofHeight: 10,
					Proof:       []byte("proof"),
					Path:        []byte("path"),
					Value:       []byte("value"),
				})
			},
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			v := newTestImpl()
			lc := &mockLightClient{status: "Frozen", timestampAtHt: farFuture}

			uassert.AbortsContains(t, cur, "client is not active", func(cur realm) {
				tc.run(cur, v, lc)
			})
			uassert.Equal(t, 0, lc.membershipCalls)
		})
	}
}

func TestPacketRecvRejectsMissingPortApp(cur realm, t *testing.T) {
	v := newTestImpl()
	chId := setupOpenChannelWithoutApp(cur, v, types.Bytes("missing-port"))
	packet := recvPacket(chId, "missing-port-recv")

	uassert.AbortsContains(t, cur, "port missing-port not found", func(cur realm) {
		v.PacketRecv(0, cur, types.MsgPacketRecv{
			Packets:     []types.Packet{packet},
			RelayerMsgs: [][]byte{[]byte("rm")},
			Proof:       []byte("p"),
			ProofHeight: 10,
		})
	})
}

func TestIntentPacketRecvRejectsMissingPortApp(cur realm, t *testing.T) {
	v := newTestImpl()
	chId := setupOpenChannelWithoutApp(cur, v, types.Bytes("missing-port"))
	packet := recvPacket(chId, "missing-port-intent")

	uassert.AbortsContains(t, cur, "port missing-port not found", func(cur realm) {
		v.IntentPacketRecv(0, cur, types.MsgIntentPacketRecv{
			Packets:             []types.Packet{packet},
			MarketMakerMessages: [][]byte{[]byte("mm")},
		})
	})
}

func TestPacketAcknowledgementMarksAndNotifies(cur realm, t *testing.T) {
	v := newTestImpl()
	chId, _, mApp := setupOpenChannel(cur, v)
	packet := v.SendPacket(0, cur, chId, types.Timestamp(1000), []byte("ack-data"))

	v.PacketAcknowledgement(0, cur, types.MsgPacketAcknowledgement{
		Packets:          []types.Packet{packet},
		Acknowledgements: [][]byte{[]byte("ack")},
		Proof:            []byte("proof"),
		ProofHeight:      10,
	})

	uassert.Equal(t, 1, mApp.ackCalls)
	// A second ack of the same packet is now rejected (already acknowledged):
	// the impl owns the state machine and aborts before re-flipping the commitment.
	uassert.AbortsContains(t, cur, "already acknowledged", func(cur realm) {
		v.markPacketAcknowledged(0, cur, packet)
	})
}

func TestPacketAcknowledgementRejectsInvalidMessages(cur realm, t *testing.T) {
	tests := []struct {
		name string
		want string
		run  func(cur realm)
	}{
		{
			name: "empty packet batch",
			want: "not enough packets",
			run: func(cur realm) {
				v := newTestImpl()
				v.PacketAcknowledgement(0, cur, types.MsgPacketAcknowledgement{})
			},
		},
		{
			name: "mixed source channels",
			want: "batch must use the same channel",
			run: func(cur realm) {
				v := newTestImpl()
				chId, _, _ := setupOpenChannel(cur, v)
				p1 := v.SendPacket(0, cur, chId, types.Timestamp(1000), []byte("ack-mixed-1"))
				p2 := p1
				p2.SourceChannelId = types.ChannelId(uint32(chId) + 1)
				v.PacketAcknowledgement(0, cur, types.MsgPacketAcknowledgement{
					Packets:          []types.Packet{p1, p2},
					Acknowledgements: [][]byte{[]byte("ack1"), []byte("ack2")},
					Proof:            []byte("proof"),
					ProofHeight:      10,
				})
			},
		},
		{
			name: "missing commitment",
			want: "packet commitment not found",
			run: func(cur realm) {
				v := newTestImpl()
				chId, _, _ := setupOpenChannel(cur, v)
				packet := types.Packet{SourceChannelId: chId, DestinationChannelId: types.ChannelId(9), Data: []byte("missing-ack"), TimeoutTimestamp: types.Timestamp(1000)}
				v.PacketAcknowledgement(0, cur, types.MsgPacketAcknowledgement{
					Packets:          []types.Packet{packet},
					Acknowledgements: [][]byte{[]byte("ack")},
					Proof:            []byte("proof"),
					ProofHeight:      10,
				})
			},
		},
		{
			name: "already acknowledged",
			want: "packet already acknowledged",
			run: func(cur realm) {
				v := newTestImpl()
				chId, _, _ := setupOpenChannel(cur, v)
				packet := v.SendPacket(0, cur, chId, types.Timestamp(1000), []byte("ack-twice"))
				msg := types.MsgPacketAcknowledgement{
					Packets:          []types.Packet{packet},
					Acknowledgements: [][]byte{[]byte("ack")},
					Proof:            []byte("proof"),
					ProofHeight:      10,
				}
				v.PacketAcknowledgement(0, cur, msg)
				v.PacketAcknowledgement(0, cur, msg)
			},
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			uassert.AbortsContains(t, cur, tc.want, tc.run)
		})
	}
}

func TestPacketAcknowledgementLengthMismatchIsPartial(cur realm, t *testing.T) {
	tests := []struct {
		name      string
		acks      [][]byte
		wantCalls int
		wantP1Ack bool
		wantP2Ack bool
	}{
		{"fewer acknowledgements than packets", [][]byte{[]byte("ack1")}, 1, true, false},
		{"more acknowledgements than packets", [][]byte{[]byte("ack1"), []byte("ack2"), []byte("extra")}, 2, true, true},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			v := newTestImpl()
			chId, _, mApp := setupOpenChannel(cur, v)
			p1 := v.SendPacket(0, cur, chId, types.Timestamp(1000), []byte("ack-len-1"))
			p2 := v.SendPacket(0, cur, chId, types.Timestamp(1000), []byte("ack-len-2"))

			v.PacketAcknowledgement(0, cur, types.MsgPacketAcknowledgement{
				Packets:          []types.Packet{p1, p2},
				Acknowledgements: tc.acks,
				Proof:            []byte("proof"),
				ProofHeight:      10,
			})

			uassert.Equal(t, tc.wantCalls, mApp.ackCalls)
			p1Commitment, _ := v.store.PacketCommitment(chId, p1)
			p2Commitment, _ := v.store.PacketCommitment(chId, p2)
			uassert.Equal(t, tc.wantP1Ack, p1Commitment == types.COMMITMENT_MAGIC_ACK)
			uassert.Equal(t, tc.wantP2Ack, p2Commitment == types.COMMITMENT_MAGIC_ACK)
		})
	}
}

func TestPacketTimeoutRefunds(cur realm, t *testing.T) {
	v := newTestImpl()
	chId, _, mApp := setupOpenChannel(cur, v)
	packet := v.SendPacket(0, cur, chId, types.Timestamp(1000), []byte("timeout-data"))

	v.PacketTimeout(0, cur, types.MsgPacketTimeout{
		Packet:      packet,
		Proof:       []byte("proof"),
		ProofHeight: 5,
	})

	uassert.Equal(t, 1, mApp.timeoutCalls)
}

func TestPacketTimeoutRejectsInvalidMessages(cur realm, t *testing.T) {
	tests := []struct {
		name string
		want string
		run  func(cur realm)
	}{
		{
			name: "missing channel",
			want: "channel 777 not found",
			run: func(cur realm) {
				v := newTestImpl()
				packet := types.Packet{SourceChannelId: types.ChannelId(777), DestinationChannelId: types.ChannelId(9), Data: []byte("timeout-missing-channel"), TimeoutTimestamp: types.Timestamp(1000)}
				v.PacketTimeout(0, cur, types.MsgPacketTimeout{Packet: packet, Proof: []byte("proof"), ProofHeight: 5})
			},
		},
		{
			name: "missing client",
			want: "client 99 not found",
			run: func(cur realm) {
				v := newTestImpl()
				ms := v.store.(*mockStore)
				chId := types.ChannelId(1)
				ms.SaveConnection(0, cur, types.ConnectionId(1),
					core.NewConnection(types.ConnectionStateOpen, types.ClientId(99), types.ClientId(7), types.ConnectionId(2)))
				ms.CreateChannel(0, cur, chId, types.Channel{
					State:                 types.ChannelStateOpen,
					ConnectionId:          types.ConnectionId(1),
					CounterpartyChannelId: types.ChannelId(9),
					Version:               "v1",
				}, types.Bytes(cur.Previous().PkgPath()))
				packet := types.Packet{SourceChannelId: chId, DestinationChannelId: types.ChannelId(9), Data: []byte("timeout-missing-client"), TimeoutTimestamp: types.Timestamp(1000)}
				v.PacketTimeout(0, cur, types.MsgPacketTimeout{Packet: packet, Proof: []byte("proof"), ProofHeight: 5})
			},
		},
		{
			name: "zero proof timestamp",
			want: "packet timeout proof timestamp not found",
			run: func(cur realm) {
				v := newTestImpl()
				chId, _, _ := setupOpenChannelWithLightClient(cur, v, &mockLightClient{})
				packet := v.SendPacket(0, cur, chId, types.Timestamp(1000), []byte("timeout-zero-ts"))
				v.PacketTimeout(0, cur, types.MsgPacketTimeout{Packet: packet, Proof: []byte("proof"), ProofHeight: 5})
			},
		},
		{
			name: "timeout not reached",
			want: "packet timeout not reached",
			run: func(cur realm) {
				v := newTestImpl()
				chId, _, _ := setupOpenChannelWithLightClient(cur, v, &mockLightClient{timestampAtHt: types.Timestamp(10)})
				packet := v.SendPacket(0, cur, chId, farFuture, []byte("timeout-not-reached"))
				v.PacketTimeout(0, cur, types.MsgPacketTimeout{Packet: packet, Proof: []byte("proof"), ProofHeight: 5})
			},
		},
		{
			name: "missing commitment",
			want: "packet commitment not found",
			run: func(cur realm) {
				v := newTestImpl()
				chId, _, _ := setupOpenChannel(cur, v)
				packet := types.Packet{SourceChannelId: chId, DestinationChannelId: types.ChannelId(9), Data: []byte("timeout-missing"), TimeoutTimestamp: types.Timestamp(1000)}
				v.PacketTimeout(0, cur, types.MsgPacketTimeout{Packet: packet, Proof: []byte("proof"), ProofHeight: 5})
			},
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			uassert.AbortsContains(t, cur, tc.want, tc.run)
		})
	}
}

func TestPacketTimeoutInactiveClientAbortsBeforeVerification(cur realm, t *testing.T) {
	lc := &mockLightClient{timestampAtHt: farFuture}
	v := newTestImpl()
	chId, _, _ := setupOpenChannelWithLightClient(cur, v, lc)
	packet := v.SendPacket(0, cur, chId, types.Timestamp(1000), []byte("timeout-inactive"))
	lc.status = "Frozen"

	uassert.AbortsContains(t, cur, "client is not active", func(cur realm) {
		v.PacketTimeout(0, cur, types.MsgPacketTimeout{Packet: packet, Proof: []byte("proof"), ProofHeight: 5})
	})
	uassert.Equal(t, 0, lc.nonMembershipCalls)
}

func TestCommitMembershipProof(cur realm, t *testing.T) {
	v := newTestImpl()
	clientId := createClient(cur, v, &mockLightClient{}, nil, nil)

	uassert.NotAborts(t, cur, func() {
		v.CommitMembershipProof(0, cur, types.MsgCommitMembershipProof{
			ClientId: clientId, ProofHeight: 10, Proof: []byte("p"), Path: []byte("path"), Value: []byte("value"),
		})
	})
}

func TestCommitNonMembershipProof(cur realm, t *testing.T) {
	v := newTestImpl()
	clientId := createClient(cur, v, &mockLightClient{}, nil, nil)

	uassert.NotAborts(t, cur, func() {
		v.CommitNonMembershipProof(0, cur, types.MsgCommitNonMembershipProof{
			ClientId: clientId, ProofHeight: 10, Proof: []byte("p"), Path: []byte("path"),
		})
	})
}

func TestCommitNonMembershipProofInactiveClientAbortsBeforeVerification(cur realm, t *testing.T) {
	v := newTestImpl()
	lc := &mockLightClient{status: "Frozen"}
	clientId := createClient(cur, v, lc, nil, nil)

	uassert.AbortsContains(t, cur, "client is not active", func(cur realm) {
		v.CommitNonMembershipProof(0, cur, types.MsgCommitNonMembershipProof{
			ClientId: clientId, ProofHeight: 10, Proof: []byte("p"), Path: []byte("path"),
		})
	})
	uassert.Equal(t, 0, lc.nonMembershipCalls)
}

func TestWriteAcknowledgementWritesAsyncAck(cur realm, t *testing.T) {
	v := newTestImpl()
	chId, _, mApp := setupOpenChannel(cur, v)
	mApp.recvStatus = types.PacketStatusAsync // recv defers the ack
	packet := types.Packet{
		SourceChannelId:      types.ChannelId(9),
		DestinationChannelId: chId,
		Data:                 []byte("wack-data"),
		TimeoutTimestamp:     farFuture,
	}
	v.PacketRecv(0, cur, types.MsgPacketRecv{Packets: []types.Packet{packet}, RelayerMsgs: [][]byte{[]byte("rm")}, Proof: []byte("p"), ProofHeight: 10})

	v.WriteAcknowledgement(0, cur, types.MsgWriteAcknowledgement{Packet: packet, Acknowledgement: []byte("late-ack")})

	receipt, ok := v.store.AcknowledgementReceipt(chId, packet)
	uassert.True(t, ok)
	uassert.True(t, receipt == types.CommitAcks([][]byte{[]byte("late-ack")}))
}

func TestWriteAcknowledgementRejectsInvalidMessages(cur realm, t *testing.T) {
	tests := []struct {
		name string
		want string
		run  func(cur realm)
	}{
		{
			name: "empty ack",
			want: "acknowledgement cannot be empty",
			run: func(cur realm) {
				v := newTestImpl()
				chId, _, _ := setupOpenChannel(cur, v)
				packet := recvPacket(chId, "empty-write-ack")
				v.WriteAcknowledgement(0, cur, types.MsgWriteAcknowledgement{Packet: packet})
			},
		},
		{
			name: "unauthorized writer",
			want: "caller not authorized to write ack",
			run: func(cur realm) {
				v := newTestImpl()
				ms := v.store.(*mockStore)
				chId := types.ChannelId(77)
				packet := recvPacket(chId, "unauthorized-write-ack")
				ms.CreateChannel(0, cur, chId, types.Channel{State: types.ChannelStateOpen}, types.Bytes("other-port"))
				ms.SetPacketReceipt(0, cur, packet)
				v.WriteAcknowledgement(0, cur, types.MsgWriteAcknowledgement{Packet: packet, Acknowledgement: []byte("ack")})
			},
		},
		{
			name: "missing channel",
			want: "channel 777 not found",
			run: func(cur realm) {
				v := newTestImpl()
				packet := recvPacket(types.ChannelId(777), "missing-write-channel")
				v.WriteAcknowledgement(0, cur, types.MsgWriteAcknowledgement{Packet: packet, Acknowledgement: []byte("ack")})
			},
		},
		{
			name: "missing receipt",
			want: "packet receipt not found",
			run: func(cur realm) {
				v := newTestImpl()
				chId, _, _ := setupOpenChannel(cur, v)
				packet := recvPacket(chId, "missing-write-receipt")
				v.WriteAcknowledgement(0, cur, types.MsgWriteAcknowledgement{Packet: packet, Acknowledgement: []byte("ack")})
			},
		},
		{
			name: "already written",
			want: "acknowledgement already written",
			run: func(cur realm) {
				v := newTestImpl()
				chId, _, _ := setupOpenChannel(cur, v)
				packet := recvPacket(chId, "already-written-ack")
				v.PacketRecv(0, cur, types.MsgPacketRecv{Packets: []types.Packet{packet}, RelayerMsgs: [][]byte{[]byte("rm")}, Proof: []byte("p"), ProofHeight: 10})
				v.WriteAcknowledgement(0, cur, types.MsgWriteAcknowledgement{Packet: packet, Acknowledgement: []byte("late-ack")})
			},
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			uassert.AbortsContains(t, cur, tc.want, tc.run)
		})
	}
}

func TestSendPacketRejectsInvalidState(cur realm, t *testing.T) {
	tests := []struct {
		name string
		want string
		run  func(cur realm)
	}{
		{
			name: "missing channel owner",
			want: "channel 777 not found",
			run: func(cur realm) {
				v := newTestImpl()
				v.SendPacket(0, cur, types.ChannelId(777), types.Timestamp(1000), []byte("missing-owner-send"))
			},
		},
		{
			name: "missing channel record",
			want: "channel 77 not found",
			run: func(cur realm) {
				v := newTestImpl()
				ms := v.store.(*mockStore)
				chId := types.ChannelId(77)
				ms.channelOwners[uint32(chId)] = types.Bytes(cur.Previous().PkgPath())
				v.SendPacket(0, cur, chId, types.Timestamp(1000), []byte("missing-channel-send"))
			},
		},
		{
			name: "closed channel",
			want: "invalid channel state",
			run: func(cur realm) {
				v := newTestImpl()
				chId, _, _ := setupOpenChannel(cur, v)
				v.store.SaveChannel(0, cur, chId, types.Channel{
					State:                 types.ChannelStateClosed,
					ConnectionId:          types.ConnectionId(1),
					CounterpartyChannelId: types.ChannelId(9),
					Version:               "v1",
				})
				v.SendPacket(0, cur, chId, types.Timestamp(1000), []byte("closed-send"))
			},
		},
		{
			name: "duplicate commitment",
			want: "packet commitment already exists",
			run: func(cur realm) {
				v := newTestImpl()
				chId, _, _ := setupOpenChannel(cur, v)
				v.SendPacket(0, cur, chId, types.Timestamp(1000), []byte("dup-send"))
				v.SendPacket(0, cur, chId, types.Timestamp(1000), []byte("dup-send"))
			},
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			uassert.AbortsContains(t, cur, tc.want, tc.run)
		})
	}
}

func TestBatchSendAggregatesCommitments(cur realm, t *testing.T) {
	v := newTestImpl()
	chId, _, _ := setupOpenChannel(cur, v)
	p1 := v.SendPacket(0, cur, chId, types.Timestamp(1000), []byte("b1"))
	p2 := v.SendPacket(0, cur, chId, types.Timestamp(1000), []byte("b2"))

	uassert.NotAborts(t, cur, func() {
		v.BatchSend(0, cur, types.MsgBatchSend{Packets: []types.Packet{p1, p2}})
	})
}

func TestBatchSendRejectsUncommitted(cur realm, t *testing.T) {
	v := newTestImpl()
	chId, _, _ := setupOpenChannel(cur, v)
	p1 := v.SendPacket(0, cur, chId, types.Timestamp(1000), []byte("b1"))
	// p2 was never committed.
	p2 := types.Packet{SourceChannelId: chId, DestinationChannelId: types.ChannelId(9), Data: []byte("b2"), TimeoutTimestamp: types.Timestamp(1000)}

	uassert.AbortsContains(t, cur, "packet commitment not found", func(cur realm) {
		v.BatchSend(0, cur, types.MsgBatchSend{Packets: []types.Packet{p1, p2}})
	})
}

func TestBatchAcksAggregatesReceipts(cur realm, t *testing.T) {
	v := newTestImpl()
	chId, _, _ := setupOpenChannel(cur, v)
	p1 := recvPacket(chId, "ack-batch-1")
	p2 := recvPacket(chId, "ack-batch-2")
	v.PacketRecv(0, cur, types.MsgPacketRecv{
		Packets:     []types.Packet{p1, p2},
		RelayerMsgs: [][]byte{[]byte("rm1"), []byte("rm2")},
		Proof:       []byte("p"),
		ProofHeight: 10,
	})

	v.BatchAcks(0, cur, types.MsgBatchAcks{Packets: []types.Packet{p1, p2}, Acks: [][]byte{[]byte("ack"), []byte("ack")}})

	batchHash := core.CommitPacketsHash([]types.Packet{p1, p2})
	receipt, ok := v.store.BatchReceiptsAt(batchHash)
	uassert.True(t, ok)
	uassert.True(t, receipt == types.CommitAcks([][]byte{[]byte("ack"), []byte("ack")}))
}

func TestBatchAcksRejectsInvalidMessages(cur realm, t *testing.T) {
	tests := []struct {
		name string
		want string
		run  func(cur realm)
	}{
		{
			name: "not enough packets",
			want: "not enough packets",
			run: func(cur realm) {
				v := newTestImpl()
				v.BatchAcks(0, cur, types.MsgBatchAcks{})
			},
		},
		{
			name: "mixed destination channels",
			want: "batch must use the same channel",
			run: func(cur realm) {
				v := newTestImpl()
				chId, _, _ := setupOpenChannel(cur, v)
				p1 := recvPacket(chId, "ack-mixed-dest-1")
				p2 := recvPacket(types.ChannelId(uint32(chId)+1), "ack-mixed-dest-2")
				v.store.CommitAcknowledgement(0, cur, p1, []byte("ack"))
				v.BatchAcks(0, cur, types.MsgBatchAcks{Packets: []types.Packet{p1, p2}, Acks: [][]byte{[]byte("ack"), []byte("ack")}})
			},
		},
		{
			name: "missing receipt",
			want: "packet commitment not found",
			run: func(cur realm) {
				v := newTestImpl()
				chId, _, _ := setupOpenChannel(cur, v)
				p1 := recvPacket(chId, "ack-missing-1")
				p2 := recvPacket(chId, "ack-missing-2")
				v.BatchAcks(0, cur, types.MsgBatchAcks{Packets: []types.Packet{p1, p2}, Acks: [][]byte{[]byte("ack"), []byte("ack")}})
			},
		},
		{
			name: "empty ack receipt",
			want: "acknowledgement cannot be empty",
			run: func(cur realm) {
				v := newTestImpl()
				chId, _, mApp := setupOpenChannel(cur, v)
				mApp.recvStatus = types.PacketStatusAsync
				p1 := recvPacket(chId, "ack-empty-1")
				p2 := recvPacket(chId, "ack-empty-2")
				v.PacketRecv(0, cur, types.MsgPacketRecv{
					Packets:     []types.Packet{p1, p2},
					RelayerMsgs: [][]byte{[]byte("rm1"), []byte("rm2")},
					Proof:       []byte("p"),
					ProofHeight: 10,
				})
				v.BatchAcks(0, cur, types.MsgBatchAcks{Packets: []types.Packet{p1, p2}, Acks: [][]byte{[]byte("ack"), []byte("ack")}})
			},
		},
		{
			name: "ack mismatch",
			want: "acknowledgement mismatch",
			run: func(cur realm) {
				v := newTestImpl()
				chId, _, _ := setupOpenChannel(cur, v)
				p1 := recvPacket(chId, "ack-mismatch-1")
				p2 := recvPacket(chId, "ack-mismatch-2")
				v.PacketRecv(0, cur, types.MsgPacketRecv{
					Packets:     []types.Packet{p1, p2},
					RelayerMsgs: [][]byte{[]byte("rm1"), []byte("rm2")},
					Proof:       []byte("p"),
					ProofHeight: 10,
				})
				v.BatchAcks(0, cur, types.MsgBatchAcks{Packets: []types.Packet{p1, p2}, Acks: [][]byte{[]byte("wrong"), []byte("ack")}})
			},
		},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			uassert.AbortsContains(t, cur, tc.want, tc.run)
		})
	}
}

func TestBatchAcksLengthMismatchPersistsProvidedAcks(cur realm, t *testing.T) {
	tests := []struct {
		name string
		acks [][]byte
	}{
		{"fewer acks than packets", [][]byte{[]byte("ack")}},
		{"more acks than packets", [][]byte{[]byte("ack"), []byte("ack"), []byte("extra")}},
	}

	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			v := newTestImpl()
			chId, _, _ := setupOpenChannel(cur, v)
			p1 := recvPacket(chId, "batch-len-1")
			p2 := recvPacket(chId, "batch-len-2")
			v.PacketRecv(0, cur, types.MsgPacketRecv{
				Packets:     []types.Packet{p1, p2},
				RelayerMsgs: [][]byte{[]byte("rm1"), []byte("rm2")},
				Proof:       []byte("p"),
				ProofHeight: 10,
			})

			v.BatchAcks(0, cur, types.MsgBatchAcks{Packets: []types.Packet{p1, p2}, Acks: tc.acks})

			batchHash := core.CommitPacketsHash([]types.Packet{p1, p2})
			receipt, ok := v.store.BatchReceiptsAt(batchHash)
			uassert.True(t, ok)
			uassert.True(t, receipt == types.CommitAcks(tc.acks))
		})
	}
}
