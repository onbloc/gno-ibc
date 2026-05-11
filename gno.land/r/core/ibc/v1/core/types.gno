package core

import (
	"encoding/hex"
	"strconv"

	"gno.land/p/core/encoding/abi"
)

type ClientId uint32

func (id ClientId) String() string {
	return strconv.FormatUint(uint64(id), 10)
}

type ConnectionId uint32

func (id ConnectionId) String() string {
	return strconv.FormatUint(uint64(id), 10)
}

type ChannelId uint32

func (id ChannelId) String() string {
	return strconv.FormatUint(uint64(id), 10)
}

type Timestamp uint64

func (ts Timestamp) String() string {
	return strconv.FormatUint(uint64(ts), 10)
}

type Sequence uint64

func (s Sequence) String() string {
	return strconv.FormatUint(uint64(s), 10)
}

type Height uint64

func (h Height) String() string {
	return strconv.FormatUint(uint64(h), 10)
}

type Bytes []byte

func (bz Bytes) String() string {
	return "0x" + hex.EncodeToString(bz)
}

// NewBytes constructs a Bytes value from a plain []byte. Required for callers
// in other realms: Gno forbids `core.Bytes(b)` conversions outside this realm.
func NewBytes(_ realm, b []byte) Bytes {
	return Bytes(b)
}

type H256 [32]byte

func (h H256) String() string {
	return "0x" + hex.EncodeToString(h[:])
}

type ClientType string

type Status uint8

const (
	StatusUnknown Status = 0
	StatusActive  Status = 1
	StatusExpired Status = 2
	StatusFrozen  Status = 3
)

type ConnectionState uint8

const (
	ConnectionStateUnknown ConnectionState = 0
	ConnectionStateInit    ConnectionState = 1
	ConnectionStateTryOpen ConnectionState = 2
	ConnectionStateOpen    ConnectionState = 3
)

type ChannelState uint8

const (
	ChannelStateUnknown ChannelState = 0
	ChannelStateInit    ChannelState = 1
	ChannelStateTryOpen ChannelState = 2
	ChannelStateOpen    ChannelState = 3
	ChannelStateClosed  ChannelState = 4
)

type Packet struct {
	Sequence             Sequence
	SourceChannelId      ChannelId
	DestinationChannelId ChannelId
	Data                 Bytes
	TimeoutTimestamp     Timestamp
}

func NewPacket(_ realm, sequence Sequence, sourceChannelId ChannelId, destinationChannelId ChannelId, data []byte, timeoutTimestamp Timestamp) Packet {
	return Packet{
		Sequence:             sequence,
		SourceChannelId:      sourceChannelId,
		DestinationChannelId: destinationChannelId,
		Data:                 Bytes(data),
		TimeoutTimestamp:     timeoutTimestamp,
	}
}

func (p Packet) EthAbiEncode() []byte {
	schema := abi.Schema{Fields: []abi.Field{
		{Type: abi.TypeUint64},
		{Type: abi.TypeUint32},
		{Type: abi.TypeUint32},
		{Type: abi.TypeBytes},
		{Type: abi.TypeUint64},
		{Type: abi.TypeUint64},
	}}
	bz, err := abi.Encode(schema, []any{
		uint64(p.Sequence),
		uint32(p.SourceChannelId),
		uint32(p.DestinationChannelId),
		[]byte(p.Data),
		uint64(0), // TimeoutHeight always zero
		uint64(p.TimeoutTimestamp),
	})
	if err != nil {
		panic(err)
	}
	return bz
}

type PacketStatus uint8

const (
	PacketStatusUnknown PacketStatus = 0
	PacketStatusSuccess PacketStatus = 1
	PacketStatusFailure PacketStatus = 2
	PacketStatusAsync   PacketStatus = 3
)

type RecvPacketResult struct {
	Status PacketStatus
	Ack    Bytes
}

func NewRecvPacketResult(_ realm, status PacketStatus, ack []byte) RecvPacketResult {
	return RecvPacketResult{Status: status, Ack: Bytes(ack)}
}

type Channel struct {
	State                 ChannelState
	ConnectionId          ConnectionId
	CounterpartyChannelId ChannelId
	CounterpartyPortId    Bytes
	Version               string
}

func (c Channel) EthAbiEncode() []byte {
	schema := abi.Schema{Fields: []abi.Field{
		{Type: abi.TypeUint8},
		{Type: abi.TypeUint32},
		{Type: abi.TypeUint32},
		{Type: abi.TypeBytes},
		{Type: abi.TypeString},
	}}
	bz, err := abi.Encode(schema, []any{
		uint8(c.State),
		uint32(c.ConnectionId),
		uint32(c.CounterpartyChannelId),
		[]byte(c.CounterpartyPortId),
		c.Version,
	})
	if err != nil {
		panic(err)
	}
	return bz
}

type Connection struct {
	State                    ConnectionState
	ClientId                 ClientId
	CounterpartyClientId     ClientId
	CounterpartyConnectionId ConnectionId
}

func (c Connection) EthAbiEncode() []byte {
	schema := abi.Schema{Fields: []abi.Field{
		{Type: abi.TypeUint8},
		{Type: abi.TypeUint32},
		{Type: abi.TypeUint32},
		{Type: abi.TypeUint32},
	}}
	bz, err := abi.Encode(schema, []any{
		uint8(c.State),
		uint32(c.ClientId),
		uint32(c.CounterpartyClientId),
		uint32(c.CounterpartyConnectionId),
	})
	if err != nil {
		panic(err)
	}
	return bz
}

type ConsensusStateUpdate struct {
	Height              Height
	ConsensusStateBytes []byte
	ClientStateBytes    []byte
}
