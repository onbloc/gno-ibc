// PKGPATH: gno.land/r/onbloc/ibc/scenario/union/settlement
package settlement

// initialize_then_escrow_voucher_lifecycle_filetest is the NORMAL-path settlement
// scenario for the wrapped-voucher lifecycle (re-targeted from the legacy e2e
// zs13). An INITIALIZE order deploys the wrapped token and mints its amount; a
// following ESCROW order for the same asset mints more into the existing voucher.
// Each step is verified as a balance diff plus a recorded receipt. (The legacy
// `zkgm.GetTokenOrigin` introspection is now store-internal, so origin tracking is
// not asserted here — the minted balance is the observable that matters.)

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

	adminAddr    = address("g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5")
	receiverAddr = address("g1wymu47drhr0kuq2098m792lytgtj2nyx77yrsm")
)

func main(cur realm) {
	println("[SCENARIO] 1. Bootstrap IBC host and open a zkgm channel")
	channelId := bootstrap(cur)
	println("")

	meta := mustTokenMetadata("\xaf\x73\x9f\x34\xdd\xf9\x51\xcb\xc2\x4f\xdb\xba\x4f\x76\x21\x36\x88\xe1\x36\x27", z.TokenInitializer{Name: "Gno Token", Symbol: "GNOT", Decimals: 6})
	quoteToken := z.PredictWrappedTokenV2(u256.Zero(), uint32(channelId), []byte("ugnot"), z.MetadataImage(mustDecodeMeta(meta)))

	println("[SCENARIO] 2. INITIALIZE order: deploy the wrapped token and mint 33")
	receiveOrder(cur, channelId, "INITIALIZE", initializeOrder(quoteToken, meta), quoteToken, 33)
	println("")

	println("[SCENARIO] 3. ESCROW order: mint 21 more into the existing voucher")
	receiveOrder(cur, channelId, "ESCROW", escrowOrder(quoteToken), quoteToken, 54)
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

func initializeOrder(quoteToken string, meta []byte) z.TokenOrderV2 {
	return z.TokenOrderV2{
		Sender:      []byte("remote-sender"),
		Receiver:    []byte(receiverAddr.String()),
		BaseToken:   []byte("ugnot"),
		BaseAmount:  u256.NewUint(33),
		QuoteToken:  []byte(quoteToken),
		QuoteAmount: u256.NewUint(33),
		Kind:        z.TOKEN_ORDER_KIND_INITIALIZE,
		Metadata:    meta,
	}
}

func escrowOrder(quoteToken string) z.TokenOrderV2 {
	return z.TokenOrderV2{
		Sender:      []byte("remote-sender"),
		Receiver:    []byte(receiverAddr.String()),
		BaseToken:   []byte("ugnot"),
		BaseAmount:  u256.NewUint(21),
		QuoteToken:  []byte(quoteToken),
		QuoteAmount: u256.NewUint(21),
		Kind:        z.TOKEN_ORDER_KIND_ESCROW,
	}
}

// receiveOrder receives one TokenOrder and reports the receiver's voucher balance
// as a before/after diff plus the recorded receipt; expectedTotal is the asserted
// cumulative balance after this order.
func receiveOrder(cur realm, channelId types.ChannelId, kind string, order z.TokenOrderV2, quoteToken string, expectedTotal int64) {
	packet := core.NewPacket(types.ChannelId(2), channelId, mustPacketData(mustOrderInstruction(order)), types.Timestamp(1<<62))

	before := zkgm.VoucherBalanceOf(quoteToken, receiverAddr)

	testing.SetRealm(testing.NewUserRealm(adminAddr))
	core.PacketRecv(cross(cur), core.NewMsgPacketRecv([]types.Packet{packet}, [][]byte{nil}, nil, 1))

	after := zkgm.VoucherBalanceOf(quoteToken, receiverAddr)
	ufmt.Printf("[INFO] %s: receiver voucher balance %d -> %d (delta +%d)\n", kind, before, after, after-before)
	ufmt.Printf("[INFO] %s: packet receipt recorded: %t\n", kind, receiptRecorded(packet))
	ufmt.Printf("[EXPECTED] cumulative voucher balance should be %d\n", expectedTotal)
}

func receiptRecorded(packet types.Packet) bool {
	_, err := core.GetBatchReceipts(core.CommitPacketsHash([]types.Packet{packet}))
	return err == nil
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
// [SCENARIO] 2. INITIALIZE order: deploy the wrapped token and mint 33
// [INFO] INITIALIZE: receiver voucher balance 0 -> 33 (delta +33)
// [INFO] INITIALIZE: packet receipt recorded: true
// [EXPECTED] cumulative voucher balance should be 33
//
// [SCENARIO] 3. ESCROW order: mint 21 more into the existing voucher
// [INFO] ESCROW: receiver voucher balance 33 -> 54 (delta +21)
// [INFO] ESCROW: packet receipt recorded: true
// [EXPECTED] cumulative voucher balance should be 54
