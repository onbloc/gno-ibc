package main

import (
	"gno.land/p/aib/ibc/types"
	z "gno.land/p/gnoswap/ibc/zkgm"
	u256 "gno.land/p/gnoswap/uint256"
	zkgm "gno.land/r/gnoswap/ibc/apps/zkgm"
	"gno.land/r/gnoswap/ibc/apps/zkgm/testing/mock"
	impl "gno.land/r/gnoswap/ibc/apps/zkgm/v0/impl"
	_ "gno.land/r/gnoswap/ibc/apps/zkgm/v0/loader"
)

const mockReceiverPath = "gno.land/r/gnoswap/ibc/apps/zkgm/testing/mock"

func main() {
	mock.Reset(cross)

	metaBytes := mustEncodeTokenMetadata(z.TokenMetadata{
		Implementation: []byte("grc20"),
		Initializer:    []byte("init"),
	})
	image := impl.MetadataImage(mustDecodeTokenMetadata(metaBytes))
	ibcDenom := impl.PredictWrappedTokenV2(u256.NewUint(7), 1, []byte("ugnot"), image)
	receiver := "g1wymu47drhr0kuq2098m792lytgtj2nyx77yrsm"
	order := z.TokenOrderV2{
		Receiver:    []byte(receiver),
		BaseToken:   []byte("ugnot"),
		BaseAmount:  u256.NewUint(95),
		QuoteToken:  []byte(ibcDenom),
		QuoteAmount: u256.NewUint(95),
		Kind:        z.TOKEN_ORDER_KIND_INITIALIZE,
		Metadata:    metaBytes,
	}

	res := zkgm.AsIBCApp().OnRecvPacket(cross, "client-a", "client-1", 1, mustBatchPayload(z.Batch{
		Instructions: []z.Instruction{
			mustCallInstruction("call-payload"),
			mustOrderInstruction(order),
		},
	}))
	outerAck, err := z.DecodeAck(res.Acknowledgement)
	if err != nil {
		panic(err)
	}
	batchAck, err := z.DecodeBatchAck(outerAck.InnerAck)
	if err != nil {
		panic(err)
	}
	println("status", int(res.Status))
	println("outer_ack_tag", outerAck.Tag.Dec())
	println("child_acks", len(batchAck.Acknowledgements))
	println("mock_calls", mock.Calls())
	println("last_calldata", mock.LastCalldata(cross))
	println("voucher_balance", impl.VoucherBalanceOf(ibcDenom, address(receiver)))
}

func mustBatchPayload(batch z.Batch) types.Payload {
	batchBytes, err := z.EncodeBatch(batch)
	if err != nil {
		panic(err)
	}
	packetBytes, err := z.EncodeZkgmPacket(z.ZkgmPacket{
		Path: u256.NewUint(7),
		Instruction: z.Instruction{
			Version: z.INSTR_VERSION_0,
			Opcode:  z.OP_BATCH,
			Operand: batchBytes,
		},
	})
	if err != nil {
		panic(err)
	}
	return types.Payload{Value: packetBytes}
}

func mustCallInstruction(calldata string) z.Instruction {
	callBytes, err := z.EncodeCall(z.Call{
		Sender:           []byte("sender"),
		ContractAddress:  []byte(mockReceiverPath),
		ContractCalldata: []byte(calldata),
	})
	if err != nil {
		panic(err)
	}
	return z.Instruction{Version: z.INSTR_VERSION_0, Opcode: z.OP_CALL, Operand: callBytes}
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
// status 1
// outer_ack_tag 1
// child_acks 2
// mock_calls 1
// last_calldata call-payload
// voucher_balance 95
