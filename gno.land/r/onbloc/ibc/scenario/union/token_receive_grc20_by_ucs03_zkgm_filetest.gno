// PKGPATH: gno.land/r/onbloc/ibc/scenario/union
package union

// token_receive_grc20_by_ucs03_zkgm_filetest exercises the local GRC20 release
// path on receive. It first locks GRC20 in the proxy escrow through a local send,
// then receives an UNESCROW packet that releases part of that escrow to a local
// receiver.

import (
	"testing"

	"gno.land/p/demo/tokens/grc20"
	u256 "gno.land/p/gnoswap/uint256"
	"gno.land/p/nt/ufmt/v0"
	"gno.land/p/onbloc/ibc/union/types"
	z "gno.land/p/onbloc/ibc/union/zkgm"

	"gno.land/r/demo/defi/grc20reg"
	mocklc "gno.land/r/onbloc/ibc/testing/mock/lightclient"
	"gno.land/r/onbloc/ibc/union/access"
	zkgm "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm"
	_ "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/v1"
	core "gno.land/r/onbloc/ibc/union/core"
	_ "gno.land/r/onbloc/ibc/union/core/v1"
)

const (
	coreImplPath = "gno.land/r/onbloc/ibc/union/core/v1"
	zkgmImplPath = "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/v1"

	adminAddr    = address("g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5")
	senderAddr   = address("g1wymu47drhr0kuq2098m792lytgtj2nyx77yrsm")
	receiverAddr = address("g1dyxy88p94acjnm8dmu9tfj2mv2ncvx83cagllu")

	scenarioPkgPath = "gno.land/r/onbloc/ibc/scenario/union"
	grc20Slug       = "scenario-grc20-recv"
	grc20Key        = scenarioPkgPath + "." + grc20Slug
	remoteGRC20     = "remote-scenario-grc20"
)

func main(cur realm) {
	ufmt.Println("[SCENARIO] 1. Bootstrap IBC host and open client/connection/channel")
	testing.SetRealm(testing.NewUserRealm(adminAddr))
	core.UpdateImpl(cross(cur), coreImplPath)
	zkgm.UpdateImpl(cross(cur), zkgmImplPath)
	zkgm.SetRateLimitDisabled(cross(cur), true)
	zkgm.RegisterCoreApp(cross(cur))
	access.GrantRole(cross(cur), access.RelayerRole, adminAddr)
	access.GrantRole(cross(cur), access.RelayerRole, mocklc.MockClientAddress(cross(cur)))

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
	ufmt.Printf("[INFO] handshake opened: client=%s connection=%s channel=%s\n", clientId.String(), connectionId.String(), channelId.String())
	ufmt.Println("[EXPECTED] client should be 1")
	ufmt.Println("[EXPECTED] connection should be 1")
	ufmt.Println("[EXPECTED] channel should be 1")

	ufmt.Println("")
	ufmt.Println("[SCENARIO] 2. Register local GRC20, mint 100 to sender, approve proxy for 40")
	testing.SetRealm(testing.NewCodeRealm(scenarioPkgPath))
	token, ledger := grc20.NewToken(0, cur, "Scenario Receive GRC20", "SCENR", 6)
	if err := ledger.Mint(senderAddr, 100); err != nil {
		panic(err)
	}
	if err := ledger.ImpersonateTeller(senderAddr).Approve(0, cur, zkgm.ProxyAddress(), 40); err != nil {
		panic(err)
	}
	grc20reg.Register(cross(cur), token, grc20Slug)

	ufmt.Printf("[INFO] registered GRC20 key: %s\n", grc20Key)
	ufmt.Printf("[INFO] sender GRC20 balance: %d\n", token.BalanceOf(senderAddr))
	ufmt.Printf("[INFO] proxy GRC20 allowance: %d\n", token.Allowance(senderAddr, zkgm.ProxyAddress()))
	ufmt.Println("[EXPECTED] sender GRC20 balance should be 100")
	ufmt.Println("[EXPECTED] proxy allowance should be 40")

	ufmt.Println("")
	ufmt.Println("[SCENARIO] 3. Lock 40 GRC20 into proxy escrow")
	lockOrder := z.TokenOrderV2{
		Sender:      []byte(senderAddr.String()),
		Receiver:    []byte("remote-receiver"),
		BaseToken:   []byte(grc20Key),
		BaseAmount:  u256.NewUint(40),
		QuoteToken:  []byte(remoteGRC20),
		QuoteAmount: u256.NewUint(40),
		Kind:        z.TOKEN_ORDER_KIND_ESCROW,
	}

	testing.SetRealm(testing.NewUserRealm(senderAddr))
	lockPacket := zkgm.Send(cross(cur), channelId, types.Timestamp(1<<62), [32]byte{}, mustOrderInstruction(lockOrder))

	ufmt.Printf("[INFO] sender GRC20 balance: %d\n", token.BalanceOf(senderAddr))
	ufmt.Printf("[INFO] proxy GRC20 escrow balance: %d\n", token.BalanceOf(zkgm.ProxyAddress()))
	ufmt.Printf("[INFO] receiver GRC20 balance: %d\n", token.BalanceOf(receiverAddr))
	ufmt.Println("[EXPECTED] sender GRC20 balance should be 60")
	ufmt.Println("[EXPECTED] proxy GRC20 escrow balance should be 40")
	ufmt.Println("[EXPECTED] receiver GRC20 balance should be 0")

	ufmt.Println("")
	ufmt.Println("[SCENARIO] 4. Acknowledge outbound escrow with protocol-fill success")
	successAck := mustSuccessAck(mustProtocolTokenOrderAck())

	testing.SetRealm(testing.NewUserRealm(adminAddr))
	core.PacketAcknowledgement(cross(cur), core.NewMsgPacketAcknowledgement([]types.Packet{lockPacket}, [][]byte{successAck}, nil, 1))

	ufmt.Printf("[INFO] sender GRC20 balance: %d\n", token.BalanceOf(senderAddr))
	ufmt.Printf("[INFO] proxy GRC20 escrow balance: %d\n", token.BalanceOf(zkgm.ProxyAddress()))
	ufmt.Printf("[INFO] receiver GRC20 balance: %d\n", token.BalanceOf(receiverAddr))
	ufmt.Println("[EXPECTED] sender GRC20 balance should be 60 (unchanged)")
	ufmt.Println("[EXPECTED] proxy GRC20 escrow balance should be 40 (unchanged)")
	ufmt.Println("[EXPECTED] receiver GRC20 balance should be 0 (unchanged)")

	ufmt.Println("")
	ufmt.Println("[SCENARIO] 5. Receive UNESCROW order releasing 25 GRC20 to receiver")
	unescrowOrder := z.TokenOrderV2{
		Sender:      []byte("remote-sender"),
		Receiver:    []byte(receiverAddr.String()),
		BaseToken:   []byte(remoteGRC20),
		BaseAmount:  u256.NewUint(25),
		QuoteToken:  []byte(grc20Key),
		QuoteAmount: u256.NewUint(25),
		Kind:        z.TOKEN_ORDER_KIND_UNESCROW,
	}
	unescrowPacket := core.NewPacket(types.ChannelId(2), channelId, mustPacketData(mustOrderInstruction(unescrowOrder)), types.Timestamp(1<<62))

	testing.SetRealm(testing.NewUserRealm(adminAddr))
	core.PacketRecv(cross(cur), core.NewMsgPacketRecv([]types.Packet{unescrowPacket}, [][]byte{nil}, nil, 1))

	ufmt.Printf("[INFO] sender GRC20 balance: %d\n", token.BalanceOf(senderAddr))
	ufmt.Printf("[INFO] proxy GRC20 escrow balance: %d\n", token.BalanceOf(zkgm.ProxyAddress()))
	ufmt.Printf("[INFO] receiver GRC20 balance: %d\n", token.BalanceOf(receiverAddr))
	ufmt.Println("[EXPECTED] sender GRC20 balance should be 60 (unchanged)")
	ufmt.Println("[EXPECTED] proxy GRC20 escrow balance should be 15 (40 - 25 released)")
	ufmt.Println("[EXPECTED] receiver GRC20 balance should be 25")
}

