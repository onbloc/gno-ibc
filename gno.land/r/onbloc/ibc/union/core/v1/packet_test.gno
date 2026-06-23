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
	ms := v.store.(*mockStore)
	clientId := createClient(cur, v, &mockLightClient{timestampAtHt: farFuture}, nil, nil)
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
