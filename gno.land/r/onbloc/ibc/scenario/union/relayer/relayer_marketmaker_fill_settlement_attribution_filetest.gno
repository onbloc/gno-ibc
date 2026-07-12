// PKGPATH: gno.land/r/onbloc/ibc/scenario/union/relayer
package relayer

// relayer_marketmaker_fill_settlement_attribution_filetest is the BY-TYPE
// relayer scenario for market-maker settlement attribution. marketMakerFillV2
// (token_order.gno) always fronts the quote from the *submitting* relayer's
// own voucher balance (transferVoucher(relayer, receiver, ...)), but the ack
// it writes records MarketMaker as relayerMsg when the submitter provides one
// — falling back to the relayer's own address only when relayerMsg is empty.
// Later, on the source chain, acknowledgeTokenOrderV2's market-maker branch
// releases the original escrow to that recorded MarketMaker address, not to
// whoever happened to submit the recv or send. This file shows both halves
// with two independent addresses: relayer A fronts liquidity on recv while
// designating relayer B via relayerMsg (part 1 — A's own balance visibly
// funds the receiver), and a separately escrowed send is acknowledged with a
// market-maker-fill ack naming B (part 2 — the escrow settles to B, not to A
// and not to the original sender). Every prior relayer/ scenario passes an
// empty relayerMsg, so submitter and reimbursement address were always the
// same account; this is the first to pull them apart.

import (
	"chain"
	"chain/banker"
	"testing"

	"gno.land/p/nt/ufmt/v0"
	types "gno.land/p/onbloc/ibc/union/types"
	z "gno.land/p/onbloc/ibc/union/zkgm"

	u256 "gno.land/p/gnoswap/uint256"

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

	adminAddr    = address("g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5")
	relayerAAddr = address("g1wymu47drhr0kuq2098m792lytgtj2nyx77yrsm")
	relayerBAddr = address("g1dyxy88p94acjnm8dmu9tfj2mv2ncvx83cagllu")
	receiverAddr = address("g1qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqluuxe")
	senderAddr   = address("g13sfw6733qnvqz5xwr2xa7f8g5fk3qvqwj9zc7p")
)

func main(cur realm) {
	println("[SCENARIO] 1. Bootstrap IBC host, open a channel, authorize relayer A")
	channelId := bootstrap(cur)
	println("")

	meta := mustTokenMetadata("grc20", z.TokenInitializer{Name: "Relay Token", Symbol: "RLY", Decimals: 6})
	quoteToken := z.PredictWrappedTokenV2(u256.Zero(), uint32(channelId), []byte("urly"), z.MetadataImage(mustDecodeMeta(meta)))

	println("[SCENARIO] 2. Fund relayer A with 100 of the voucher via a protocol-fill INITIALIZE recv")
	fundRelayerA(cur, channelId, quoteToken, meta)
	println("")

	println("[SCENARIO] 3. Relayer A fronts an under-quoted recv while designating relayer B via relayerMsg")
	frontUnderQuotedOrderAsRelayerA(cur, channelId, quoteToken)
	println("")

	println("[SCENARIO] 4. Send a separate native ESCROW order locking 40ugnot")
	sendPacket := sendNativeEscrowOrder(cur, channelId)
	println("")

	println("[SCENARIO] 5. Acknowledge with a market-maker-fill ack naming B: escrow settles to B, not A or the sender")
	acknowledgeMarketMakerFillToB(cur, sendPacket)
}