func mustOrderInstruction(order z.TokenOrderV2) z.Instruction {
	operand, err := z.EncodeTokenOrderV2(order)
	if err != nil {
		panic(err)
	}
	return z.Instruction{Version: z.INSTR_VERSION_2, Opcode: z.OP_TOKEN_ORDER, Operand: operand}
}

func mustPacketData(instr z.Instruction) []byte {
	data, err := z.EncodeZkgmPacket(z.ZkgmPacket{Path: u256.Zero(), Instruction: instr})
	if err != nil {
		panic(err)
	}
	return data
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

// Output:
// [SCENARIO] 1. Bootstrap IBC host and open client/connection/channel
// [INFO] handshake opened: client=1 connection=1 channel=1
// [EXPECTED] client should be 1
// [EXPECTED] connection should be 1
// [EXPECTED] channel should be 1
//
// [SCENARIO] 2. Register local GRC20, mint 100 to sender, approve proxy for 40
// [INFO] registered GRC20 key: gno.land/r/onbloc/ibc/scenario/union.scenario-grc20-recv
// [INFO] sender GRC20 balance: 100
// [INFO] proxy GRC20 allowance: 40
// [EXPECTED] sender GRC20 balance should be 100
// [EXPECTED] proxy allowance should be 40
//
// [SCENARIO] 3. Lock 40 GRC20 into proxy escrow
// [INFO] sender GRC20 balance: 60
// [INFO] proxy GRC20 escrow balance: 40
// [INFO] receiver GRC20 balance: 0
// [EXPECTED] sender GRC20 balance should be 60
// [EXPECTED] proxy GRC20 escrow balance should be 40
// [EXPECTED] receiver GRC20 balance should be 0
//
// [SCENARIO] 4. Acknowledge outbound escrow with protocol-fill success
// [INFO] sender GRC20 balance: 60
// [INFO] proxy GRC20 escrow balance: 40
// [INFO] receiver GRC20 balance: 0
// [EXPECTED] sender GRC20 balance should be 60 (unchanged)
// [EXPECTED] proxy GRC20 escrow balance should be 40 (unchanged)
// [EXPECTED] receiver GRC20 balance should be 0 (unchanged)
//
// [SCENARIO] 5. Receive UNESCROW order releasing 25 GRC20 to receiver
// [INFO] sender GRC20 balance: 60
// [INFO] proxy GRC20 escrow balance: 15
// [INFO] receiver GRC20 balance: 25
// [EXPECTED] sender GRC20 balance should be 60 (unchanged)
// [EXPECTED] proxy GRC20 escrow balance should be 15 (40 - 25 released)
// [EXPECTED] receiver GRC20 balance should be 25
