package main

import (
	"chain/runtime"
	"time"

	tmtesting "gno.land/p/aib/ibc/lightclient/tendermint/testing"
	"gno.land/p/aib/ibc/types"
	z "gno.land/p/gnoswap/ibc/zkgm"
	u256 "gno.land/p/gnoswap/uint256"
	"gno.land/r/aib/ibc/core"
	zkgm "gno.land/r/gnoswap/ibc/apps/zkgm"
	impl "gno.land/r/gnoswap/ibc/apps/zkgm/v0/impl"
	_ "gno.land/r/gnoswap/ibc/apps/zkgm/v0/loader"
)

func main() {
	clientID := setupClient()
	sender := runtime.OriginCaller().String()
	receiver := "g1wymu47drhr0kuq2098m792lytgtj2nyx77yrsm"
	baseToken := mintWrappedVoucher(sender, 50)
	order := z.TokenOrderV2{
		Sender:      []byte(sender),
		Receiver:    []byte(receiver),
		BaseToken:   []byte(baseToken),
		BaseAmount:  u256.NewUint(50),
		QuoteToken:  []byte("quote"),
		QuoteAmount: u256.NewUint(45),
		Kind:        z.TOKEN_ORDER_KIND_ESCROW,
	}
	instr := mustOrderInstruction(order)
	seq, _ := zkgm.Send(cross, clientID, uint64(time.Now().Add(time.Hour).Unix()), [32]byte{}, instr)
	sourceKey := impl.ChannelBalanceKeyV2(clientID, u256.Zero(), order.BaseToken, order.QuoteToken)

	res := zkgm.AsIBCApp().OnRecvPacket(cross, clientID, "client-dst", seq, mustPayload(instr))
	ack, err := z.DecodeAck(res.Acknowledgement)
	if err != nil {
		panic(err)
	}

	println("send_sequence", seq)
	println("source_escrow", zkgm.GetChannelBalanceV2(sourceKey).Dec())
	println("source_sender_balance", impl.VoucherBalanceOf(baseToken, address(sender)))
	println("recv_status", int(res.Status))
	println("recv_ack_tag", ack.Tag.Dec())
	println("dest_receiver_balance", impl.VoucherBalanceOf("quote", address(receiver)))
}

func setupClient() string {
	clientID := core.CreateClient(cross,
		tmtesting.NewClientState("chain-id-2", types.NewHeight(2, 2)),
		tmtesting.GenConsensusState(time.Now(), tmtesting.Hash("apphash"), tmtesting.GenValset().Hash()),
	)
	core.RegisterCounterparty(cross, clientID, [][]byte{[]byte("iavlStoreKey"), []byte("prefix2")}, "07-tendermint-2")
	return clientID
}

func mintWrappedVoucher(receiver string, amount uint64) string {
	metaBytes := mustEncodeTokenMetadata(z.TokenMetadata{Implementation: []byte("grc20"), Initializer: []byte("roundtrip")})
	order := z.TokenOrderV2{
		Receiver:    []byte(receiver),
		BaseToken:   []byte("ugnot"),
		BaseAmount:  u256.NewUint(amount),
		QuoteToken:  []byte("quote"),
		QuoteAmount: u256.NewUint(amount),
		Kind:        z.TOKEN_ORDER_KIND_INITIALIZE,
		Metadata:    metaBytes,
	}
	zkgm.AsIBCApp().OnRecvPacket(cross, "client-a", "client-b", 1, mustPayload(mustOrderInstruction(order)))
	return impl.PredictWrappedTokenV2("client-b", order.BaseToken, impl.MetadataImage(mustDecodeTokenMetadata(metaBytes)))
}

func mustPayload(instr z.Instruction) types.Payload {
	packetBytes, err := z.EncodeZkgmPacket(z.ZkgmPacket{Path: u256.Zero(), Instruction: instr})
	if err != nil {
		panic(err)
	}
	return types.Payload{Value: packetBytes}
}

func mustOrderInstruction(order z.TokenOrderV2) z.Instruction {
	orderBytes, err := z.EncodeTokenOrderV2(order)
	if err != nil {
		panic(err)
	}
	return z.Instruction{Version: z.INSTR_VERSION_2, Opcode: z.OP_TOKEN_ORDER, Operand: orderBytes}
}

func mustEncodeTokenMetadata(meta z.TokenMetadata) []byte {
	bz, err := z.EncodeTokenMetadata(meta)
	if err != nil {
		panic(err)
	}
	return bz
}

func mustDecodeTokenMetadata(bz []byte) z.TokenMetadata {
	meta, err := z.DecodeTokenMetadata(bz)
	if err != nil {
		panic(err)
	}
	return meta
}

// Output:
// send_sequence 1
// source_escrow 50
// source_sender_balance 0
// recv_status 1
// recv_ack_tag 1
// dest_receiver_balance 45
