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
	baseToken := mintWrappedVoucher(sender, 30)
	order := z.TokenOrderV2{
		Sender:      []byte(sender),
		Receiver:    []byte("counterparty-receiver"),
		BaseToken:   []byte(baseToken),
		BaseAmount:  u256.NewUint(30),
		QuoteToken:  []byte("quote"),
		QuoteAmount: u256.NewUint(30),
		Kind:        z.TOKEN_ORDER_KIND_ESCROW,
	}
	forward := z.Forward{
		Path:        forwardPath(1, 2),
		Instruction: mustOrderInstruction(order),
	}
	instr := mustForwardInstruction(forward)

	seq, _ := zkgm.Send(cross, clientID, uint64(time.Now().Add(time.Hour).Unix()), [32]byte{}, instr)
	key := impl.ChannelBalanceKeyV2(clientID, u256.Zero(), order.BaseToken, order.QuoteToken)
	println("sequence", seq)
	println("balance_after_send", zkgm.GetChannelBalanceV2(key).Dec())
	println("voucher_after_send", impl.VoucherBalanceOf(baseToken, address(sender)))

	err := zkgm.AsIBCApp().OnTimeoutPacket(cross, clientID, "07-tendermint-2", seq, mustPayload(instr))
	if err != nil {
		panic(err)
	}
	println("balance_after_timeout", balanceDec(key))
	println("voucher_after_timeout", impl.VoucherBalanceOf(baseToken, address(sender)))
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
	metaBytes := mustEncodeTokenMetadata(z.TokenMetadata{Implementation: []byte("grc20"), Initializer: []byte("init")})
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

func mustForwardInstruction(forward z.Forward) z.Instruction {
	forwardBytes, err := z.EncodeForward(forward)
	if err != nil {
		panic(err)
	}
	return z.Instruction{Version: z.INSTR_VERSION_0, Opcode: z.OP_FORWARD, Operand: forwardBytes}
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

func forwardPath(channels ...uint64) *u256.Uint {
	path := u256.Zero()
	for i, channel := range channels {
		path = new(u256.Uint).Or(path, new(u256.Uint).Lsh(u256.NewUint(channel), uint(32*i)))
	}
	return path
}

func balanceDec(key string) string {
	balance := zkgm.GetChannelBalanceV2(key)
	if balance == nil {
		return "0"
	}
	return balance.Dec()
}

// Output:
// sequence 1
// balance_after_send 30
// voucher_after_send 0
// balance_after_timeout 0
// voucher_after_timeout 30
