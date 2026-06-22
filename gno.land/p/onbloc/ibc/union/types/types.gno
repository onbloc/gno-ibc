package types

import (
	"encoding/hex"
	"strconv"
)

type ClientId uint32

func (id ClientId) String() string {
	return strconv.FormatUint(uint64(id), 10)
}

type ConnectionId uint32

func (id ConnectionId) String() string {
	return strconv.FormatUint(uint64(id), 10)
}

type Timestamp uint64

func (ts Timestamp) String() string {
	return strconv.FormatUint(uint64(ts), 10)
}

type Bytes []byte

func (bz Bytes) String() string {
	return "0x" + hex.EncodeToString(bz)
}

func (bz Bytes) Bytes() []byte {
	out := make([]byte, len(bz))
	copy(out, bz)
	return []byte(out)
}

type H256 [32]byte

func (h H256) String() string {
	return "0x" + hex.EncodeToString(h[:])
}

type ClientType string

func (ct ClientType) String() string {
	return string(ct)
}
