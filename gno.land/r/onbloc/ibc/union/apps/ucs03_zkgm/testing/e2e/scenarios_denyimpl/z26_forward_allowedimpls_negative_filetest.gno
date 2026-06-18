// PKGPATH: gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/testing/e2e/scenarios_denyimpl
package scenarios_denyimpl

import (
	types "gno.land/p/onbloc/ibc/union/types"

	z "gno.land/p/onbloc/ibc/union/zkgm"
	zkgm "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm"
	e2e "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/testing/e2e"
	impl "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/v1"
	core "gno.land/r/onbloc/ibc/union/core"
)

func main(cur realm) {
	zkgm.UpdateImpl(cross(cur), zkgm.NewUpdateRequest(cross(cur), impl.New(cross(cur)), []string{
		"gno.land/r/onbloc/ibc/union/core",
		"gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm",
		"gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/testing/e2e",
		"gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/testing/realcometbls",
	}))
	zkgm.RegisterCoreApp(cross(cur))

	e2e.RegisterMockLightClient(cross(cur))
	parentChannel := e2e.OpenE2EChannel(cross(cur), types.ChannelId(101))
	childSource := e2e.OpenE2EChannel(cross(cur), types.ChannelId(102))

	forward := z.Forward{
		Path:             e2e.ForwardPath(cross(cur), uint32(parentChannel), uint32(childSource)),
		TimeoutTimestamp: 999,
		Instruction: e2e.MustCallInstruction(cross(cur), z.Call{
			Sender:           []byte("sender"),
			ContractAddress:  []byte("gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/testing/mock"),
			ContractCalldata: []byte("forward-core-frame"),
		}),
	}
	packet := core.NewPacket(cross(cur), types.ChannelId(1), parentChannel,
		e2e.MustPacketData(cross(cur), e2e.MustForwardInstruction(cross(cur), forward)), types.Timestamp(0))

	core.PacketRecv(cross(cur), types.NewMsgPacketRecv([]types.Packet{packet}, nil, nil, 1))
}

// Error:
// zkgm: caller is not an authorized impl for set in-flight packet: gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/v1
