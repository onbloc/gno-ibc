// PKGPATH: gno.land/r/onbloc/ibc/scenario/union/batch
package batch

// send_batch_full_failure_refund_filetest sends a batch of two TokenOrder
// children (native ESCROW, grc20 ESCROW) and acknowledges the WHOLE packet
// with a top-level FAILURE ack (not a batch success ack carrying a BatchAck).
// acknowledgeBatch (batch.gno:71-108) never decodes a BatchAck when the outer
// `successful` flag is false — it fans childSuccessful=false to every child
// unconditionally, refunding all of them back to the sender.

import (
	"chain"
	"chain/banker"
	"testing"

	"gno.land/p/demo/tokens/grc20"
	"gno.land/p/nt/ufmt/v0"
	types "gno.land/p/onbloc/ibc/union/types"
	z "gno.land/p/onbloc/ibc/union/zkgm"

	u256 "gno.land/p/gnoswap/uint256"

	"gno.land/r/demo/defi/grc20reg"
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

	adminAddr  = address("g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5")
	senderAddr = address("g1wymu47drhr0kuq2098m792lytgtj2nyx77yrsm")

	grc20Slug = "batch-full-failure-grc20"
)

func main(cur realm) {
	println("[SCENARIO] 1. Register a local grc20 token and mint 100 units to the sender")
	token, ledger, denom := setupGRC20(cur)
	println("")

	println("[SCENARIO] 2. Bootstrap IBC host and open a zkgm channel")
	channelId := bootstrap(cur)
	println("")

	println("[SCENARIO] 3. Send a batch of [native ESCROW 40ugnot, grc20 ESCROW 40 units]")
	sendPacket := sendBatch(cur, channelId, token, ledger, denom)
	println("")

	println("[SCENARIO] 4. Acknowledge with a top-level FAILURE ack: both children refund")
	acknowledgeFullFailure(cur, sendPacket, token)
}

func setupGRC20(cur realm) (*grc20.Token, *grc20.PrivateLedger, string) {
	token, ledger := grc20.NewToken(0, cur, "Batch Full Failure GRC20", "BFF", 6)
	grc20reg.Register(cross(cur), token, grc20Slug)
	denom := cur.PkgPath() + "." + grc20Slug

	if err := ledger.Mint(senderAddr, 100); err != nil {
		panic(err)
	}

	ufmt.Printf("[INFO] registered grc20 denom: %s\n", denom)
	ufmt.Printf("[INFO] sender grc20 balance: %d\n", token.BalanceOf(senderAddr))
	ufmt.Println("[EXPECTED] sender grc20 balance should be 100 (freshly minted)")

	return token, ledger, denom
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

func sendBatch(cur realm, channelId types.ChannelId, token *grc20.Token, ledger *grc20.PrivateLedger, denom string) types.Packet {
	proxy := zkgm.ProxyAddress()

	testing.IssueCoins(proxy, chain.NewCoins(chain.NewCoin("ugnot", 40)))
	if err := ledger.Approve(senderAddr, proxy, 40); err != nil {
		panic(err)
	}

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
		mustOrderInstruction(z.TokenOrderV2{
			Sender:      []byte(senderAddr.String()),
			Receiver:    []byte("remote-receiver"),
			BaseToken:   []byte(denom),
			BaseAmount:  u256.NewUint(40),
			QuoteToken:  []byte("remote-grc20"),
			QuoteAmount: u256.NewUint(40),
			Kind:        z.TOKEN_ORDER_KIND_ESCROW,
		}),
	}}

	testing.SetRealm(testing.NewUserRealm(senderAddr))
	testing.SetOriginSend(chain.NewCoins(chain.NewCoin("ugnot", 40)))
	sendPacket := zkgm.Send(cross(cur), channelId, types.Timestamp(1<<62), [32]byte{}, mustBatchInstruction(batch))

	bk := banker.NewReadonlyBanker()
	ufmt.Printf("[INFO] proxy native escrow balance: %d\n", bk.GetCoins(proxy).AmountOf("ugnot"))
	ufmt.Printf("[INFO] proxy grc20 escrow balance: %d\n", token.BalanceOf(proxy))
	ufmt.Println("[EXPECTED] both escrows locked: native=40, grc20=40")

	return sendPacket
}

func acknowledgeFullFailure(cur realm, sendPacket types.Packet, token *grc20.Token) {
	testing.SetRealm(testing.NewUserRealm(adminAddr))
	core.PacketAcknowledgement(cross(cur), core.NewMsgPacketAcknowledgement([]types.Packet{sendPacket}, [][]byte{mustFailureAck()}, nil, 1))

	bk := banker.NewReadonlyBanker()
	ufmt.Printf("[INFO] proxy native escrow balance: %d\n", bk.GetCoins(zkgm.ProxyAddress()).AmountOf("ugnot"))
	ufmt.Printf("[INFO] proxy grc20 escrow balance: %d\n", token.BalanceOf(zkgm.ProxyAddress()))
	ufmt.Printf("[INFO] sender native balance: %d\n", bk.GetCoins(senderAddr).AmountOf("ugnot"))
	ufmt.Printf("[INFO] sender grc20 balance: %d\n", token.BalanceOf(senderAddr))
	ufmt.Println("[EXPECTED] both escrows released: proxy native=0, proxy grc20=0")
	ufmt.Println("[EXPECTED] both refunded to sender: native=40, grc20=100 (full balance restored)")
}

// --- encoding helpers ---

func mustOrderInstruction(order z.TokenOrderV2) z.Instruction {
	operand, err := z.EncodeTokenOrderV2(order)
	if err != nil {
		panic(err)
	}
	return z.Instruction{Version: z.INSTR_VERSION_2, Opcode: z.OP_TOKEN_ORDER, Operand: operand}
}

func mustBatchInstruction(b z.Batch) z.Instruction {
	operand, err := z.EncodeBatch(b)
	if err != nil {
		panic(err)
	}
	return z.Instruction{Version: z.INSTR_VERSION_0, Opcode: z.OP_BATCH, Operand: operand}
}

func mustFailureAck() []byte {
	ack, err := z.EncodeAck(z.Ack{Tag: new(u256.Uint).SetBytes(z.TAG_ACK_FAILURE[:]), InnerAck: nil})
	if err != nil {
		panic(err)
	}
	return ack
}

// Output:
// [SCENARIO] 1. Register a local grc20 token and mint 100 units to the sender
// [INFO] registered grc20 denom: gno.land/r/onbloc/ibc/scenario/union/batch.batch-full-failure-grc20
// [INFO] sender grc20 balance: 100
// [EXPECTED] sender grc20 balance should be 100 (freshly minted)
//
// [SCENARIO] 2. Bootstrap IBC host and open a zkgm channel
//
// [SCENARIO] 3. Send a batch of [native ESCROW 40ugnot, grc20 ESCROW 40 units]
// [INFO] proxy native escrow balance: 40
// [INFO] proxy grc20 escrow balance: 40
// [EXPECTED] both escrows locked: native=40, grc20=40
//
// [SCENARIO] 4. Acknowledge with a top-level FAILURE ack: both children refund
// [INFO] proxy native escrow balance: 0
// [INFO] proxy grc20 escrow balance: 0
// [INFO] sender native balance: 40
// [INFO] sender grc20 balance: 100
// [EXPECTED] both escrows released: proxy native=0, proxy grc20=0
// [EXPECTED] both refunded to sender: native=40, grc20=100 (full balance restored)
