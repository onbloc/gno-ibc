package zkgm

import (
	"gno.land/p/aib/ibc/types"
	z "gno.land/p/gnoswap/ibc/zkgm"
)

type ZkgmImpl interface {
	PreSend(req SendRequest) error
	Send(req SendRequest) (SendResult, error)
	PostSend(req SendRequest, res SendResult)

	PreRecv(req RecvRequest) error
	Recv(req RecvRequest) (types.RecvPacketResult, error)
	PostRecv(req RecvRequest, res types.RecvPacketResult)

	PreAck(req AckRequest) error
	Ack(req AckRequest) error
	PostAck(req AckRequest)

	PreTimeout(req TimeoutRequest) error
	Timeout(req TimeoutRequest) error
	PostTimeout(req TimeoutRequest)

	Render(pkgpath string, path string) string
}

type SendRequest struct {
	ChannelID        string
	TimeoutTimestamp uint64
	Salt             [32]byte
	Instruction      z.Instruction
	Sender           string
	SentCoins        string
}

type SendResult struct {
	PacketSequence uint64
	PacketHash     [32]byte
}

type RecvRequest struct {
	SourceClient      string
	DestinationClient string
	Sequence          uint64
	Payload           types.Payload
	Caller            string
	Relayer           []byte
	RelayerMsg        []byte
}

type AckRequest struct {
	SourceClient      string
	DestinationClient string
	Sequence          uint64
	Acknowledgement   []byte
	Payload           types.Payload
	Caller            string
	Relayer           []byte
	RelayerMsg        []byte
}

type TimeoutRequest struct {
	SourceClient      string
	DestinationClient string
	Sequence          uint64
	Payload           types.Payload
	Caller            string
	Relayer           []byte
	RelayerMsg        []byte
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
