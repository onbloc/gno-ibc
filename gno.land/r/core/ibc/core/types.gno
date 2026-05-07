package core

import (
	"encoding/hex"
	"strconv"

	"gno.land/p/gnoswap/encoding/abi"
	// u256 "gno.land/p/gnoswap/uint256"
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

type Height uint64

func (h Height) String() string {
	return strconv.FormatUint(uint64(h), 10)
}

// TODO: Use this everywhere
type Bytes []byte

func (bz Bytes) String() string {
	return "0x" + hex.EncodeToString(bz)
}

type H256 [32]byte

func (h H256) String() string {
	return "0x" + hex.EncodeToString(h[:])
}

type ClientType string

type Packet struct {
	SourceChannelId      ChannelId
	DestinationChannelId ChannelId
	Data                 Bytes
	// TimeoutHeight MustBeZero
	TimeoutTimestamp Timestamp
}

func (c Packet) EthAbiEncode() []byte {
	PacketSchema := abi.Schema{Fields: []abi.Field{
		{Type: abi.TypeUint32},
		{Type: abi.TypeUint32},
		{Type: abi.TypeBytes},
		{Type: abi.TypeUint64},
		{Type: abi.TypeUint64},
	}}

	bz, err := abi.Encode(PacketSchema, []any{
		c.SourceChannelId,
		c.DestinationChannelId,
		c.Data,
		uint64(0),
		c.TimeoutTimestamp,
	})
	if err != nil {
		panic(err)
	}

	return bz
}

type Channel struct {
	State                 ChannelState
	ConnectionId          ConnectionId
	CounterpartyChannelId ChannelId
	CounterpartyPortId    Bytes
	Version               string
}

func (c Channel) EthAbiEncode() []byte {
	ChannelSchema := abi.Schema{Fields: []abi.Field{
		{Type: abi.TypeUint8},
		{Type: abi.TypeUint32},
		{Type: abi.TypeUint32},
		{Type: abi.TypeBytes},
		{Type: abi.TypeString},
	}}

	bz, err := abi.Encode(ChannelSchema, []any{
		c.State,
		c.ConnectionId,
		c.CounterpartyChannelId,
		c.CounterpartyPortId,
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
	ConnectionSchema := abi.Schema{Fields: []abi.Field{
		{Type: abi.TypeUint8},
		{Type: abi.TypeUint32},
		{Type: abi.TypeBytes32},
		{Type: abi.TypeBytes32},
	}}

	bz, err := abi.Encode(ConnectionSchema, []any{
		c.State,
		c.ClientId,
		c.CounterpartyClientId,
		c.CounterpartyConnectionId,
	})
	if err != nil {
		panic(err)
	}

	return bz
}

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

type Status uint8

const (
	StatusUnknown = 0
	StatusActive  = 1
	StatusExpired = 2
	StatusFrozen  = 3
)

type ConsensusStateUpdate struct {
	Height              Height
	ConsensusStateBytes []byte
	ClientStateBytes    []byte
}
