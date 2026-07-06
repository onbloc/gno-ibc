// PKGPATH: gno.land/r/onbloc/ibc/scenario/union
package union

// token_send_grc20_by_ucs03_zkgm_filetest walks local GRC20 ESCROW sends through
// the upgradeable union IBC host. The user approves the proxy, the proxy pulls
// GRC20 without native OriginSend, protocol-fill success leaves escrow locked,
// and failure ack refunds escrow to the sender.

import (
	"testing"

	"gno.land/p/demo/tokens/grc20"
	"gno.land/p/nt/ufmt/v0"

	types "gno.land/p/onbloc/ibc/union/types"
	z "gno.land/p/onbloc/ibc/union/zkgm"

	u256 "gno.land/p/gnoswap/uint256"

	"gno.land/r/demo/defi/grc20reg"
	"gno.land/r/onbloc/ibc/union/access"

	mock "gno.land/r/onbloc/ibc/testing/mock/lightclient"

	zkgm "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm"
	_ "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/v1"
	core "gno.land/r/onbloc/ibc/union/core"
	_ "gno.land/r/onbloc/ibc/union/core/v1"
)

const (
	coreImplPath = "gno.land/r/onbloc/ibc/union/core/v1"
	zkgmImplPath = "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/v1"

	adminAddr  = address("g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5")
	senderAddr = address("g1wymu47drhr0kuq2098m792lytgtj2nyx77yrsm")
	// mockClientType = types.ClientType("scenario-mock-lc")

	scenarioPkgPath = "gno.land/r/onbloc/ibc/scenario/union"
	grc20Slug       = "scenario-grc20"
	grc20Key        = scenarioPkgPath + "." + grc20Slug
)

