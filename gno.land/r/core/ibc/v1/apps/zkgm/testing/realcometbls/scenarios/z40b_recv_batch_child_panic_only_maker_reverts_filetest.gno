// PKGPATH: gno.land/r/onbloc/unionibc/v1/apps/zkgm/testing/realcometbls/scenarios
package scenarios

import (
	z "gno.land/p/onbloc/unionibc/zkgm"
	u256 "gno.land/p/gnoswap/uint256"
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
	receiver := "g1wymu47drhr0kuq2098m792lytgtj2nyx77yrsm"
	packet := panicBatchPacket(cur, pair, receiver)

	core.PacketRecv(cross(cur), core.NewMsgPacketRecv(cross(cur), []core.Packet{packet}, nil, realcometbls.Z40PanicBatchPacketCommitmentProof(cross(cur)), core.Height(realcometbls.DevnetHeight-1)))
}

func panicBatchPacket(cur realm, pair realcometbls.ChannelPair, receiver string) core.Packet {
	batch := z.Batch{Instructions: []z.Instruction{
		e2e.MustCallInstruction(cross(cur), z.Call{
			Sender:           []byte("sender"),
			ContractAddress:  []byte(mockReceiverPath),
			ContractCalldata: []byte("panic-call"),
		}),
		e2e.MustTokenOrderInstruction(cross(cur), z.TokenOrderV2{
			Sender:      []byte("sender"),
			Receiver:    []byte(receiver),
			BaseToken:   []byte("ugnot"),
			BaseAmount:  u256.NewUint(100),
			QuoteToken:  []byte("ibc/batch-panic-quote"),
			QuoteAmount: u256.NewUint(21),
			Kind:        z.TOKEN_ORDER_KIND_ESCROW,
		}),
	}}
	return core.NewPacket(cross(cur), pair.Source, pair.Destination, e2e.MustPacketData(cross(cur), e2e.MustBatchInstruction(cross(cur), batch)), 0, core.Timestamp(0))
}

// Error:
// zkgm: only maker