func bootstrap(cur realm) types.ChannelId {
	testing.SetRealm(testing.NewUserRealm(adminAddr))
	core.UpdateImpl(cross(cur), coreImplPath)
	zkgm.UpdateImpl(cross(cur), zkgmImplPath)
	zkgm.SetRateLimitDisabled(cross(cur), true)
	zkgm.RegisterCoreApp(cross(cur))
	access.GrantRole(cross(cur), access.RelayerRole, adminAddr)
	access.GrantRole(cross(cur), access.RelayerRole, chain.PackageAddress(mockLcPkgPath))
	access.GrantRole(cross(cur), access.RelayerRole, relayerAAddr)

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

func fundRelayerA(cur realm, channelId types.ChannelId, quoteToken string, meta []byte) {
	order := z.TokenOrderV2{
		Sender:      []byte("remote-sender"),
		Receiver:    []byte(relayerAAddr.String()),
		BaseToken:   []byte("urly"),
		BaseAmount:  u256.NewUint(100),
		QuoteToken:  []byte(quoteToken),
		QuoteAmount: u256.NewUint(100),
		Kind:        z.TOKEN_ORDER_KIND_INITIALIZE,
		Metadata:    meta,
	}
	packet := core.NewPacket(types.ChannelId(2), channelId, mustPacketData(mustOrderInstruction(order)), types.Timestamp(1<<62))

	testing.SetRealm(testing.NewUserRealm(adminAddr))
	core.PacketRecv(cross(cur), core.NewMsgPacketRecv([]types.Packet{packet}, [][]byte{nil}, nil, 1))

	ufmt.Printf("[INFO] relayer A voucher balance: %d\n", zkgm.VoucherBalanceOf(quoteToken, relayerAAddr))
	ufmt.Println("[EXPECTED] relayer A voucher balance should be 100")
}

// frontUnderQuotedOrderAsRelayerA submits an under-quoted ESCROW order as
// relayer A with relayerMsg set to relayer B's address bytes. Because Base
// (10) < Quote (40), executeTokenOrderV2 falls back to marketMakerFillV2,
// which fronts the quote from the SUBMITTER's (A's) own voucher balance —
// relayerMsg never affects who funds the receiver, only who the ack later
// records as MarketMaker.
func frontUnderQuotedOrderAsRelayerA(cur realm, channelId types.ChannelId, quoteToken string) {
	order := z.TokenOrderV2{
		Sender:      []byte("remote-sender"),
		Receiver:    []byte(receiverAddr.String()),
		BaseToken:   []byte("urly"),
		BaseAmount:  u256.NewUint(10),
		QuoteToken:  []byte(quoteToken),
		QuoteAmount: u256.NewUint(40),
		Kind:        z.TOKEN_ORDER_KIND_ESCROW,
	}
	packet := core.NewPacket(types.ChannelId(2), channelId, mustPacketData(mustOrderInstruction(order)), types.Timestamp(1<<62))

	testing.SetRealm(testing.NewUserRealm(relayerAAddr))
	core.PacketRecv(cross(cur), core.NewMsgPacketRecv([]types.Packet{packet}, [][]byte{[]byte(relayerBAddr.String())}, nil, 1))

	ufmt.Printf("[INFO] relayer A voucher balance: %d\n", zkgm.VoucherBalanceOf(quoteToken, relayerAAddr))
	ufmt.Printf("[INFO] receiver voucher balance: %d\n", zkgm.VoucherBalanceOf(quoteToken, receiverAddr))
	ufmt.Println("[EXPECTED] relayer A voucher balance should be 60 (100 - 40 fronted from A's own balance)")
	ufmt.Println("[EXPECTED] receiver voucher balance should be 40 (fronted by A, regardless of relayerMsg)")
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

// acknowledgeMarketMakerFillToB acknowledges the sent packet with a
// market-maker-fill ack whose MarketMaker field names relayer B. settleEscrowedV2
// releases the escrow to whichever address the ack names, so it lands on B —
// not on relayer A (who did the fronting work in step 3) and not on the
// original sender.
func acknowledgeMarketMakerFillToB(cur realm, sendPacket types.Packet) {
	bk := banker.NewReadonlyBanker()
	proxy := zkgm.ProxyAddress()

	testing.SetRealm(testing.NewUserRealm(adminAddr))
	core.PacketAcknowledgement(cross(cur), core.NewMsgPacketAcknowledgement([]types.Packet{sendPacket}, [][]byte{mustMakerFillAck(relayerBAddr)}, nil, 1))

	ufmt.Printf("[INFO] proxy native escrow balance: %d\n", bk.GetCoins(proxy).AmountOf("ugnot"))
	ufmt.Printf("[INFO] relayer B native balance: %d\n", bk.GetCoins(relayerBAddr).AmountOf("ugnot"))
	ufmt.Printf("[INFO] relayer A native balance: %d\n", bk.GetCoins(relayerAAddr).AmountOf("ugnot"))
	ufmt.Printf("[INFO] original sender native balance: %d\n", bk.GetCoins(senderAddr).AmountOf("ugnot"))
	ufmt.Println("[EXPECTED] proxy native escrow balance should be 0 (released)")
	ufmt.Println("[EXPECTED] relayer B native balance should be 40 (settled to the designated address)")
	ufmt.Println("[EXPECTED] relayer A native balance should be 0 (A fronted liquidity elsewhere; A is not this ack's payee)")
	ufmt.Println("[EXPECTED] original sender native balance should be 0 (market-maker fill settles to the maker, not a refund to the sender)")
}

// --- encoding helpers ---

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

func mustMakerFillAck(maker address) []byte {
	inner, err := z.EncodeTokenOrderAck(z.TokenOrderAck{
		FillType:    new(u256.Uint).SetBytes(z.FILL_TYPE_MARKETMAKER[:]),
		MarketMaker: []byte(maker.String()),
	})
	if err != nil {
		panic(err)
	}
	ack, err := z.EncodeAck(z.Ack{Tag: new(u256.Uint).SetBytes(z.TAG_ACK_SUCCESS[:]), InnerAck: inner})
	if err != nil {
		panic(err)
	}
	return ack
}

// Output:
// [SCENARIO] 1. Bootstrap IBC host, open a channel, authorize relayer A
//
// [SCENARIO] 2. Fund relayer A with 100 of the voucher via a protocol-fill INITIALIZE recv
// [INFO] relayer A voucher balance: 100
// [EXPECTED] relayer A voucher balance should be 100
//
// [SCENARIO] 3. Relayer A fronts an under-quoted recv while designating relayer B via relayerMsg
// [INFO] relayer A voucher balance: 60
// [INFO] receiver voucher balance: 40
// [EXPECTED] relayer A voucher balance should be 60 (100 - 40 fronted from A's own balance)
// [EXPECTED] receiver voucher balance should be 40 (fronted by A, regardless of relayerMsg)
//
// [SCENARIO] 4. Send a separate native ESCROW order locking 40ugnot
// [INFO] proxy native escrow balance: 40
// [EXPECTED] proxy native escrow balance should be 40 (locked)
//
// [SCENARIO] 5. Acknowledge with a market-maker-fill ack naming B: escrow settles to B, not A or the sender
// [INFO] proxy native escrow balance: 0
// [INFO] relayer B native balance: 40
// [INFO] relayer A native balance: 0
// [INFO] original sender native balance: 0
// [EXPECTED] proxy native escrow balance should be 0 (released)
// [EXPECTED] relayer B native balance should be 40 (settled to the designated address)
// [EXPECTED] relayer A native balance should be 0 (A fronted liquidity elsewhere; A is not this ack's payee)
// [EXPECTED] original sender native balance should be 0 (market-maker fill settles to the maker, not a refund to the sender)