func main(cur realm) {
	// --- SCENARIO 1: bootstrap (admin) — kept inline so each core call is a
	// direct origin call: runtime.AssertOriginCall requires <= 2 call frames. ---
	ufmt.Println("[SCENARIO] 1. Bootstrap IBC host and open client/connection/channel")
	testing.SetRealm(testing.NewUserRealm(adminAddr))
	core.UpdateImpl(cross(cur), coreImplPath)
	zkgm.UpdateImpl(cross(cur), zkgmImplPath)
	zkgm.SetRateLimitDisabled(cross(cur), true)
	zkgm.RegisterCoreApp(cross(cur))

	access.GrantRole(cross(cur), access.RelayerRole, adminAddr)
	access.GrantRole(cross(cur), access.RelayerRole, mock.MockClientAddress(cross(cur)))

	mock.RegisterMockLightClient(cross(cur))
	core.CreateClient(cross(cur), core.NewMsgCreateClient(mock.MockClientType, nil, nil))
	clientId := types.ClientId(1)

	core.ConnectionOpenInit(cross(cur), core.NewMsgConnectionOpenInit(clientId, types.ClientId(99)))
	connectionId := types.ConnectionId(1)
	core.ConnectionOpenAck(cross(cur), core.NewMsgConnectionOpenAck(connectionId, types.ConnectionId(77), nil, 1))

	portId := []byte(zkgm.ProxyPkgPath())
	core.ChannelOpenInit(cross(cur), core.NewMsgChannelOpenInit(portId, portId, connectionId, zkgm.Version, "g1relayer"))
	channelId := types.ChannelId(1)
	core.ChannelOpenAck(cross(cur), core.NewMsgChannelOpenAck(channelId, zkgm.Version, types.ChannelId(2), nil, 1, "g1relayer"))
	ufmt.Printf("[INFO] handshake opened: client=%s connection=%s channel=%s\n", clientId.String(), connectionId.String(), channelId.String())
	ufmt.Println("[EXPECTED] client should be 1")
	ufmt.Println("[EXPECTED] connection should be 1")
	ufmt.Println("[EXPECTED] channel should be 1")

	// --- SCENARIO 2: create a local GRC20, mint to sender, and approve proxy ---
	ufmt.Println("")
	ufmt.Println("[SCENARIO] 2. Register local GRC20, mint 100 to sender, approve proxy for 70")
	testing.SetRealm(testing.NewCodeRealm(scenarioPkgPath))
	token, ledger := grc20.NewToken(0, cur, "Scenario GRC20", "SCENG", 6)
	if err := ledger.Mint(senderAddr, 100); err != nil {
		panic(err)
	}
	if err := ledger.ImpersonateTeller(senderAddr).Approve(0, cur, zkgm.ProxyAddress(), 70); err != nil {
		panic(err)
	}
	grc20reg.Register(cross(cur), token, grc20Slug)

	ufmt.Printf("[INFO] registered GRC20 key: %s\n", grc20Key)
	ufmt.Printf("[INFO] sender GRC20 balance: %d\n", token.BalanceOf(senderAddr))
	ufmt.Printf("[INFO] proxy GRC20 allowance: %d\n", token.Allowance(senderAddr, zkgm.ProxyAddress()))
	ufmt.Println("[EXPECTED] sender GRC20 balance should be 100")
	ufmt.Println("[EXPECTED] proxy allowance should be 70")

	// --- SCENARIO 3: send ESCROW order locking 40 GRC20 without native OriginSend ---
	ufmt.Println("")
	ufmt.Println("[SCENARIO] 3. Send GRC20 ESCROW order locking 40 without native OriginSend")
	successOrder := z.TokenOrderV2{
		Sender:      []byte(senderAddr.String()),
		Receiver:    []byte("remote-receiver"),
		BaseToken:   []byte(grc20Key),
		BaseAmount:  u256.NewUint(40),
		QuoteToken:  []byte("remote-scenario-grc20"),
		QuoteAmount: u256.NewUint(40),
		Kind:        z.TOKEN_ORDER_KIND_ESCROW,
	}

	testing.SetRealm(testing.NewUserRealm(senderAddr))
	successPacket := zkgm.Send(cross(cur), channelId, types.Timestamp(1<<62), [32]byte{}, mustOrderInstruction(successOrder))

	ufmt.Printf("[INFO] send produced packet on channel: %s\n", successPacket.SourceChannelId.String())
	ufmt.Printf("[INFO] sender GRC20 balance: %d\n", token.BalanceOf(senderAddr))
	ufmt.Printf("[INFO] proxy GRC20 escrow balance: %d\n", token.BalanceOf(zkgm.ProxyAddress()))
	ufmt.Println("[EXPECTED] sender GRC20 balance should be 60 (100 - 40 escrowed)")
	ufmt.Println("[EXPECTED] proxy GRC20 escrow balance should be 40")

	// --- SCENARIO 4: protocol-fill success is a no-op for an escrow, so the lock holds ---
	ufmt.Println("")
	ufmt.Println("[SCENARIO] 4. Acknowledge with protocol-fill success (no-op for escrow)")
	successAck := mustSuccessAck(mustProtocolTokenOrderAck())

	testing.SetRealm(testing.NewUserRealm(adminAddr))
	core.PacketAcknowledgement(cross(cur), core.NewMsgPacketAcknowledgement([]types.Packet{successPacket}, [][]byte{successAck}, nil, 1))

	ufmt.Printf("[INFO] sender GRC20 balance: %d\n", token.BalanceOf(senderAddr))
	ufmt.Printf("[INFO] proxy GRC20 escrow balance: %d\n", token.BalanceOf(zkgm.ProxyAddress()))
	ufmt.Println("[EXPECTED] sender GRC20 balance should be 60 (unchanged)")
	ufmt.Println("[EXPECTED] proxy GRC20 escrow balance should be 40 (unchanged)")

	// --- SCENARIO 5: send another ESCROW order, then failure ack refunds it ---
	ufmt.Println("")
	ufmt.Println("[SCENARIO] 5. Failure ack refunds a second 30 GRC20 escrow")
	refundOrder := z.TokenOrderV2{
		Sender:      []byte(senderAddr.String()),
		Receiver:    []byte("remote-receiver"),
		BaseToken:   []byte(grc20Key),
		BaseAmount:  u256.NewUint(30),
		QuoteToken:  []byte("remote-scenario-grc20"),
		QuoteAmount: u256.NewUint(30),
		Kind:        z.TOKEN_ORDER_KIND_ESCROW,
	}

	testing.SetRealm(testing.NewUserRealm(senderAddr))
	refundPacket := zkgm.Send(cross(cur), channelId, types.Timestamp(1<<62), [32]byte{}, mustOrderInstruction(refundOrder))
	ufmt.Printf("[INFO] sender GRC20 balance after second send: %d\n", token.BalanceOf(senderAddr))
	ufmt.Printf("[INFO] proxy GRC20 escrow balance after second send: %d\n", token.BalanceOf(zkgm.ProxyAddress()))

	failureAck := mustFailureAck()
	testing.SetRealm(testing.NewUserRealm(adminAddr))
	core.PacketAcknowledgement(cross(cur), core.NewMsgPacketAcknowledgement([]types.Packet{refundPacket}, [][]byte{failureAck}, nil, 1))

	ufmt.Printf("[INFO] sender GRC20 balance after failure ack: %d\n", token.BalanceOf(senderAddr))
	ufmt.Printf("[INFO] proxy GRC20 escrow balance after failure ack: %d\n", token.BalanceOf(zkgm.ProxyAddress()))
	ufmt.Println("[EXPECTED] sender GRC20 balance should be 60 (second escrow refunded)")
	ufmt.Println("[EXPECTED] proxy GRC20 escrow balance should be 40 (only success escrow remains)")
}

