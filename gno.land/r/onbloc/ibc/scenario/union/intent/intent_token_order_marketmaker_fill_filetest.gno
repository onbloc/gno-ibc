// PKGPATH: gno.land/r/onbloc/ibc/scenario/union/intent
package intent

// intent_token_order_marketmaker_fill_filetest is the NORMAL-path intent
// scenario. core.IntentPacketRecv is the proofless market-maker fast path:
// OnIntentRecvPacket dispatches every opcode with intent=true, and
// executeTokenOrderV2 special-cases intent exactly like Kind=SOLVE — `if
// intent || order.Kind == z.TOKEN_ORDER_KIND_SOLVE { return
// v.marketMakerFillV2(...) }` — so a TokenOrder submitted through intent is
// always maker-only, even for a fully-quoted ESCROW that would otherwise
// protocol-fill. The submitting address becomes the maker
// (rlm.Previous().Address() in core's IntentPacketRecv), fronting the quote
// from its own voucher balance, exactly like the SOLVE scenario but reached
// through the proofless entrypoint instead of a proven PacketRecv.

import (
	"chain"
	"testing"

	"gno.land/p/nt/ufmt/v0"
	types "gno.land/p/onbloc/ibc/union/types"
	z "gno.land/p/onbloc/ibc/union/zkgm"

	u256 "gno.land/p/gnoswap/uint256"

	"gno.land/r/demo/defi/grc20reg"
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

	adminAddr    = address("g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5")
	makerAddr    = address("g1dyxy88p94acjnm8dmu9tfj2mv2ncvx83cagllu")
	receiverAddr = address("g1wymu47drhr0kuq2098m792lytgtj2nyx77yrsm")
)

func main(cur realm) {
	println("[SCENARIO] 1. Bootstrap IBC host and open a zkgm channel")
	channelId := bootstrap(cur)
	println("")

	meta := mustTokenMetadata("grc20", z.TokenInitializer{Name: "Gno Token", Symbol: "GNOT", Decimals: 6})
	quoteToken := z.PredictWrappedTokenV2(u256.Zero(), uint32(channelId), []byte("ugnot"), z.MetadataImage(mustDecodeMeta(meta)))

	println("[SCENARIO] 2. Fund the maker with 100 of the voucher via a proven, protocol-fill INITIALIZE recv")
	fundMaker(cur, channelId, quoteToken, meta)
	println("")

	println("[SCENARIO] 3. A fully-quoted ESCROW order submitted through proofless intent recv is still maker-only")
	intentRecvEscrowOrder(cur, channelId, quoteToken)
}

func bootstrap(cur realm) types.ChannelId {
	testing.SetRealm(testing.NewUserRealm(adminAddr))
	core.UpdateImpl(cross(cur), coreImplPath)
	zkgm.UpdateImpl(cross(cur), zkgmImplPath)
	zkgm.SetRateLimitDisabled(cross(cur), true)
	zkgm.RegisterCoreApp(cross(cur))
	access.GrantRole(cross(cur), access.RelayerRole, adminAddr)
	access.GrantRole(cross(cur), access.RelayerRole, makerAddr)
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

// fundMaker mints 100 of the wrapped voucher to the maker via a normal, proven
// protocol-fill INITIALIZE recv (deploying the wrapped token), so the maker
// has a real balance to front from in step 3, and the voucher is registered
// for marketMakerFillV2's HasVoucher gate to pass on the intent recv.
func fundMaker(cur realm, channelId types.ChannelId, quoteToken string, meta []byte) {
	order := z.TokenOrderV2{
		Sender:      []byte("remote-sender"),
		Receiver:    []byte(makerAddr.String()),
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

	token := grc20reg.MustGet(zkgm.ProxyPkgPath() + "." + quoteToken[len("ibc/"):])
	ufmt.Printf("[INFO] deployed token name/symbol/decimals: %s/%s/%d\n", token.GetName(), token.GetSymbol(), token.GetDecimals())
	ufmt.Printf("[INFO] maker voucher balance: %d\n", zkgm.VoucherBalanceOf(quoteToken, makerAddr))
	ufmt.Println("[EXPECTED] maker voucher balance should be 100")
}

// intentRecvEscrowOrder submits a fully-quoted ESCROW order (30 == 30) through
// the proofless intent path. If this went through a proven PacketRecv,
// baseCovers would be true and it would protocol-fill (a fresh mint). Because
// it goes through IntentPacketRecv, executeTokenOrderV2 forces marketMakerFillV2
// regardless, and the maker (the caller submitting this intent recv) fronts
// the quote from its own voucher balance.
func intentRecvEscrowOrder(cur realm, channelId types.ChannelId, quoteToken string) {
	order := z.TokenOrderV2{
		Sender:      []byte("remote-sender"),
		Receiver:    []byte(receiverAddr.String()),
		BaseToken:   []byte("ugnot"),
		BaseAmount:  u256.NewUint(30),
		QuoteToken:  []byte(quoteToken),
		QuoteAmount: u256.NewUint(30),
		Kind:        z.TOKEN_ORDER_KIND_ESCROW,
	}
	packet := core.NewPacket(types.ChannelId(2), channelId, mustPacketData(mustOrderInstruction(order)), types.Timestamp(1<<62))

	ufmt.Println("[INFO] order BaseAmount=30, QuoteAmount=30 (fully quoted: base == quote)")
	ufmt.Println("[INFO] intent recv forces marketMakerFillV2 regardless of baseCovers, unlike a proven PacketRecv")

	testing.SetRealm(testing.NewUserRealm(makerAddr))
	core.IntentPacketRecv(cross(cur), types.NewMsgIntentPacketRecv([]types.Packet{packet}, [][]byte{nil}))

	ufmt.Printf("[INFO] maker voucher balance: %d\n", zkgm.VoucherBalanceOf(quoteToken, makerAddr))
	ufmt.Printf("[INFO] receiver voucher balance: %d\n", zkgm.VoucherBalanceOf(quoteToken, receiverAddr))
	ufmt.Println("[EXPECTED] maker voucher balance should be 70 (100 - 30 fronted to the receiver)")
	ufmt.Println("[EXPECTED] receiver voucher balance should be 30 (fronted by the maker, not protocol-minted)")
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
// [SCENARIO] 2. Fund the maker with 100 of the voucher via a proven, protocol-fill INITIALIZE recv
// [INFO] deployed token name/symbol/decimals: Gno Token/GNOT/6
// [INFO] maker voucher balance: 100
// [EXPECTED] maker voucher balance should be 100
//
// [SCENARIO] 3. A fully-quoted ESCROW order submitted through proofless intent recv is still maker-only
// [INFO] order BaseAmount=30, QuoteAmount=30 (fully quoted: base == quote)
// [INFO] intent recv forces marketMakerFillV2 regardless of baseCovers, unlike a proven PacketRecv
// [INFO] maker voucher balance: 70
// [INFO] receiver voucher balance: 30
// [EXPECTED] maker voucher balance should be 70 (100 - 30 fronted to the receiver)
// [EXPECTED] receiver voucher balance should be 30 (fronted by the maker, not protocol-minted)
