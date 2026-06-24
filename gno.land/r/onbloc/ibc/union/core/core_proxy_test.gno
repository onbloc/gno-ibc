package core

import (
	"testing"

	"gno.land/p/nt/uassert/v0"
	"gno.land/p/onbloc/ibc/union/types"
	"gno.land/r/onbloc/ibc/union/access"
)

// core_proxy_test.gno covers delegation for the packet-lifecycle entrypoints in
// core.gno. Non-admin/non-relayer rejection for the gated entrypoints is covered
// by core_test.gno; here we assert each authorized call forwards its arguments
// to mustGetImpl(), and that SendPacket returns the impl's packet.
//
// Gate classes:
//   - ungated:       SendPacket, WriteAcknowledgement
//   - admin-gated:   CommitMembershipProof, CommitNonMembershipProof
//   - relayer-gated: PacketRecv, IntentPacketRecv, PacketAcknowledgement,
//                    PacketTimeout, BatchSend, BatchAcks

func TestSendPacket(cur realm, t *testing.T) {
	cases := []struct {
		name      string
		channelId types.ChannelId
		timeout   types.Timestamp
		data      []byte
	}{
		{"typical", 2, 1000, []byte{0x01, 0x02}},
		{"empty data zero timeout", 0, 0, nil},
	}

	for _, tc := range cases {
		resetStore(cur)
		rec, restore := installRecordingCore()
		rec.sendResult = types.NewPacket(tc.channelId, 99, tc.data, tc.timeout)

		// ungated: caller/port-owner authorization happens inside the impl
		got := SendPacket(cross(cur), tc.channelId, tc.timeout, tc.data)

		uassert.Equal(t, 1, rec.calls["SendPacket"])
		uassert.Equal(t, uint64(tc.channelId), uint64(rec.sendChannelId))
		uassert.Equal(t, uint64(tc.timeout), uint64(rec.sendTimeout))
		// SendPacket returns the impl's packet verbatim.
		uassert.Equal(t, uint64(99), uint64(got.DestinationChannelId))

		restore()
	}
}

func TestWriteAcknowledgement(cur realm, t *testing.T) {
	cases := []struct {
		name string
		ack  []byte
	}{
		{"non-empty ack", []byte{0xaa, 0xbb}},
		{"empty ack", nil},
	}

	for _, tc := range cases {
		resetStore(cur)
		rec, restore := installRecordingCore()

		// ungated
		WriteAcknowledgement(cross(cur), types.MsgWriteAcknowledgement{
			Packet:          types.NewPacket(1, 2, []byte{0x01}, 100),
			Acknowledgement: tc.ack,
		})

		uassert.Equal(t, 1, rec.calls["WriteAcknowledgement"])
		uassert.Equal(t, len(tc.ack), len(rec.writeAckMsg.Acknowledgement))

		restore()
	}
}

func TestCommitMembershipProof(cur realm, t *testing.T) {
	cases := []struct {
		name     string
		clientId types.ClientId
		height   uint64
	}{
		{"typical", 4, 200},
		{"zero", 0, 0},
	}

	for _, tc := range cases {
		resetStore(cur)
		rec, restore := installRecordingCore()

		testing.SetRealm(adminRealm)
		CommitMembershipProof(cross(cur), types.MsgCommitMembershipProof{ClientId: tc.clientId, ProofHeight: tc.height})

		uassert.Equal(t, 1, rec.calls["CommitMembershipProof"])
		uassert.Equal(t, uint64(tc.clientId), uint64(rec.commitMemMsg.ClientId))
		uassert.Equal(t, tc.height, rec.commitMemMsg.ProofHeight)

		restore()
	}
}

func TestCommitNonMembershipProof(cur realm, t *testing.T) {
	cases := []struct {
		name     string
		clientId types.ClientId
		height   uint64
	}{
		{"typical", 5, 300},
		{"zero", 0, 0},
	}

	for _, tc := range cases {
		resetStore(cur)
		rec, restore := installRecordingCore()

		testing.SetRealm(adminRealm)
		CommitNonMembershipProof(cross(cur), types.MsgCommitNonMembershipProof{ClientId: tc.clientId, ProofHeight: tc.height})

		uassert.Equal(t, 1, rec.calls["CommitNonMembershipProof"])
		uassert.Equal(t, uint64(tc.clientId), uint64(rec.commitNonMemMsg.ClientId))
		uassert.Equal(t, tc.height, rec.commitNonMemMsg.ProofHeight)

		restore()
	}
}

func TestPacketRecv(cur realm, t *testing.T) {
	cases := []struct {
		name        string
		proofHeight uint64
		packetCount int
	}{
		{"single packet", 150, 1},
		{"empty batch", 0, 0},
	}

	for _, tc := range cases {
		resetStore(cur)
		rec, restore := installRecordingCore()

		packets := make([]types.Packet, tc.packetCount)
		for i := range packets {
			packets[i] = types.NewPacket(1, 2, []byte{byte(i)}, 100)
		}

		testing.SetRealm(adminRealm)
		access.GrantRole(cross(cur), RelayerRole, testRelayer)
		testing.SetRealm(relayerRealm)
		PacketRecv(cross(cur), types.MsgPacketRecv{Packets: packets, ProofHeight: tc.proofHeight})
		testing.SetRealm(adminRealm)
		access.RevokeRole(cross(cur), RelayerRole, testRelayer)

		uassert.Equal(t, 1, rec.calls["PacketRecv"])
		uassert.Equal(t, tc.proofHeight, rec.packetRecvMsg.ProofHeight)
		uassert.Equal(t, tc.packetCount, len(rec.packetRecvMsg.Packets))

		restore()
	}
}

