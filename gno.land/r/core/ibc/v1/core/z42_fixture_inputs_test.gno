package core

import "testing"

func TestZ42HandshakeNegativeFixtureInputPaths(t *testing.T) {
	connection := Connection{
		State:                    ConnectionStateTryOpen,
		ClientId:                 99,
		CounterpartyClientId:     1,
		CounterpartyConnectionId: 1,
	}
	wrongVersionChannel := Channel{
		State:                 ChannelStateTryOpen,
		ConnectionId:          77,
		CounterpartyChannelId: 1,
		CounterpartyPortId:    Bytes("g1dyxy88p94acjnm8dmu9tfj2mv2ncvx83cagllu"),
		Version:               "bad-version",
	}
	staleChannel := Channel{
		State:                 ChannelStateInit,
		ConnectionId:          77,
		CounterpartyChannelId: 1,
		CounterpartyPortId:    Bytes("g1dyxy88p94acjnm8dmu9tfj2mv2ncvx83cagllu"),
		Version:               "ucs03-zkgm-0",
	}

	assertH256Hex(t, "z42 connection try key", ConnectionPath(77), "0x05f3c8eef62e74b10b7ee910fcc73c8358000f692d9ce2341a989e008e45b35d")
	assertH256Hex(t, "z42 connection try value", keccak(connection.EthAbiEncode()), "0xff4fb67348c16e70c898c7cf43c460a684bc900d2b41e5a24ef6dcb294586034")
	assertH256Hex(t, "z42 channel try key", ChannelPath(2), "0x88601476d11616a71c5be67555bd1dff4b1cbf21533d2669b768b61518cfe1c3")
	assertH256Hex(t, "z42 wrong version channel value", keccak(wrongVersionChannel.EthAbiEncode()), "0xcd241e37da32c69a48f490b088006f8e4b664e2dd28a079730fa9e47c5fd943d")
	assertH256Hex(t, "z42 stale channel value", keccak(staleChannel.EthAbiEncode()), "0x71eac86d6ae84d0093ae6a570909eb39ab5ee69ffc7ebb213e436fc9ddf24958")
}
