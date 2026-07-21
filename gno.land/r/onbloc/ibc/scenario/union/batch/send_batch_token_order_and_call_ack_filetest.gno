// PKGPATH: gno.land/r/onbloc/ibc/scenario/union/batch
package batch

// send_batch_token_order_and_call_ack_filetest sends a batch of [native ESCROW
// TokenOrder, OP_CALL] and acknowledges it with a batch success ack. verifyCall
// (call.gno:13-23) requires call.Sender to match the send-time caller, so the
// Call child is verified/escrowed alongside the TokenOrder child in the same
// verifyBatch pass. On ack, acknowledgeCall (call.gno:103-109) is a pure no-op
// for a non-eureka call — it neither invokes the receiver nor touches any
// state — so the only observable effect is the TokenOrder child's escrow
// staying locked (protocol-fill ack).

import (
	"chain"
	"chain/banker"
	"testing"

	types "gno.land/p/onbloc/ibc/union/types"
	z "gno.land/p/onbloc/ibc/union/zkgm"

	u256 "gno.land/p/gnoswap/uint256"

	"gno.land/p/nt/ufmt/v0"

	mocklc "gno.land/r/onbloc/ibc/testing/mock/lightclient"
	"gno.land/r/onbloc/ibc/union/access"
	zkgm "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm"
	_ "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/v1"
	core "gno.land/r/onbloc/ibc/union/core"
	_ "gno.land/r/onbloc/ibc/union/core/v1"
)

const (
	coreImplPath  = "gno.land/r/onbloc/ibc/union/core/v1"
	zkgmImplPath  = "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/v1"
	mockLcPkgPath = "gno.land/r/onbloc/ibc/testing/mock/lightclient"
	receiverPath  = "gno.land/r/onbloc/ibc/testing/mock/receiver"

	adminAddr  = address("g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5")
	senderAddr = address("g1wymu47drhr0kuq2098m792lytgtj2nyx77yrsm")
)

func main(cur realm) {
	println("[SCENARIO] 1. Bootstrap IBC host and open a zkgm channel")
	channelId := bootstrap(cur)
	println("")

	println("[SCENARIO] 2. Send a batch of [native ESCROW 40ugnot, OP_CALL]")
	sendPacket := sendBatch(cur, channelId)
	println("")

	println("[SCENARIO] 3. Acknowledge the batch: TokenOrder protocol-fills, Call ack is a no-op")
	acknowledgeBatch(cur, sendPacket)
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

func sendBatch(cur realm, channelId types.ChannelId) types.Packet {
	proxy := zkgm.ProxyAddress()
	testing.IssueCoins(proxy, chain.NewCoins(chain.NewCoin("ugnot", 40)))

	batch := z.Batch{Instructions: []z.Instruction{
		mustOrderInstruction(z.TokenOrderV2{
			Sender:      []byte(senderAddr.String()),
			Receiver:    []byte("remote-receiver"),
			BaseToken:   []byte("ugnot"),
			BaseAmount:  u256.NewUint(40),
			QuoteToken:  []byte("remote-ugnot"),
			QuoteAmount: u256.NewUint(40),
			Kind:        z.TOKEN_ORDER_KIND_ESCROW,
		}),
		mustCallInstruction(z.Call{
			Sender:           []byte(senderAddr.String()),
			ContractAddress:  []byte(receiverPath),
			ContractCalldata: []byte("post-transfer-action"),
		}),
	}}

	testing.SetRealm(testing.NewUserRealm(senderAddr))
	testing.SetOriginSend(chain.NewCoins(chain.NewCoin("ugnot", 40)))
	sendPacket := zkgm.Send(cross(cur), channelId, types.Timestamp(1<<62), [32]byte{}, mustBatchInstruction(batch))

	bk := banker.NewReadonlyBanker()
	ufmt.Printf("[INFO] send produced packet on channel: %s\n", sendPacket.SourceChannelId.String())
	ufmt.Printf("[INFO] proxy native escrow balance: %d\n", bk.GetCoins(proxy).AmountOf("ugnot"))
	ufmt.Println("[EXPECTED] send should succeed: Call sender matches the send-time caller, TokenOrder escrows 40")

	return sendPacket
}

func acknowledgeBatch(cur realm, sendPacket types.Packet) {
	batchAck := mustBatchAckBytes([][]byte{
		mustSuccessAck(mustProtocolTokenOrderAck()),
		mustSuccessAck([]byte{}),
	})
	ack := mustSuccessAck(batchAck)

	testing.SetRealm(testing.NewUserRealm(adminAddr))
	core.PacketAcknowledgement(cross(cur), core.NewMsgPacketAcknowledgement([]types.Packet{sendPacket}, [][]byte{ack}, nil, 1))

	bk := banker.NewReadonlyBanker()
	ufmt.Printf("[INFO] proxy native escrow balance: %d\n", bk.GetCoins(zkgm.ProxyAddress()).AmountOf("ugnot"))
	ufmt.Println("[EXPECTED] proxy native escrow balance should be 40 (unchanged: protocol-fill no-op, Call ack is also a no-op)")
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

func mustBatchInstruction(b z.Batch) z.Instruction {
	operand, err := z.EncodeBatch(b)
	if err != nil {
		panic(err)
	}
	return z.Instruction{Version: z.INSTR_VERSION_0, Opcode: z.OP_BATCH, Operand: operand}
}

func mustProtocolTokenOrderAck() []byte {
	bz, err := z.EncodeTokenOrderAck(z.TokenOrderAck{FillType: new(u256.Uint).SetBytes(z.FILL_TYPE_PROTOCOL[:])})
	if err != nil {
		panic(err)
	}
	return bz
}

func mustSuccessAck(inner []byte) []byte {
	ack, err := z.EncodeAck(z.Ack{Tag: new(u256.Uint).SetBytes(z.TAG_ACK_SUCCESS[:]), InnerAck: inner})
	if err != nil {
		panic(err)
	}
	return ack
}

func mustBatchAckBytes(childAcks [][]byte) []byte {
	bz, err := z.EncodeBatchAck(z.BatchAck{Acknowledgements: childAcks})
	if err != nil {
		panic(err)
	}
	return bz
}

// Output:
// [SCENARIO] 1. Bootstrap IBC host and open a zkgm channel
//
// [SCENARIO] 2. Send a batch of [native ESCROW 40ugnot, OP_CALL]
// [INFO] send produced packet on channel: 1
// [INFO] proxy native escrow balance: 40
// [EXPECTED] send should succeed: Call sender matches the send-time caller, TokenOrder escrows 40
//
// [SCENARIO] 3. Acknowledge the batch: TokenOrder protocol-fills, Call ack is a no-op
// [INFO] proxy native escrow balance: 40
// [EXPECTED] proxy native escrow balance should be 40 (unchanged: protocol-fill no-op, Call ack is also a no-op)
