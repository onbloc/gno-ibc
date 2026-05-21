package main

import (
	"crypto/keccak256"
	"encoding/hex"

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
	channel := core.Channel{
		State:                 core.ChannelStateTryOpen,
		ConnectionId:          counterpartyConnectionID,
		CounterpartyChannelId: channelID,
		CounterpartyPortId:    portID,
		Version:               zkgm.Version,
	}
	channelValue := hash(channel.EthAbiEncode())

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
