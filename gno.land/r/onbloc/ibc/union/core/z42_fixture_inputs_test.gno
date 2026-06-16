package core

import (
	"testing"

	"gno.land/p/onbloc/ibc/union/types"
)

func TestZ42HandshakeNegativeFixtureInputPaths(cur realm, t *testing.T) {
	connection := types.Connection{
		State:                    types.ConnectionStateTryOpen,
		ClientId:                 99,
		CounterpartyClientId:     1,
		CounterpartyConnectionId: 1,
	}
	wrongVersionChannel := types.Channel{
		State:                 types.ChannelStateTryOpen,
		ConnectionId:          77,
		CounterpartyChannelId: 1,
		CounterpartyPortId:    types.Bytes("g1dyxy88p94acjnm8dmu9tfj2mv2ncvx83cagllu"),
		Version:               "bad-version",
	}
	staleChannel := types.Channel{
		State:                 types.ChannelStateInit,
		ConnectionId:          77,
		CounterpartyChannelId: 1,
		CounterpartyPortId:    types.Bytes("g1dyxy88p94acjnm8dmu9tfj2mv2ncvx83cagllu"),
		Version:               "ucs03-zkgm-0",
	}

	assertH256Hex(t, "z42 connection try key", types.ConnectionPath(77), "0x05f3c8eef62e74b10b7ee910fcc73c8358000f692d9ce2341a989e008e45b35d")
	assertH256Hex(t, "z42 connection try value", keccak(connection.EthAbiEncode()), "0xff4fb67348c16e70c898c7cf43c460a684bc900d2b41e5a24ef6dcb294586034")
	assertH256Hex(t, "z42 channel try key", types.ChannelPath(2), "0x88601476d11616a71c5be67555bd1dff4b1cbf21533d2669b768b61518cfe1c3")
	assertH256Hex(t, "z42 wrong version channel value", keccak(wrongVersionChannel.EthAbiEncode()), "0xaf0c0adb7e156ac5070391fd9a86d138475ecd4302b250b36511098ca4d2a240")
	assertH256Hex(t, "z42 stale channel value", keccak(staleChannel.EthAbiEncode()), "0x0e108a322006151b61cf7e1fe81cf6f33c14817a2a92d3b7a5bc7a691790a539")
}
