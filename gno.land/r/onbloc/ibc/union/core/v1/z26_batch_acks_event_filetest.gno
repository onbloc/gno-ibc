// PKGPATH: gno.land/r/onbloc/ibc/union/core/v1/main
package main

import (
	"gno.land/p/onbloc/ibc/union/app"
	"gno.land/p/onbloc/ibc/union/lightclient"
	"gno.land/p/onbloc/ibc/union/types"
	core "gno.land/r/onbloc/ibc/union/core"
	impl "gno.land/r/onbloc/ibc/union/core/v1"
)

func main(cur realm) {
	store := newZ26Store()
	v := impl.NewCoreV1(store)

	p1 := types.NewPacket(types.ChannelId(9), types.ChannelId(1), []byte("batch-ack-1"), types.Timestamp(1000))
	p2 := types.NewPacket(types.ChannelId(9), types.ChannelId(1), []byte("batch-ack-2"), types.Timestamp(1000))
	acks := [][]byte{[]byte("ack-1"), []byte("ack-2")}
	store.receipts[z26PacketKey(p1)] = types.CommitAcks([][]byte{acks[0]})
	store.receipts[z26PacketKey(p2)] = types.CommitAcks([][]byte{acks[1]})

	v.BatchAcks(0, cur, types.NewMsgBatchAcks([]types.Packet{p1, p2}, acks))

	batchHash := core.CommitPacketsHash([]types.Packet{p1, p2})
	receipt, ok := store.BatchReceiptsAt(types.ChannelId(1), batchHash)
	println("batch_acks_hash", batchHash.String())
	println("batch_receipt_saved", ok)
	println("batch_receipt_matches", receipt == types.CommitAcks(acks))
	println("batch_acks_event", "ok")
}

type z26Store struct {
	receipts      map[string]types.H256
	batchReceipts map[string]types.H256
}

func newZ26Store() *z26Store {
	return &z26Store{
		receipts:      map[string]types.H256{},
		batchReceipts: map[string]types.H256{},
	}
}

var _ core.IStore = (*z26Store)(nil)

func z26PacketKey(packet types.Packet) string {
	return core.CommitPacketsHash([]types.Packet{packet}).String()
}

func z26BatchKey(channelId types.ChannelId, batchHash types.H256) string {
	return channelId.String() + "|" + batchHash.String()
}

func (s *z26Store) RegisterClient(_ int, rlm realm, typ types.ClientType, lc lightclient.Interface) {
	panic("unused")
}

func (s *z26Store) RegisteredClient(typ types.ClientType) (lightclient.Interface, bool) {
	return nil, false
}
func (s *z26Store) HasRegisteredClient(typ types.ClientType) bool { return false }
func (s *z26Store) AddClient(_ int, rlm realm, typ types.ClientType, creator address, lc lightclient.Interface) types.ClientId {
	panic("unused")
}
func (s *z26Store) ClientExists(clientId types.ClientId) bool { return false }
func (s *z26Store) ClientType(clientId types.ClientId) (types.ClientType, bool) {
	return "", false
}

func (s *z26Store) GetLightClient(clientId types.ClientId) (lightclient.Interface, bool) {
	return nil, false
}

func (s *z26Store) SetLightClient(_ int, rlm realm, clientId types.ClientId, lc lightclient.Interface) bool {
	return false
}

func (s *z26Store) SaveClientState(_ int, rlm realm, clientId types.ClientId, clientStateBytes []byte) bool {
	return false
}

func (s *z26Store) SaveConsensusState(_ int, rlm realm, clientId types.ClientId, height types.Height, consensusStateBytes []byte) bool {
	return false
}

func (s *z26Store) SaveClientStore(_ int, rlm realm, clientId types.ClientId, key string, value []byte) bool {
	return false
}
func (s *z26Store) NextConnectionId(_ int, rlm realm) types.ConnectionId { panic("unused") }
func (s *z26Store) SaveConnection(_ int, rlm realm, connectionId types.ConnectionId, connection types.Connection) {
	panic("unused")
}

func (s *z26Store) GetConnection(connectionId types.ConnectionId) (types.Connection, bool) {
	return types.Connection{}, false
}
func (s *z26Store) NextChannelId(_ int, rlm realm) types.ChannelId { panic("unused") }
func (s *z26Store) CreateChannel(_ int, rlm realm, channelId types.ChannelId, channel types.Channel, portId types.Bytes) {
	panic("unused")
}

func (s *z26Store) SaveChannel(_ int, rlm realm, channelId types.ChannelId, channel types.Channel) {
	panic("unused")
}

