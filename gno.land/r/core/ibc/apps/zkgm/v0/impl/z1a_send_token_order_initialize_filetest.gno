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
	baseToken := mintWrappedVoucher(sender, 100)
	order := z.TokenOrderV2{
		Sender:      []byte(sender),
		Receiver:    []byte("counterparty-receiver"),
		BaseToken:   []byte(baseToken),
		BaseAmount:  u256.NewUint(100),
		QuoteToken:  []byte("quote"),
		QuoteAmount: u256.NewUint(95),
		Kind:        z.TOKEN_ORDER_KIND_INITIALIZE,
		Metadata:    mustEncodeTokenMetadata(z.TokenMetadata{Implementation: []byte("grc20"), Initializer: []byte("remote")}),
	}
	instr := mustOrderInstruction(order)

	seq, hash := zkgm.Send(cross, clientID, uint64(time.Now().Add(time.Hour).Unix()), [32]byte{}, instr)
	key := impl.ChannelBalanceKeyV2(clientID, u256.Zero(), order.BaseToken, order.QuoteToken)
	_, inFlight := zkgm.GetInFlightPacket(zkgm.InFlightKey(hash))

	println("sequence", seq)
	println("packet_hash_len", len(hash))
	println("channel_balance", zkgm.GetChannelBalanceV2(key).Dec())
	println("voucher_balance", impl.VoucherBalanceOf(baseToken, address(sender)))
	println("in_flight", inFlight)
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
	quoteToken := impl.PredictWrappedTokenV2(nil, 1, []byte("ugnot"), impl.MetadataImage(mustDecodeTokenMetadata(metaBytes)))
	order := z.TokenOrderV2{
		Receiver:    []byte(receiver),
		BaseToken:   []byte("ugnot"),
		BaseAmount:  u256.NewUint(amount),
		QuoteToken:  []byte(quoteToken),
		QuoteAmount: u256.NewUint(amount),
		Kind:        z.TOKEN_ORDER_KIND_INITIALIZE,
		Metadata:    metaBytes,
	}
	zkgm.AsIBCApp().OnRecvPacket(cross, "client-a", "client-1", 1, mustPayload(mustOrderInstruction(order)))
	return quoteToken
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
// sequence 1
// packet_hash_len 32
// channel_balance 100
// voucher_balance 0
// in_flight true