func TestIntentPacketRecv(cur realm, t *testing.T) {
	cases := []struct {
		name        string
		packetCount int
	}{
		{"single packet", 1},
		{"empty batch", 0},
	}

	for _, tc := range cases {
		resetStore(cur)
		rec, restore := installRecordingCore()

		packets := make([]types.Packet, tc.packetCount)
		for i := range packets {
			packets[i] = types.NewPacket(1, 2, []byte{byte(i)}, 100)
		}

		testing.SetRealm(adminRealm)
		access.GrantRole(cross(cur), RelayerRole, testRelayer)
		testing.SetRealm(relayerRealm)
		IntentPacketRecv(cross(cur), types.MsgIntentPacketRecv{Packets: packets})
		testing.SetRealm(adminRealm)
		access.RevokeRole(cross(cur), RelayerRole, testRelayer)

		uassert.Equal(t, 1, rec.calls["IntentPacketRecv"])
		uassert.Equal(t, tc.packetCount, len(rec.intentRecvMsg.Packets))

		restore()
	}
}

func TestPacketAcknowledgement(cur realm, t *testing.T) {
	cases := []struct {
		name        string
		proofHeight uint64
	}{
		{"typical", 175},
		{"zero height", 0},
	}

	for _, tc := range cases {
		resetStore(cur)
		rec, restore := installRecordingCore()

		testing.SetRealm(adminRealm)
		access.GrantRole(cross(cur), RelayerRole, testRelayer)
		testing.SetRealm(relayerRealm)
		PacketAcknowledgement(cross(cur), types.MsgPacketAcknowledgement{ProofHeight: tc.proofHeight})
		testing.SetRealm(adminRealm)
		access.RevokeRole(cross(cur), RelayerRole, testRelayer)

		uassert.Equal(t, 1, rec.calls["PacketAcknowledgement"])
		uassert.Equal(t, tc.proofHeight, rec.packetAckMsg.ProofHeight)

		restore()
	}
}

func TestPacketTimeout(cur realm, t *testing.T) {
	cases := []struct {
		name        string
		proofHeight uint64
	}{
		{"typical", 188},
		{"zero height", 0},
	}

	for _, tc := range cases {
		resetStore(cur)
		rec, restore := installRecordingCore()

		testing.SetRealm(adminRealm)
		access.GrantRole(cross(cur), RelayerRole, testRelayer)
		testing.SetRealm(relayerRealm)
		PacketTimeout(cross(cur), types.MsgPacketTimeout{ProofHeight: tc.proofHeight})
		testing.SetRealm(adminRealm)
		access.RevokeRole(cross(cur), RelayerRole, testRelayer)

		uassert.Equal(t, 1, rec.calls["PacketTimeout"])
		uassert.Equal(t, tc.proofHeight, rec.packetTimeoutMsg.ProofHeight)

		restore()
	}
}

func TestBatchSend(cur realm, t *testing.T) {
	cases := []struct {
		name        string
		packetCount int
	}{
		{"two packets", 2},
		{"empty", 0},
	}

	for _, tc := range cases {
		resetStore(cur)
		rec, restore := installRecordingCore()

		packets := make([]types.Packet, tc.packetCount)
		for i := range packets {
			packets[i] = types.NewPacket(1, 2, []byte{byte(i)}, 100)
		}

		testing.SetRealm(adminRealm)
		access.GrantRole(cross(cur), RelayerRole, testRelayer)
		testing.SetRealm(relayerRealm)
		BatchSend(cross(cur), types.MsgBatchSend{Packets: packets})
		testing.SetRealm(adminRealm)
		access.RevokeRole(cross(cur), RelayerRole, testRelayer)

		uassert.Equal(t, 1, rec.calls["BatchSend"])
		uassert.Equal(t, tc.packetCount, len(rec.batchSendMsg.Packets))

		restore()
	}
}

func TestBatchAcks(cur realm, t *testing.T) {
	cases := []struct {
		name        string
		packetCount int
	}{
		{"two packets", 2},
		{"empty", 0},
	}

	for _, tc := range cases {
		resetStore(cur)
		rec, restore := installRecordingCore()

		packets := make([]types.Packet, tc.packetCount)
		acks := make([][]byte, tc.packetCount)
		for i := range packets {
			packets[i] = types.NewPacket(1, 2, []byte{byte(i)}, 100)
			acks[i] = []byte{0x01}
		}

		testing.SetRealm(adminRealm)
		access.GrantRole(cross(cur), RelayerRole, testRelayer)
		testing.SetRealm(relayerRealm)
		BatchAcks(cross(cur), types.MsgBatchAcks{Packets: packets, Acks: acks})
		testing.SetRealm(adminRealm)
		access.RevokeRole(cross(cur), RelayerRole, testRelayer)

		uassert.Equal(t, 1, rec.calls["BatchAcks"])
		uassert.Equal(t, tc.packetCount, len(rec.batchAcksMsg.Packets))

		restore()
	}
}
