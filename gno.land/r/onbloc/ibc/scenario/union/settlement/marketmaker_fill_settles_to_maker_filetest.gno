// PKGPATH: gno.land/r/onbloc/ibc/scenario/union/settlement
package settlement

// marketmaker_fill_settles_to_maker_filetest is the NORMAL-path settlement scenario for
// a market-maker fill (S-2.4). When a sent TokenOrder is filled on the counterparty by a
// market maker (rather than by the protocol), the returning acknowledgement is a
// success ack whose inner TokenOrderAck carries FILL_TYPE_MARKETMAKER and the maker's
// address. On that ack, acknowledgeTokenOrderV2 does not refund the sender and does not
// leave the escrow locked — it releases the escrowed base to the recorded market maker,
// reimbursing the liquidity the maker fronted on the destination. This file escrows 40
// of a voucher on send, then acknowledges with a maker-fill ack and verifies the escrow
// moves to the maker (proxy 40 -> 0, maker 0 -> 40) while the sender's balance is
// unchanged (not refunded). The maker-fill ack is built from the public zkgm encoders.

import (
	"chain"
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
	makerAddr  = address("g1dyxy88p94acjnm8dmu9tfj2mv2ncvx83cagllu")
)

func main(cur realm) {
	println("[SCENARIO] 1. Bootstrap IBC host and open a zkgm channel")
	channelId := bootstrap(cur)
	println("")

	meta := mustTokenMetadata("grc20", z.TokenInitializer{Name: "Gno Token", Symbol: "GNOT", Decimals: 6})
	quoteToken := z.PredictWrappedTokenV2(u256.Zero(), uint32(channelId), []byte("ugnot"), z.MetadataImage(mustDecodeMeta(meta)))

	println("[SCENARIO] 2. Fund the sender with 100 of the voucher via an INITIALIZE recv")
	fundSender(cur, channelId, quoteToken, meta)
	println("")

	println("[SCENARIO] 3. ESCROW send locks 40 in the proxy escrow")
	sendPacket := sendEscrow(cur, channelId, quoteToken)
	println("")

	println("[SCENARIO] 4. A market-maker-fill ack settles the escrow to the maker (not the sender)")
	makerFillAck(cur, sendPacket, quoteToken)
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

func fundSender(cur realm, channelId types.ChannelId, quoteToken string, meta []byte) {
	order := z.TokenOrderV2{
		Sender:      []byte("remote-sender"),
		Receiver:    []byte(senderAddr.String()),
		BaseToken:   []byte("ugnot"),
		BaseAmount:  u256.NewUint(100),
		QuoteToken:  []byte(quoteToken),
		QuoteAmount: u256.NewUint(100),
		Kind:        z.TOKEN_ORDER_KIND_INITIALIZE,
		Metadata:    meta,
	}
	packet := core.NewPacket(types.ChannelId(2), channelId, mustPacketData(mustOrderInstruction(order)), types.Timestamp(1<<62))

	testing.SetRealm(testing.NewUserRealm(adminAddr))
	core.PacketRecv(cross(cur), core.NewMsgPacketRecv([]types.Packet{packet}, [][]byte{nil}, nil, 1))
	ufmt.Printf("[INFO] sender voucher balance: %d\n", zkgm.VoucherBalanceOf(quoteToken, senderAddr))
	ufmt.Println("[EXPECTED] sender should hold 100")
}

func sendEscrow(cur realm, channelId types.ChannelId, quoteToken string) types.Packet {
	order := z.TokenOrderV2{
		Sender:      []byte(senderAddr.String()),
		Receiver:    []byte("remote-receiver"),
		BaseToken:   []byte(quoteToken),
		BaseAmount:  u256.NewUint(40),
		QuoteToken:  []byte("ugnot"),
		QuoteAmount: u256.NewUint(40),
		Kind:        z.TOKEN_ORDER_KIND_ESCROW,
	}

	testing.SetRealm(testing.NewUserRealm(senderAddr))
	sendPacket := zkgm.Send(cross(cur), channelId, types.Timestamp(1<<62), [32]byte{}, mustOrderInstruction(order))

	ufmt.Printf("[INFO] sender voucher: %d, proxy escrow: %d\n", zkgm.VoucherBalanceOf(quoteToken, senderAddr), zkgm.VoucherBalanceOf(quoteToken, zkgm.ProxyAddress()))
	ufmt.Println("[EXPECTED] sender 100 -> 60, proxy escrow 0 -> 40")
	return sendPacket
}

func makerFillAck(cur realm, sendPacket types.Packet, quoteToken string) {
	senderBefore := zkgm.VoucherBalanceOf(quoteToken, senderAddr)
	proxyBefore := zkgm.VoucherBalanceOf(quoteToken, zkgm.ProxyAddress())
	makerBefore := zkgm.VoucherBalanceOf(quoteToken, makerAddr)

	testing.SetRealm(testing.NewUserRealm(adminAddr))
	core.PacketAcknowledgement(cross(cur), core.NewMsgPacketAcknowledgement([]types.Packet{sendPacket}, [][]byte{mustMakerFillAck(makerAddr)}, nil, 1))

	ufmt.Printf("[INFO] sender voucher: %d -> %d (delta %d)\n", senderBefore, zkgm.VoucherBalanceOf(quoteToken, senderAddr), zkgm.VoucherBalanceOf(quoteToken, senderAddr)-senderBefore)
	ufmt.Printf("[INFO] proxy escrow:   %d -> %d (delta %d)\n", proxyBefore, zkgm.VoucherBalanceOf(quoteToken, zkgm.ProxyAddress()), zkgm.VoucherBalanceOf(quoteToken, zkgm.ProxyAddress())-proxyBefore)
	ufmt.Printf("[INFO] maker voucher:  %d -> %d (delta +%d)\n", makerBefore, zkgm.VoucherBalanceOf(quoteToken, makerAddr), zkgm.VoucherBalanceOf(quoteToken, makerAddr)-makerBefore)
	ufmt.Println("[EXPECTED] escrow settles to the maker: proxy 40 -> 0, maker 0 -> 40, sender unchanged (not refunded)")
}

// mustMakerFillAck builds a success ack whose inner TokenOrderAck is a market-maker fill
// designating maker as the settlement recipient, using the public zkgm encoders.
func mustMakerFillAck(maker address) []byte {
	innerAck, err := z.EncodeTokenOrderAck(z.TokenOrderAck{
		FillType:    z.Uint256FromBytes32(z.FILL_TYPE_MARKETMAKER),
		MarketMaker: []byte(maker.String()),
	})
	if err != nil {
		panic(err)
	}
	ack, err := z.EncodeAck(z.Ack{Tag: z.Uint256FromBytes32(z.TAG_ACK_SUCCESS), InnerAck: innerAck})
	if err != nil {
		panic(err)
	}
	return ack
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

// Output:
// [SCENARIO] 1. Bootstrap IBC host and open a zkgm channel
//
// [SCENARIO] 2. Fund the sender with 100 of the voucher via an INITIALIZE recv
// [INFO] sender voucher balance: 100
// [EXPECTED] sender should hold 100
//
// [SCENARIO] 3. ESCROW send locks 40 in the proxy escrow
// [INFO] sender voucher: 60, proxy escrow: 40
// [EXPECTED] sender 100 -> 60, proxy escrow 0 -> 40
//
// [SCENARIO] 4. A market-maker-fill ack settles the escrow to the maker (not the sender)
// [INFO] sender voucher: 60 -> 60 (delta 0)
// [INFO] proxy escrow:   40 -> 0 (delta -40)
// [INFO] maker voucher:  0 -> 40 (delta +40)
// [EXPECTED] escrow settles to the maker: proxy 40 -> 0, maker 0 -> 40, sender unchanged (not refunded)
