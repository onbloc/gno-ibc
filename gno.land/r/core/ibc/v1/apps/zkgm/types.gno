package zkgm

import (
	z "gno.land/p/gnoswap/ibc/zkgm"
	core "gno.land/r/core/ibc/v1/core"
)

const Version = "ucs03-zkgm-0"

type ZkgmImpl interface {
	PreChannelOpenInit(channelId core.ChannelId)
	PreChannelOpenTry(channelId core.ChannelId, counterpartyVersion string)
	PostChannelOpenAck(channelId core.ChannelId, counterpartyChannelId core.ChannelId)
	PostChannelOpenConfirm(channelId core.ChannelId)
	PreChannelCloseInit(channelId core.ChannelId)
	PostChannelCloseConfirm(channelId core.ChannelId)

	Recv(packet core.Packet, relayer address, relayerMsg []byte) core.RecvPacketResult
	IntentRecv(packet core.Packet, marketMaker address, marketMakerMsg []byte)
	Ack(packet core.Packet, ack []byte, relayer address)
	Timeout(packet core.Packet, relayer address)

	Send(req SendRequest) ([]byte, error)
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

type UpdateRequest struct {
	Impl         ZkgmImpl
	AllowedImpls []string
}

type Config struct {
	ImplPath     string
	AllowedImpls []string
	Paused       bool
}
