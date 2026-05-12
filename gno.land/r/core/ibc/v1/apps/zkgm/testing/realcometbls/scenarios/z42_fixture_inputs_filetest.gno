package main

import (
	"crypto/keccak256"
	"encoding/binary"
	"encoding/hex"

	core "gno.land/r/core/ibc/v1/core"
	zkgm "gno.land/r/gnoswap/ibc/v1/apps/zkgm"
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
	wrongVersionChannel := core.Channel{
		State:                 core.ChannelStateTryOpen,
		ConnectionId:          counterpartyConnectionId,
		CounterpartyChannelId: channelId,
		CounterpartyPortId:    core.NewBytes(cross, []byte(string(zkgm.ProxyAddress()))),
		Version:               "bad-version",
	}
	staleChannel := core.Channel{
		State:                 core.ChannelStateInit,
		ConnectionId:          counterpartyConnectionId,
		CounterpartyChannelId: channelId,
		CounterpartyPortId:    core.NewBytes(cross, []byte(string(zkgm.ProxyAddress()))),
		Version:               zkgm.Version,
	}

	connectionKey := connectionPath(counterpartyConnectionId)
	connectionValue := hash(connection.EthAbiEncode())
	channelKey := channelPath(counterpartyChannelId)
	wrongVersionValue := hash(wrongVersionChannel.EthAbiEncode())
	staleValue := hash(staleChannel.EthAbiEncode())

	printKV("z42_wrong_version_connection_try", connectionKey[:], connectionValue[:])
	printKV("z42_wrong_version_channel_try", channelKey[:], wrongVersionValue[:])
	printKV("z42_stale_connection_try", connectionKey[:], connectionValue[:])
	printKV("z42_stale_channel_try", channelKey[:], staleValue[:])
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
// z42_wrong_version_connection_try_key 0x05f3c8eef62e74b10b7ee910fcc73c8358000f692d9ce2341a989e008e45b35d
// z42_wrong_version_connection_try_value 0xff4fb67348c16e70c898c7cf43c460a684bc900d2b41e5a24ef6dcb294586034
// z42_wrong_version_channel_try_key 0x88601476d11616a71c5be67555bd1dff4b1cbf21533d2669b768b61518cfe1c3
// z42_wrong_version_channel_try_value 0xcd241e37da32c69a48f490b088006f8e4b664e2dd28a079730fa9e47c5fd943d
// z42_stale_connection_try_key 0x05f3c8eef62e74b10b7ee910fcc73c8358000f692d9ce2341a989e008e45b35d
// z42_stale_connection_try_value 0xff4fb67348c16e70c898c7cf43c460a684bc900d2b41e5a24ef6dcb294586034
// z42_stale_channel_try_key 0x88601476d11616a71c5be67555bd1dff4b1cbf21533d2669b768b61518cfe1c3
// z42_stale_channel_try_value 0x71eac86d6ae84d0093ae6a570909eb39ab5ee69ffc7ebb213e436fc9ddf24958
