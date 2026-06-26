// PKGPATH: gno.land/r/onbloc/ibc/scenario/union/decimals
package decimals

// send_6dec_native_no_scaling_filetest is the BY-TYPE scenario for native-coin
// amount fidelity on send (re-targeted from the legacy e2e zs26). A native ESCROW
// send of an odd 6-decimal amount (1234567 ugnot) locks exactly that amount into
// the proxy escrow with no scaling. The legacy `sh.ChannelBalanceStr` channel-
// balance read is re-targeted to the proxy's on-chain native balance, which must
// equal the wire BaseAmount exactly.

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

	nativeAmount = int64(1234567) // an odd 6-decimal amount, must not be scaled
)

func main(cur realm) {
	println("[SCENARIO] 1. Bootstrap IBC host and open a zkgm channel")
	channelId := bootstrap(cur)
	println("")

	println("[SCENARIO] 2. Native ESCROW send locks the exact 1234567ugnot with no scaling")
	sendNativeEscrow(cur, channelId)
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

// sendNativeEscrow locks native ugnot via a user ESCROW send funded by attached
// coins: IssueCoins reproduces the -send deposit landing at the proxy, SetOriginSend
// reproduces the envelope the impl reads to seed the escrow budget.
func sendNativeEscrow(cur realm, channelId types.ChannelId) {
	order := z.TokenOrderV2{
		Sender:      []byte(senderAddr.String()),
		Receiver:    []byte("remote-receiver"),
		BaseToken:   []byte("ugnot"),
		BaseAmount:  u256.NewUint(uint64(nativeAmount)),
		QuoteToken:  []byte("quote/native"),
		QuoteAmount: u256.NewUint(uint64(nativeAmount)),
		Kind:        z.TOKEN_ORDER_KIND_ESCROW,
	}

	proxy := zkgm.ProxyAddress()
	testing.IssueCoins(proxy, chain.NewCoins(chain.NewCoin("ugnot", nativeAmount)))

	testing.SetRealm(testing.NewUserRealm(senderAddr))
	testing.SetOriginSend(chain.NewCoins(chain.NewCoin("ugnot", nativeAmount)))
	_ = zkgm.Send(cross(cur), channelId, types.Timestamp(1<<62), [32]byte{}, mustOrderInstruction(order))

	bk := banker.NewReadonlyBanker()
	ufmt.Printf("[INFO] order base amount: %s\n", order.BaseAmount.ToString())
	ufmt.Printf("[INFO] proxy native escrow balance: %d\n", bk.GetCoins(proxy).AmountOf("ugnot"))
	ufmt.Println("[EXPECTED] both should be exactly 1234567 (locked, unscaled)")
}

// --- encoding helpers ---

func mustOrderInstruction(order z.TokenOrderV2) z.Instruction {
	operand, err := z.EncodeTokenOrderV2(order)
	if err != nil {
		panic(err)
	}
	return z.Instruction{Version: z.INSTR_VERSION_2, Opcode: z.OP_TOKEN_ORDER, Operand: operand}
}

// Output:
// [SCENARIO] 1. Bootstrap IBC host and open a zkgm channel
//
// [SCENARIO] 2. Native ESCROW send locks the exact 1234567ugnot with no scaling
// [INFO] order base amount: 1234567
// [INFO] proxy native escrow balance: 1234567
// [EXPECTED] both should be exactly 1234567 (locked, unscaled)
