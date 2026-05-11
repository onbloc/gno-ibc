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

	Recv(packet core.Packet, relayer address, relayerMsg core.Bytes) core.RecvPacketResult
	Ack(packet core.Packet, ack core.Bytes, relayer address)
	Timeout(packet core.Packet, relayer address)

	Send(req SendRequest) (core.Packet, error)
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
// resolution; the source-side IBC core stores the parent ack against this tuple.
type InFlightKey struct {
	SourceChannelId      core.ChannelId
	DestinationChannelId core.ChannelId
	Sequence             core.Sequence
}

// InFlightValue carries the parent packet identity so that when the child resolves,
// the parent's deferred ack/timeout can be written on the correct destination channel.
type InFlightValue struct {
	ParentSourceChannelId      core.ChannelId
	ParentDestinationChannelId core.ChannelId
	ParentSequence             core.Sequence
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
