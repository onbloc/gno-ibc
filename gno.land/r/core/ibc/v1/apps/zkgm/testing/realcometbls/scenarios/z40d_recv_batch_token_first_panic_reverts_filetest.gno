// PKGPATH: gno.land/r/onbloc/unionibc/v1/apps/zkgm/testing/realcometbls/scenarios
package scenarios

import (
	u256 "gno.land/p/gnoswap/uint256"

	z "gno.land/p/onbloc/unionibc/zkgm"
	"gno.land/r/onbloc/unionibc/v1/core"

	"gno.land/r/onbloc/unionibc/v1/apps/zkgm/testing/e2e"
	"gno.land/r/onbloc/unionibc/v1/apps/zkgm/testing/mock"
	"gno.land/r/onbloc/unionibc/v1/apps/zkgm/testing/realcometbls"
	"gno.land/r/onbloc/unionibc/v1/apps/zkgm/v0/impl"

	_ "gno.land/r/onbloc/unionibc/v1/apps/zkgm/v0/loader"
)

const mockReceiverPath = "gno.land/r/onbloc/unionibc/v1/apps/zkgm/testing/mock"

func main(cur realm) {
	mock.Reset(cross(cur))
	mock.SetPanic(cross(cur), "boom")
	pair := realcometbls.OpenZ40TokenFirstCometBLSChannel(cross(cur))
	packet := tokenFirstPanicBatchPacket(cur, pair)

	core.PacketRecv(cross(cur), core.NewMsgPacketRecv(cross(cur), []core.Packet{packet}, nil, realcometbls.Z40TokenFirstPanicBatchPacketCommitmentProof(cross(cur)), core.Height(realcometbls.DevnetHeight-1)))
}

func tokenFirstPanicBatchPacket(cur realm, pair realcometbls.ChannelPair) core.Packet {
	quoteToken := impl.PredictWrappedTokenV1(u256.Zero(), uint32(pair.Destination), []byte("ugnot"))
	batch := z.Batch{Instructions: []z.Instruction{
		e2e.MustTokenOrderInstruction(cross(cur), z.TokenOrderV2{
			Sender:      []byte("sender"),
			Receiver:    []byte("g1wymu47drhr0kuq2098m792lytgtj2nyx77yrsm"),
			BaseToken:   []byte("ugnot"),
			BaseAmount:  u256.NewUint(100),
			QuoteToken:  []byte(quoteToken),
			QuoteAmount: u256.NewUint(21),
			Kind:        z.TOKEN_ORDER_KIND_ESCROW,
		}),
		e2e.MustCallInstruction(cross(cur), z.Call{
			Sender:           []byte("sender"),
			ContractAddress:  []byte(mockReceiverPath),
			ContractCalldata: []byte("panic-call"),
		}),
	}}
	return core.NewPacket(cross(cur), pair.Source, pair.Destination, e2e.MustPacketData(cross(cur), e2e.MustBatchInstruction(cross(cur), batch)), 0, core.Timestamp(0))
}

// Error:
// zkgm: only-maker acknowledgement requires retry
