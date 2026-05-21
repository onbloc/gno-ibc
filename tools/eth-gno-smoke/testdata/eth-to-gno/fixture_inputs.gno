package main

import (
	"crypto/keccak256"
	"encoding/binary"
	"encoding/hex"

	"gno.land/p/core/encoding/abi"
	z "gno.land/p/gnoswap/ibc/zkgm"
	core "gno.land/r/core/ibc/v1/core"
	zkgm "gno.land/r/gnoswap/ibc/v1/apps/zkgm"
	e2e "gno.land/r/gnoswap/ibc/v1/apps/zkgm/testing/e2e"
	_ "gno.land/r/gnoswap/ibc/v1/apps/zkgm/v0/loader"
)

func main() {
	lensClientID := core.ClientId(2)
	connectionID := core.ConnectionId(1)
	counterpartyClientID := core.ClientId(99)
	counterpartyConnectionID := core.ConnectionId(77)
	channelID := core.ChannelId(1)
	counterpartyChannelID := core.ChannelId(1)
	portID := []byte(zkgm.ProxyPkgPath())

	conn := core.Connection{
		State:                    core.ConnectionStateTryOpen,
		ClientId:                 counterpartyClientID,
		CounterpartyClientId:     lensClientID,
		CounterpartyConnectionId: connectionID,
	}
	connPath := core.ConnectionPath(counterpartyConnectionID)
	connValue := hash(conn.EthAbiEncode())

	channelPath := core.ChannelPath(counterpartyChannelID)
	channelValue := hash(encodeChannel(core.ChannelStateTryOpen, counterpartyConnectionID, channelID, portID, zkgm.Version))

	call := z.Call{Sender: []byte("eth-sender"), ContractAddress: []byte("gno.land/r/gnoswap/ibc/v1/apps/zkgm/testing/mock"), ContractCalldata: []byte("hello")}
	packet := core.Packet{
		SourceChannelId:      counterpartyChannelID,
		DestinationChannelId: channelID,
		Data:                 e2e.MustPacketData(cross, e2e.MustCallInstruction(cross, call)),
		TimeoutTimestamp:     core.Timestamp(0),
	}
	packetPath := core.BatchPacketsPath(core.CommitPackets([]core.Packet{packet}))

	println("conn_ack_path", connPath.String())
	println("conn_ack_value", connValue.String())
	println("channel_ack_path", channelPath.String())
	println("channel_ack_value", channelValue.String())
	println("packet_path", packetPath.String())
	println("packet_value", core.COMMITMENT_MAGIC.String())
	println("packet_data_hex", "0x"+hex.EncodeToString(packet.Data))
	println("packet_timeout_timestamp", packet.TimeoutTimestamp.String())
}

func hash(bz []byte) core.H256 {
	sum := keccak256.Sum256(bz)
	var out core.H256
	copy(out[:], sum[:])
	return out
}

func encodeChannel(state core.ChannelState, connectionID core.ConnectionId, counterpartyChannelID core.ChannelId, counterpartyPortID []byte, version string) []byte {
	schema := abi.Schema{Fields: []abi.Field{
		{Type: abi.TypeUint8},
		{Type: abi.TypeUint32},
		{Type: abi.TypeUint32},
		{Type: abi.TypeBytes},
		{Type: abi.TypeString},
	}}
	bz, err := abi.Encode(schema, []any{
		uint8(state),
		uint32(connectionID),
		uint32(counterpartyChannelID),
		counterpartyPortID,
		version,
	})
	if err != nil {
		panic(err)
	}
	return encodeTopLevelDynamic(bz)
}

func encodeTopLevelDynamic(encoded []byte) []byte {
	out := make([]byte, 0, 32+len(encoded))
	return append(append(out, u64ToH256(32)...), encoded...)
}

func u64ToH256(n uint64) []byte {
	bz := [32]byte{}
	binary.BigEndian.PutUint64(bz[24:], n)
	return bz[:]
}
