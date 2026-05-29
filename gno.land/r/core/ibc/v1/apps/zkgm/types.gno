package zkgm

import (
	z "gno.land/p/gnoswap/ibc/zkgm"
	core "gno.land/r/core/ibc/v1/core"
)

const Version = "ucs03-zkgm-0"

type ZkgmImpl interface {
	PreChannelOpenInit(cur realm, channelId core.ChannelId)
	PreChannelOpenTry(cur realm, channelId core.ChannelId, counterpartyVersion string)
	PostChannelOpenAck(cur realm, channelId core.ChannelId, counterpartyChannelId core.ChannelId)
	PostChannelOpenConfirm(cur realm, channelId core.ChannelId)
	PreChannelCloseInit(cur realm, channelId core.ChannelId)
	PostChannelCloseConfirm(cur realm, channelId core.ChannelId)

	Recv(cur realm, packet core.Packet, relayer address, relayerMsg []byte) core.RecvPacketResult
	IntentRecv(cur realm, packet core.Packet, marketMaker address, marketMakerMsg []byte) core.RecvPacketResult
	Ack(cur realm, packet core.Packet, ack []byte, relayer address)
	Timeout(cur realm, packet core.Packet, relayer address)

	Send(cur realm, req SendRequest) ([]byte, error)
	Render(pkgpath string, path string) string
}

type SendRequest struct {
	ChannelId        core.ChannelId
	TimeoutTimestamp core.Timestamp
	Salt             [32]byte
	Instruction      z.Instruction
	Sender           string
	SentCoins        string
}

func NewSendRequest(cur realm, channelId core.ChannelId, timeoutTimestamp core.Timestamp, salt [32]byte, instruction z.Instruction, sender string, sentCoins string) SendRequest {
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
	PacketHash core.H256
}

// InFlightValue carries the full parent packet so that when the child resolves,
// the parent's deferred ack/timeout can be written via core.WriteAcknowledgement
// on the parent's identity.
type InFlightValue struct {
	ParentPacket core.Packet
}

// NewInFlightValue and NewInFlightKey are crossing constructors so callers
// from other realms can build these structs without tripping the Phase 3
// allocation guard.
func NewInFlightValue(cur realm, parentPacket core.Packet) InFlightValue {
	return InFlightValue{ParentPacket: parentPacket}
}

func NewInFlightKey(cur realm, packetHash core.H256) InFlightKey {
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