func (s *z26Store) GetChannel(channelId types.ChannelId) (types.Channel, bool) {
	return types.Channel{}, false
}
func (s *z26Store) GetChannelOwner(channelId types.ChannelId) (types.Bytes, bool) { return nil, false }
func (s *z26Store) GetAppByPortId(portId types.Bytes) (app.IApp, bool)            { return nil, false }
func (s *z26Store) HasApp(portId types.Bytes) bool                                { return false }
func (s *z26Store) RegisterAppAtPort(_ int, rlm realm, portId types.Bytes, a app.IApp) {
	panic("unused")
}
func (s *z26Store) HasPacketCommitment(packet types.Packet) bool { return false }
func (s *z26Store) CommitPacket(_ int, rlm realm, packet types.Packet) {
	panic("unused")
}

func (s *z26Store) SetPacketAcknowledged(_ int, rlm realm, packet types.Packet) {
	panic("unused")
}

func (s *z26Store) HasPacketReceipt(packet types.Packet) bool {
	_, ok := s.receipts[z26PacketKey(packet)]
	return ok
}

func (s *z26Store) SetPacketReceipt(_ int, rlm realm, packet types.Packet) {
	s.receipts[z26PacketKey(packet)] = types.COMMITMENT_MAGIC
}

func (s *z26Store) CommitAcknowledgement(_ int, rlm realm, packet types.Packet, ack []byte) {
	s.receipts[z26PacketKey(packet)] = types.CommitAcks([][]byte{ack})
}

func (s *z26Store) AcknowledgementReceipt(channelId types.ChannelId, packet types.Packet) (types.H256, bool) {
	v, ok := s.receipts[z26PacketKey(packet)]
	return v, ok
}

func (s *z26Store) PacketCommitment(channelId types.ChannelId, packet types.Packet) (types.H256, bool) {
	return types.H256{}, false
}

func (s *z26Store) SaveBatchPackets(_ int, rlm realm, channelId types.ChannelId, batchHash, value types.H256) {
	panic("unused")
}

func (s *z26Store) SaveBatchReceipts(_ int, rlm realm, channelId types.ChannelId, batchHash, value types.H256) {
	s.batchReceipts[z26BatchKey(channelId, batchHash)] = value
}

func (s *z26Store) SaveMembershipProof(_ int, rlm realm, clientId types.ClientId, proofHeight uint64, path []byte, value types.H256) {
	panic("unused")
}

func (s *z26Store) SaveNonMembershipProof(_ int, rlm realm, clientId types.ClientId, proofHeight uint64, path []byte, value types.H256) {
	panic("unused")
}
func (s *z26Store) ClientStateBytes(clientId types.ClientId) ([]byte, bool) { return nil, false }
func (s *z26Store) ConsensusStateBytes(clientId types.ClientId, height types.Height) ([]byte, bool) {
	return nil, false
}

func (s *z26Store) BatchPacketsAt(channelId types.ChannelId, batchHash types.H256) (types.H256, bool) {
	return types.H256{}, false
}

func (s *z26Store) BatchReceiptsAt(channelId types.ChannelId, batchHash types.H256) (types.H256, bool) {
	v, ok := s.batchReceipts[z26BatchKey(channelId, batchHash)]
	return v, ok
}

// Output:
// batch_acks_hash 0x6169e1095f844beaa20f0d1d75f1c7f5cf1fbee591be6cb10ae06eaaa70b8179
// batch_receipt_saved true
// batch_receipt_matches true
// batch_acks_event ok

// Events:
// [
//   {
//     "type": "BatchAcks",
//     "attrs": [
//       {
//         "key": "channel_id",
//         "value": "1"
//       },
//       {
//         "key": "packet_hash",
//         "value": "0x1f36089351fe4ad21ee815e71dbf6917e0176e6fa9ebd841aab2066e7eb52997"
//       },
//       {
//         "key": "batch_hash",
//         "value": "0x6169e1095f844beaa20f0d1d75f1c7f5cf1fbee591be6cb10ae06eaaa70b8179"
//       }
//     ],
//     "pkg_path": "gno.land/r/onbloc/ibc/union/core"
//   },
//   {
//     "type": "BatchAcks",
//     "attrs": [
//       {
//         "key": "channel_id",
//         "value": "1"
//       },
//       {
//         "key": "packet_hash",
//         "value": "0x91672f4f6f6d02be3d2124bdc4411f3399994d16a6fedcf3aa811cbd95eb55e2"
//       },
//       {
//         "key": "batch_hash",
//         "value": "0x6169e1095f844beaa20f0d1d75f1c7f5cf1fbee591be6cb10ae06eaaa70b8179"
//       }
//     ],
//     "pkg_path": "gno.land/r/onbloc/ibc/union/core"
//   }
// ]
