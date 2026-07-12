// PKGPATH: gno.land/r/onbloc/ibc/scenario/union/upgrade
package upgrade

// send_escrow_survives_impl_reinstall_filetest is the IN-FLIGHT SEND upgrade
// scenario. A sender has a native ESCROW send locked at the proxy. The admin
// re-installs the impl (rebuilding it against the same proxy-owned store)
// before the packet's acknowledgement arrives. The escrow is proxy-owned
// state, so the new impl settles it exactly like the old one would: a failure
// ack still refunds the sender. This mirrors forward/'s
// inflight_survives_impl_upgrade_filetest.gno, but for a plain (non-forward)
// TokenOrder send settling directly, not an in-flight forwarded parent.

import (
	"chain"
	"chain/banker"
	"testing"

	"gno.land/p/nt/ufmt/v0"
	types "gno.land/p/onbloc/ibc/union/types"
	z "gno.land/p/onbloc/ibc/union/zkgm"

	u256 "gno.land/p/gnoswap/uint256"

	"gno.land/r/onbloc/ibc/union/access"
	zkgm "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm"
	_ "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/v1"
	core "gno.land/r/onbloc/ibc/union/core"
	_ "gno.land/r/onbloc/ibc/union/core/v1"
	mocklc "gno.land/r/onbloc/ibc/testing/mock/lightclient"
)

const (
	coreImplPath  = "gno.land/r/onbloc/ibc/union/core/v1"
	zkgmImplPath  = "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/v1"
	mockLcPkgPath = "gno.land/r/onbloc/ibc/testing/mock/lightclient"

	adminAddr  = address("g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5")
	senderAddr = address("g1wymu47drhr0kuq2098m792lytgtj2nyx77yrsm")
)

func main(cur realm) {
	println("[SCENARIO] 1. Bootstrap IBC host and open a zkgm channel")
	channelId := bootstrap(cur)
	println("")

	println("[SCENARIO] 2. Send native ESCROW order locking 40ugnot")
	sendPacket := sendNativeEscrowOrder(cur, channelId)
	println("")

	println("[SCENARIO] 3. Re-install the impl before the ack arrives")
	reinstallImpl(cur)
	println("")

	println("[SCENARIO] 4. A failure ack still settles correctly under the new impl: escrow refunded")
	acknowledgeFailureRefund(cur, sendPacket)
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

func sendNativeEscrowOrder(cur realm, channelId types.ChannelId) types.Packet {
	order := z.TokenOrderV2{
		Sender:      []byte(senderAddr.String()),
		Receiver:    []byte("remote-receiver"),
		BaseToken:   []byte("ugnot"),
		BaseAmount:  u256.NewUint(40),
		QuoteToken:  []byte("remote-ugnot"),
		QuoteAmount: u256.NewUint(40),
		Kind:        z.TOKEN_ORDER_KIND_ESCROW,
	}

	proxy := zkgm.ProxyAddress()
	testing.IssueCoins(proxy, chain.NewCoins(chain.NewCoin("ugnot", 40)))

	testing.SetRealm(testing.NewUserRealm(senderAddr))
	testing.SetOriginSend(chain.NewCoins(chain.NewCoin("ugnot", 40)))
	sendPacket := zkgm.Send(cross(cur), channelId, types.Timestamp(1<<62), [32]byte{}, mustOrderInstruction(order))

	bk := banker.NewReadonlyBanker()
	ufmt.Printf("[INFO] proxy native escrow balance: %d\n", bk.GetCoins(proxy).AmountOf("ugnot"))
	ufmt.Println("[EXPECTED] proxy native escrow balance should be 40 (locked)")

	return sendPacket
}

func reinstallImpl(cur realm) {
	testing.SetRealm(testing.NewUserRealm(adminAddr))
	zkgm.UpdateImpl(cross(cur), zkgmImplPath)
	ufmt.Println("[INFO] impl re-installed against the same proxy-owned store")
}

// acknowledgeFailureRefund acknowledges the sent packet with a FAILURE ack under
// the new impl: the escrowed native asset is released back to the original sender.
func acknowledgeFailureRefund(cur realm, sendPacket types.Packet) {
	bk := banker.NewReadonlyBanker()
	proxy := zkgm.ProxyAddress()

	testing.SetRealm(testing.NewUserRealm(adminAddr))
	core.PacketAcknowledgement(cross(cur), core.NewMsgPacketAcknowledgement([]types.Packet{sendPacket}, [][]byte{mustFailureAck()}, nil, 1))

	ufmt.Printf("[INFO] proxy native escrow balance: %d\n", bk.GetCoins(proxy).AmountOf("ugnot"))
	ufmt.Printf("[INFO] sender native balance: %d\n", bk.GetCoins(senderAddr).AmountOf("ugnot"))
	ufmt.Println("[EXPECTED] proxy native escrow balance should be 0 (refunded)")
	ufmt.Println("[EXPECTED] sender native balance should be 40 (escrow refunded back)")
}

// --- encoding helpers ---

func mustOrderInstruction(order z.TokenOrderV2) z.Instruction {
	operand, err := z.EncodeTokenOrderV2(order)
	if err != nil {
		panic(err)
	}
	return z.Instruction{Version: z.INSTR_VERSION_2, Opcode: z.OP_TOKEN_ORDER, Operand: operand}
}

func mustFailureAck() []byte {
	ack, err := z.EncodeAck(z.Ack{Tag: new(u256.Uint).SetBytes(z.TAG_ACK_FAILURE[:]), InnerAck: nil})
	if err != nil {
		panic(err)
	}
	return ack
}

// Output:
// [SCENARIO] 1. Bootstrap IBC host and open a zkgm channel
//
// [SCENARIO] 2. Send native ESCROW order locking 40ugnot
// [INFO] proxy native escrow balance: 40
// [EXPECTED] proxy native escrow balance should be 40 (locked)
//
// [SCENARIO] 3. Re-install the impl before the ack arrives
// [INFO] impl re-installed against the same proxy-owned store
//
// [SCENARIO] 4. A failure ack still settles correctly under the new impl: escrow refunded
// [INFO] proxy native escrow balance: 0
// [INFO] sender native balance: 40
// [EXPECTED] proxy native escrow balance should be 0 (refunded)
// [EXPECTED] sender native balance should be 40 (escrow refunded back)