// --- encoding helpers (pure z calls, mirroring the e2e harness) ---

func mustOrderInstruction(order z.TokenOrderV2) z.Instruction {
	operand, err := z.EncodeTokenOrderV2(order)
	if err != nil {
		panic(err)
	}
	return z.Instruction{Version: z.INSTR_VERSION_2, Opcode: z.OP_TOKEN_ORDER, Operand: operand}
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

func mustFailureAck() []byte {
	ack, err := z.EncodeAck(z.Ack{Tag: new(u256.Uint).SetBytes(z.TAG_ACK_FAILURE[:]), InnerAck: nil})
	if err != nil {
		panic(err)
	}
	return ack
}

// Output:
// [SCENARIO] 1. Bootstrap IBC host and open client/connection/channel
// [INFO] handshake opened: client=1 connection=1 channel=1
// [EXPECTED] client should be 1
// [EXPECTED] connection should be 1
// [EXPECTED] channel should be 1
//
// [SCENARIO] 2. Register local GRC20, mint 100 to sender, approve proxy for 70
// [INFO] registered GRC20 key: gno.land/r/onbloc/ibc/scenario/union.scenario-grc20
// [INFO] sender GRC20 balance: 100
// [INFO] proxy GRC20 allowance: 70
// [EXPECTED] sender GRC20 balance should be 100
// [EXPECTED] proxy allowance should be 70
//
// [SCENARIO] 3. Send GRC20 ESCROW order locking 40 without native OriginSend
// [INFO] send produced packet on channel: 1
// [INFO] sender GRC20 balance: 60
// [INFO] proxy GRC20 escrow balance: 40
// [EXPECTED] sender GRC20 balance should be 60 (100 - 40 escrowed)
// [EXPECTED] proxy GRC20 escrow balance should be 40
//
// [SCENARIO] 4. Acknowledge with protocol-fill success (no-op for escrow)
// [INFO] sender GRC20 balance: 60
// [INFO] proxy GRC20 escrow balance: 40
// [EXPECTED] sender GRC20 balance should be 60 (unchanged)
// [EXPECTED] proxy GRC20 escrow balance should be 40 (unchanged)
//
// [SCENARIO] 5. Failure ack refunds a second 30 GRC20 escrow
// [INFO] sender GRC20 balance after second send: 30
// [INFO] proxy GRC20 escrow balance after second send: 70
// [INFO] sender GRC20 balance after failure ack: 60
// [INFO] proxy GRC20 escrow balance after failure ack: 40
// [EXPECTED] sender GRC20 balance should be 60 (second escrow refunded)
// [EXPECTED] proxy GRC20 escrow balance should be 40 (only success escrow remains)
