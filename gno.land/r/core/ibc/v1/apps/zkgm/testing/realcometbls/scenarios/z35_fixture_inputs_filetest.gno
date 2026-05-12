package main

import (
	"crypto/keccak256"
	"encoding/binary"
	"encoding/hex"

	z "gno.land/p/gnoswap/ibc/zkgm"
	u256 "gno.land/p/gnoswap/uint256"
	core "gno.land/r/core/ibc/v1/core"
	zkgm "gno.land/r/gnoswap/ibc/v1/apps/zkgm"
	e2e "gno.land/r/gnoswap/ibc/v1/apps/zkgm/testing/e2e"
)

func main() {
	clientId := core.ClientId(1)
	counterpartyClientId := core.ClientId(99)
	connectionId := core.ConnectionId(1)
	counterpartyConnectionId := core.ConnectionId(77)
	channelId := core.ChannelId(1)
	counterpartyChannelId := core.ChannelId(2)

	connection := core.Connection{
		State:                    core.ConnectionStateTryOpen,
		ClientId:                 counterpartyClientId,
		CounterpartyClientId:     clientId,
		CounterpartyConnectionId: connectionId,
	}
	channel := core.Channel{
		State:                 core.ChannelStateTryOpen,
		ConnectionId:          counterpartyConnectionId,
		CounterpartyChannelId: channelId,
		CounterpartyPortId:    core.NewBytes(cross, []byte(string(zkgm.ProxyAddress()))),
		Version:               zkgm.Version,
	}
	order := z.TokenOrderV2{
		Sender:      []byte("sender"),
		Receiver:    []byte("g1wymu47drhr0kuq2098m792lytgtj2nyx77yrsm"),
		BaseToken:   []byte("ugnot"),
		BaseAmount:  u256.NewUint(100),
		QuoteToken:  []byte("ibc/quote"),
		QuoteAmount: u256.NewUint(21),
		Kind:        z.TOKEN_ORDER_KIND_ESCROW,
	}
	packet := core.NewPacket(
		cross,
		core.Sequence(7),
		counterpartyChannelId,
		channelId,
		e2e.MustPacketData(cross, e2e.MustTokenOrderInstruction(cross, order)),
		core.Timestamp(0),
	)

	connectionKey := connectionPath(counterpartyConnectionId)
	connectionValue := hash(connection.EthAbiEncode())
	channelKey := channelPath(counterpartyChannelId)
	channelValue := hash(channel.EthAbiEncode())
	packetKey := packetCommitmentPath(packet)
	packetValue := core.COMMITMENT_MAGIC

	printKV("connection_try", connectionKey[:], connectionValue[:])
	printKV("channel_try", channelKey[:], channelValue[:])
	printKV("packet_commitment", packetKey[:], packetValue[:])
}

func hash(bz []byte) [32]byte {
	return keccak256.Sum256(bz)
}

func connectionPath(connectionId core.ConnectionId) [32]byte {
	return hash(concat(core.CONNECTIONS[:], u32ToH256(uint32(connectionId))))
}

func channelPath(channelId core.ChannelId) [32]byte {
	return hash(concat(core.CHANNELS[:], u32ToH256(uint32(channelId))))
}

func packetCommitmentPath(packet core.Packet) [32]byte {
	batchHash := hash(packet.EthAbiEncode())
	return hash(concat(core.PACKETS[:], batchHash[:]))
}

func u32ToH256(n uint32) []byte {
	bz := [32]byte{}
	binary.BigEndian.PutUint32(bz[28:], n)
	return bz[:]
}

func concat(parts ...[]byte) []byte {
	size := 0
	for _, p := range parts {
		size += len(p)
	}
	out := make([]byte, 0, size)
	for _, p := range parts {
		out = append(out, p...)
	}
	return out
}

func printKV(name string, key []byte, value []byte) {
	println(name+"_key", "0x"+hex.EncodeToString(key))
	println(name+"_value", "0x"+hex.EncodeToString(value))
}

// Output:
// connection_try_key 0x05f3c8eef62e74b10b7ee910fcc73c8358000f692d9ce2341a989e008e45b35d
// connection_try_value 0xff4fb67348c16e70c898c7cf43c460a684bc900d2b41e5a24ef6dcb294586034
// channel_try_key 0x88601476d11616a71c5be67555bd1dff4b1cbf21533d2669b768b61518cfe1c3
// channel_try_value 0xfa3c11d224a164cd0beca2b6756128dc1531714a75813e9c2b5840bd8f2a8347
// packet_commitment_key 0x6cdd701570bc5e4ca75bc46a6499076fcd9d3485329063a1cf23cf6ee66a5d10
// packet_commitment_value 0x0100000000000000000000000000000000000000000000000000000000000000
