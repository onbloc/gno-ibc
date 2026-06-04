// PKGPATH: gno.land/r/onbloc/ibc/v1/apps/zkgm/testing/e2e/scenarios_denyimpl
package scenarios_denyimpl

import (
	z "gno.land/p/onbloc/ibc/zkgm"
	core "gno.land/r/core/ibc/v1/core"
	e2e "gno.land/r/onbloc/ibc/v1/apps/zkgm/testing/e2e"
	_ "gno.land/r/onbloc/ibc/v1/apps/zkgm/testing/loader_denyimpl"
)

func main(cur realm) {
	e2e.RegisterMockLightClient(cross(cur))
	parentChannel := e2e.OpenE2EChannel(cross(cur), core.ChannelId(101))
	childSource := e2e.OpenE2EChannel(cross(cur), core.ChannelId(102))

	forward := z.Forward{
		Path:             e2e.ForwardPath(cross(cur), uint32(parentChannel), uint32(childSource)),
		TimeoutTimestamp: 999,
		Instruction: e2e.MustCallInstruction(cross(cur), z.Call{
			Sender:           []byte("sender"),
			ContractAddress:  []byte("gno.land/r/onbloc/ibc/v1/apps/zkgm/testing/mock"),
			ContractCalldata: []byte("forward-core-frame"),
		}),
	}
	packet := core.NewPacket(cross(cur), core.ChannelId(1), parentChannel,
		e2e.MustPacketData(cross(cur), e2e.MustForwardInstruction(cross(cur), forward)), 0, core.Timestamp(0))

	core.PacketRecv(cross(cur), core.NewMsgPacketRecv(cross(cur), []core.Packet{packet}, nil, nil, core.Height(1)))
}

// Error:
// zkgm: only registered impl (gno.land/r/onbloc/ibc/v1/apps/zkgm/testing/loader_denyimpl) can batch send, got gno.land/r/onbloc/ibc/v1/apps/zkgm/v0/impl
