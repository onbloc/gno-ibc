package core

import (
	"strconv"
)

type ClientId uint32

func (id ClientId) String() string {
	return strconv.FormatUint(uint64(id), 10)
}

type ConnectionId uint32

type ChannelId uint32

type Timestamp uint64

type Height uint64

type Bytes []byte

type H256 [32]byte

type ClientType string

type Packet struct {
    source_channel_id ChannelId
    destination_channel_id ChannelId
    data Bytes
    // timeout_height MustBeZero
    timeout_timestamp Timestamp
}

type Channel struct {
    state ChannelState
    connection_id ConnectionId
    counterparty_channel_id ChannelId
    counterparty_port_id Bytes
    version string
}

type Connection struct {
    state ConnectionState
    client_id ClientId
    counterparty_client_id ClientId
    counterparty_connection_id ConnectionId
}

type ConnectionState uint8

const (
	ConnectionStateUnspecified ConnectionState = 0
	ConnectionStateInit ConnectionState = 1
	ConnectionStateTryOpen ConnectionState = 2
	ConnectionStateOpen ConnectionState = 3
)

type ChannelState uint8

const (
	ChannelStateUnspecified ChannelState = 0
	ChannelStateInit ChannelState = 1
	ChannelStateTryOpen ChannelState = 2
	ChannelStateOpen ChannelState = 3
	ChannelStateClosed ChannelState = 4
)
