package zkgm

import (
	types "gno.land/p/onbloc/ibc/union/types"

	z "gno.land/p/onbloc/ibc/union/zkgm"
)

const Version = z.PROTOCOL_VERSION

type ZkgmImpl interface {
	PreChannelOpenInit(cur realm, channelId types.ChannelId)
	PreChannelOpenTry(cur realm, channelId types.ChannelId, counterpartyVersion string)
	PostChannelOpenAck(cur realm, channelId types.ChannelId, counterpartyChannelId types.ChannelId)
	PostChannelOpenConfirm(cur realm, channelId types.ChannelId)
	PreChannelCloseInit(cur realm, channelId types.ChannelId)
	PostChannelCloseConfirm(cur realm, channelId types.ChannelId)

	Recv(cur realm, packet types.Packet, relayer address, relayerMsg []byte) types.RecvPacketResult
	IntentRecv(cur realm, packet types.Packet, marketMaker address, marketMakerMsg []byte) types.RecvPacketResult
	Ack(cur realm, packet types.Packet, ack []byte, relayer address)
	Timeout(cur realm, packet types.Packet, relayer address)

	Send(cur realm, req SendRequest) ([]byte, error)
	Render(pkgpath string, path string) string
}

type SendRequest struct {
	ChannelId        types.ChannelId
	TimeoutTimestamp types.Timestamp
	Salt             [32]byte
	Instruction      z.Instruction
	Sender           string
	SentCoins        string
}

func NewSendRequest(cur realm, channelId types.ChannelId, timeoutTimestamp types.Timestamp, salt [32]byte, instruction z.Instruction, sender string, sentCoins string) SendRequest {
	return SendRequest{
		ChannelId:        channelId,
		TimeoutTimestamp: timeoutTimestamp,
		Salt:             salt,
		Instruction:      instruction,
		Sender:           sender,
		SentCoins:        sentCoins,
	}
}

// InFlightKey identifies a forwarded child packet awaiting the counterparty's
// resolution by the child packet's Union batch hash (CommitPacket result).
type InFlightKey struct {
	PacketHash types.H256
}

// InFlightValue carries the full parent packet so that when the child resolves,
// the parent's deferred ack/timeout can be written via core.WriteAcknowledgement
// on the parent's identity.
type InFlightValue struct {
	ParentPacket types.Packet
}

// NewInFlightValue and NewInFlightKey are crossing constructors so callers
// from other realms can build these structs without tripping the Phase 3
// allocation guard.
func NewInFlightValue(cur realm, parentPacket types.Packet) InFlightValue {
	return InFlightValue{ParentPacket: parentPacket}
}

func NewInFlightKey(cur realm, packetHash types.H256) InFlightKey {
	return InFlightKey{PacketHash: packetHash}
}

type UpdateRequest struct {
	Impl         ZkgmImpl
	AllowedImpls []string
}

// NewUpdateRequest constructs an UpdateRequest in zkgm's realm so callers from
// other realms can build one without tripping the Phase 3 cross-realm
// allocation guard.
func NewUpdateRequest(cur realm, impl ZkgmImpl, allowedImpls []string) UpdateRequest {
	return UpdateRequest{Impl: impl, AllowedImpls: allowedImpls}
}

type Config struct {
	ImplPath     string
	AllowedImpls []string
	Paused       bool
}
