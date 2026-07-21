// PKGPATH: gno.land/r/onbloc/ibc/scenario/union/batch
package batch

// recv_batch_only_maker_child_reverts_filetest is the EXCEPTION-path batch scenario for
// only-maker propagation (S-7.2). A batch child that can only be settled by a market
// maker — here a TokenOrder whose quote token is not a known voucher, so the protocol
// cannot mint or unescrow it — yields ACK_ERR_ONLY_MAKER. Per the batch contract, an
// only-maker child is propagated as the parent batch acknowledgement and the remaining
// children are skipped; core does not recover recv panics, so OnRecvPacket turns that
// parent-level only-maker ack into a revert ("is only maker ack"). The whole batch
// rolls back atomically: the trailing OP_CALL never reaches the receiver and any
// earlier child mutation is undone. The only-maker child is placed first to make the
// "remaining children skipped" semantics explicit. The terminating panic is the
// assertion.

import (
	"chain"
	"testing"

	types "gno.land/p/onbloc/ibc/union/types"
	z "gno.land/p/onbloc/ibc/union/zkgm"

	u256 "gno.land/p/gnoswap/uint256"

	"gno.land/r/onbloc/ibc/union/access"
	zkgm "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm"
	_ "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/v1"
	core "gno.land/r/onbloc/ibc/union/core"
	_ "gno.land/r/onbloc/ibc/union/core/v1"
	mocklc "gno.land/r/onbloc/ibc/testing/mock/lightclient"
	_ "gno.land/r/onbloc/ibc/testing/mock/receiver"
)

const (
	coreImplPath  = "gno.land/r/onbloc/ibc/union/core/v1"
	zkgmImplPath  = "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/v1"
	mockLcPkgPath = "gno.land/r/onbloc/ibc/testing/mock/lightclient"
	receiverPath  = "gno.land/r/onbloc/ibc/testing/mock/receiver"

	adminAddr = address("g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5")
)

func main(cur realm) {
	println("[SCENARIO] 1. Bootstrap IBC host and open a zkgm channel")
	channelId := bootstrap(cur)
	println("")

	println("[SCENARIO] 2. Receive an OP_BATCH whose first child is only-maker: the whole batch reverts")
	recvOnlyMakerBatch(cur, channelId)
}

func bootstrap(cur realm) types.ChannelId {
	testing.SetRealm(testing.NewUserRealm(adminAddr))
	core.UpdateImpl(cross(cur), coreImplPath)
	zkgm.UpdateImpl(cross(cur), zkgmImplPath)
	zkgm.SetRateLimitDisabled(cross(cur), true)
	zkgm.RegisterCoreApp(cross(cur))
	access.GrantRole(cross(cur), access.RelayerRole, adminAddr)
	access.GrantRole(cross(cur), access.RelayerRole, chain.PackageAddress(mockLcPkgPath))

	mocklc.RegisterMockLightClient(cross(cur))
	core.CreateClient(cross(cur), core.NewMsgCreateClient(mocklc.MockClientType, nil, nil))
	clientId := types.ClientId(1)

	core.ConnectionOpenInit(cross(cur), core.NewMsgConnectionOpenInit(clientId, types.ClientId(99)))
	connectionId := types.ConnectionId(1)
	core.ConnectionOpenAck(cross(cur), core.NewMsgConnectionOpenAck(connectionId, types.ConnectionId(77), nil, 1))

	portId := []byte(zkgm.ProxyPkgPath())
	core.ChannelOpenInit(cross(cur), core.NewMsgChannelOpenInit(portId, portId, connectionId, zkgm.Version, "g1relayer"))
	channelId := types.ChannelId(1)
	core.ChannelOpenAck(cross(cur), core.NewMsgChannelOpenAck(channelId, zkgm.Version, types.ChannelId(2), nil, 1, "g1relayer"))
	return channelId
}

func recvOnlyMakerBatch(cur realm, channelId types.ChannelId) {
	batch := z.Batch{Instructions: []z.Instruction{
		// ESCROW with a quote token that is not a known voucher: the protocol cannot
		// fill it, so it falls to a market-maker fill and acks ACK_ERR_ONLY_MAKER.
		mustOrderInstruction(z.TokenOrderV2{
			Sender:      []byte("remote-sender"),
			Receiver:    []byte(adminAddr.String()),
			BaseToken:   []byte("uremote"),
			BaseAmount:  u256.NewUint(40),
			QuoteToken:  []byte("undeployed-quote-token"),
			QuoteAmount: u256.NewUint(40),
			Kind:        z.TOKEN_ORDER_KIND_ESCROW,
		}),
		// Skipped because the first child propagates only-maker.
		mustCallInstruction(z.Call{
			Sender:           []byte("remote-sender"),
			ContractAddress:  []byte(receiverPath),
			ContractCalldata: []byte("should-not-run"),
		}),
	}}
	packet := core.NewPacket(types.ChannelId(2), channelId, mustPacketData(mustBatchInstruction(batch)), types.Timestamp(1<<62))

	testing.SetRealm(testing.NewUserRealm(adminAddr))
	core.PacketRecv(cross(cur), core.NewMsgPacketRecv([]types.Packet{packet}, [][]byte{nil}, nil, 1))
}

// --- encoding helpers ---

func mustOrderInstruction(order z.TokenOrderV2) z.Instruction {
	operand, err := z.EncodeTokenOrderV2(order)
	if err != nil {
		panic(err)
	}
	return z.Instruction{Version: z.INSTR_VERSION_2, Opcode: z.OP_TOKEN_ORDER, Operand: operand}
}

func mustCallInstruction(call z.Call) z.Instruction {
	operand, err := z.EncodeCall(call)
	if err != nil {
		panic(err)
	}
	return z.Instruction{Version: z.INSTR_VERSION_0, Opcode: z.OP_CALL, Operand: operand}
}

func mustBatchInstruction(batch z.Batch) z.Instruction {
	operand, err := z.EncodeBatch(batch)
	if err != nil {
		panic(err)
	}
	return z.Instruction{Version: z.INSTR_VERSION_0, Opcode: z.OP_BATCH, Operand: operand}
}

func mustPacketData(instr z.Instruction) []byte {
	data, err := z.EncodeZkgmPacket(z.ZkgmPacket{Path: u256.Zero(), Instruction: instr})
	if err != nil {
		panic(err)
	}
	return data
}

// Output:
// [SCENARIO] 1. Bootstrap IBC host and open a zkgm channel
//
// [SCENARIO] 2. Receive an OP_BATCH whose first child is only-maker: the whole batch reverts

// Error:
// is only maker ack
