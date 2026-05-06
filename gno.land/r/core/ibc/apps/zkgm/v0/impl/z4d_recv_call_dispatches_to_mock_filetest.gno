package main

import (
	"gno.land/p/aib/ibc/types"
	z "gno.land/p/gnoswap/ibc/zkgm"
	u256 "gno.land/p/gnoswap/uint256"
	zkgm "gno.land/r/gnoswap/ibc/apps/zkgm"
	"gno.land/r/gnoswap/ibc/apps/zkgm/testing/mock"
	_ "gno.land/r/gnoswap/ibc/apps/zkgm/v0/loader"
)

const mockReceiverPath = "gno.land/r/gnoswap/ibc/apps/zkgm/testing/mock"

func main() {
	mock.Reset(cross)

	res := zkgm.AsIBCApp().OnRecvPacket(cross, "client-a", "client-b", 1, mustCallPayload(z.Call{
		Sender:           []byte("sender"),
		ContractAddress:  []byte(mockReceiverPath),
		ContractCalldata: []byte("calldata"),
	}))
	ack, err := z.DecodeAck(res.Acknowledgement)
	if err != nil {
		panic(err)
	}

	println("status", int(res.Status))
	println("ack_tag", ack.Tag.Dec())
	println("mock_calls", mock.Calls())
	println("source_channel", mock.LastSourceChannel(cross))
	println("destination_channel", mock.LastDestinationChannel(cross))
	println("sender", mock.LastSender(cross))
	println("calldata", mock.LastCalldata(cross))
	println("caller", mock.LastCaller(cross))
	println("relayer", mock.LastRelayer(cross))
	println("path", mock.LastPathDec(cross))
	println("proxy_account_len", len(mock.LastProxyAccount(cross)))
}

func mustCallPayload(call z.Call) types.Payload {
	callBytes, err := z.EncodeCall(call)
	if err != nil {
		panic(err)
	}
	packetBytes, err := z.EncodeZkgmPacket(z.ZkgmPacket{
		Salt: [32]byte{},
		Path: u256.NewUint(7),
		Instruction: z.Instruction{
			Version: z.INSTR_VERSION_0,
			Opcode:  z.OP_CALL,
			Operand: callBytes,
		},
	})
	if err != nil {
		panic(err)
	}
	return types.Payload{
		SourcePort:      "ucs03-zkgm-0",
		DestinationPort: "ucs03-zkgm-0",
		Version:         z.PROTOCOL_VERSION,
		Encoding:        "application/octet-stream",
		Value:           packetBytes,
	}
}

// Output:
// status 1
// ack_tag 1
// mock_calls 1
// source_channel client-a
// destination_channel client-b
// sender sender
// calldata calldata
// caller g1wymu47drhr0kuq2098m792lytgtj2nyx77yrsm
// relayer g1wymu47drhr0kuq2098m792lytgtj2nyx77yrsm
// path 7
// proxy_account_len 45
