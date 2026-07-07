// PKGPATH: gno.land/r/onbloc/ibc/scenario/union
package union

// token_send_voucher_with_decimal_trim_filetest walks a token send for an
// 18-decimal voucher through ucs03-zkgm, asserting that local 6-decimal amounts
// are scaled up when encoded into the outgoing packet.

import (
	"testing"

	u256 "gno.land/p/gnoswap/uint256"
	"gno.land/p/nt/ufmt/v0"
	"gno.land/p/onbloc/ibc/union/types"
	z "gno.land/p/onbloc/ibc/union/zkgm"

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
	receiverAddr = address("g1qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqlldmu")
)

func main(cur realm) {
	ufmt.Println("[SCENARIO] Bootstrap IBC host and open client/connection/channel")
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

	core.ChannelOpenInit(cross(cur), core.NewMsgChannelOpenInit(portId, portId, connectionId, zkgm.Version, "g1relayer"))
	remoteChannelId := types.ChannelId(2)
	core.ChannelOpenAck(cross(cur), core.NewMsgChannelOpenAck(remoteChannelId, zkgm.Version, channelId, nil, 1, "g1relayer"))

	ufmt.Println("")
	ufmt.Println("[SCENARIO] Fund sender with 18-decimal voucher via INITIALIZE recv")
	meta := mustTokenMetadata("grc20", z.TokenInitializer{Name: "USD Coin", Symbol: "USDC", Decimals: 18})
	quoteToken := z.PredictWrappedTokenV2(u256.Zero(), uint32(channelId), []byte("uatom"), z.MetadataImage(mustDecodeMeta(meta)))
	initOrder := z.TokenOrderV2{
		Sender:      []byte("remote-sender"),
		Receiver:    []byte(senderAddr.String()),
		BaseToken:   []byte("uatom"),
		BaseAmount:  u256.NewUint(123456000000000000),
		QuoteToken:  []byte(quoteToken),
		QuoteAmount: u256.NewUint(123456000000000000),
		Kind:        z.TOKEN_ORDER_KIND_INITIALIZE,
		Metadata:    meta,
	}
	initPacket := core.NewPacket(types.ChannelId(2), channelId, mustPacketData(mustOrderInstruction(initOrder)), types.Timestamp(1<<62))

	testing.SetRealm(testing.NewUserRealm(adminAddr))
	core.PacketRecv(cross(cur), core.NewMsgPacketRecv([]types.Packet{initPacket}, [][]byte{nil}, nil, 1))

	ufmt.Printf("[INFO] minted 18-decimal voucher: %s (decimals=18)\n", quoteToken)
	ufmt.Printf("[INFO] sender %s initial local balance: %d (0.123456 tokens)\n", senderAddr.String(), zkgm.VoucherBalanceOf(quoteToken, senderAddr))
	ufmt.Println("[EXPECTED] sender local balance should be 123456")

	ufmt.Println("")
	ufmt.Println("[SCENARIO] Send ESCROW order with local 6-decimal amount (0.123456)")
	escrowOrder := z.TokenOrderV2{
		Sender:      []byte(senderAddr.String()),
		Receiver:    []byte(receiverAddr.String()),
		BaseToken:   []byte(quoteToken),
		BaseAmount:  u256.NewUint(123456),
		QuoteToken:  []byte(quoteToken),
		QuoteAmount: u256.NewUint(123456),
		Kind:        z.TOKEN_ORDER_KIND_ESCROW,
	}

	ufmt.Printf("[INFO] local BaseAmount to send: %d (0.123456)\n", escrowOrder.BaseAmount.Uint64())
	ufmt.Printf("[INFO] expected packet BaseAmount: %d (18-decimal wire amount)\n", uint64(123456000000000000))

	testing.SetRealm(testing.NewUserRealm(senderAddr))
	sendPacket := zkgm.Send(cross(cur), channelId, types.Timestamp(1<<62), [32]byte{}, mustOrderInstruction(escrowOrder))

	senderBalanceAfter := zkgm.VoucherBalanceOf(quoteToken, senderAddr)
	ufmt.Printf("[INFO] sender balance after send: %d\n", senderBalanceAfter)
	ufmt.Println("[EXPECTED] sender balance should be 0")
	ufmt.Printf("[INFO] proxy escrow balance after send: %d\n", zkgm.VoucherBalanceOf(quoteToken, zkgm.ProxyAddress()))
	ufmt.Println("[EXPECTED] proxy escrow balance should be 123456")

	zkgmPacket, err := z.DecodeZkgmPacket(sendPacket.Data)
	if err != nil {
		panic(err)
	}
	decodedOrder, err := z.DecodeTokenOrderV2(zkgmPacket.Instruction.Operand)
	if err != nil {
		panic(err)
	}
	ufmt.Printf("[INFO] packet BaseAmount (decoded): %d\n", decodedOrder.BaseAmount.Uint64())
	ufmt.Println("[EXPECTED] packet BaseAmount should be 123456000000000000 (scaled for wire)")
	ufmt.Printf("[INFO] packet QuoteAmount (decoded): %d\n", decodedOrder.QuoteAmount.Uint64())
	ufmt.Println("[EXPECTED] packet QuoteAmount should be 123456000000000000 (scaled for wire)")
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

func mustTokenMetadata(implementation string, ti z.TokenInitializer) []byte {
	initBytes, err := z.EncodeTokenInitializer(ti)
	if err != nil {
		panic(err)
	}
	meta, err := z.EncodeTokenMetadata(z.TokenMetadata{Implementation: []byte(implementation), Initializer: initBytes})
	if err != nil {
		panic(err)
	}
	return meta
}

func mustDecodeMeta(bz []byte) z.TokenMetadata {
	meta, err := z.DecodeTokenMetadata(bz)
	if err != nil {
		panic(err)
	}
	return meta
}

// Output:
// [SCENARIO] Bootstrap IBC host and open client/connection/channel
//
// [SCENARIO] Fund sender with 18-decimal voucher via INITIALIZE recv
// [INFO] minted 18-decimal voucher: ibc/f5bb2d8e2e450ba45c889df6df11dcc178d074c9 (decimals=18)
// [INFO] sender g1wymu47drhr0kuq2098m792lytgtj2nyx77yrsm initial local balance: 123456 (0.123456 tokens)
// [EXPECTED] sender local balance should be 123456
//
// [SCENARIO] Send ESCROW order with local 6-decimal amount (0.123456)
// [INFO] local BaseAmount to send: 123456 (0.123456)
// [INFO] expected packet BaseAmount: 123456000000000000 (18-decimal wire amount)
// [INFO] sender balance after send: 0
// [EXPECTED] sender balance should be 0
// [INFO] proxy escrow balance after send: 123456
// [EXPECTED] proxy escrow balance should be 123456
// [INFO] packet BaseAmount (decoded): 123456000000000000
// [EXPECTED] packet BaseAmount should be 123456000000000000 (scaled for wire)
// [INFO] packet QuoteAmount (decoded): 123456000000000000
// [EXPECTED] packet QuoteAmount should be 123456000000000000 (scaled for wire)
