// PKGPATH: gno.land/r/onbloc/unionibc/v1/apps/zkgm/testing/realcometbls/scenarios
package scenarios

import (
	z "gno.land/p/onbloc/unionibc/zkgm"
	core "gno.land/r/onbloc/unionibc/v1/core"
	e2e "gno.land/r/onbloc/unionibc/v1/apps/zkgm/testing/e2e"
	"gno.land/r/onbloc/unionibc/v1/apps/zkgm/testing/mock"
	realcometbls "gno.land/r/onbloc/unionibc/v1/apps/zkgm/testing/realcometbls"
	_ "gno.land/r/onbloc/unionibc/v1/apps/zkgm/v0/loader"
)

const mockReceiverPath = "gno.land/r/onbloc/unionibc/v1/apps/zkgm/testing/mock"

func main(cur realm) {
	mock.Reset(cross(cur))
	mock.SetPanic(cross(cur), "boom")
	pair := realcometbls.OpenZ35CometBLSChannel(cross(cur))
	packet := callPacket(cur, pair, mockReceiverPath)

	core.PacketRecv(cross(cur), core.NewMsgPacketRecv(cross(cur), []core.Packet{packet}, nil, realcometbls.Z39CallPacketCommitmentProof(cross(cur)), core.Height(realcometbls.DevnetHeight-1)))
}

func callPacket(cur realm, pair realcometbls.ChannelPair, receiverPath string) core.Packet {
	call := z.Call{
		Sender:           []byte("sender"),
		ContractAddress:  []byte(receiverPath),
		ContractCalldata: []byte("calldata"),
	}
	return core.NewPacket(cross(cur), pair.Source, pair.Destination, e2e.MustPacketData(cross(cur), e2e.MustCallInstruction(cross(cur), call)), 0, core.Timestamp(0))
}

// Error:
// zkgm: only maker
