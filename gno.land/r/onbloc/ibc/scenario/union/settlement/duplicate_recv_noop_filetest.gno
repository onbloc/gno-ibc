// PKGPATH: gno.land/r/onbloc/ibc/scenario/union/settlement
package settlement

// duplicate_recv_noop_filetest is the BY-TYPE settlement scenario for receive
// idempotency (re-targeted from the legacy e2e zs14a). A packet is received once,
// minting the wrapped voucher and recording the receipt; receiving the *same*
// packet again is a no-op — the receipt stays recorded and the balance does not
// change. The second receive must neither panic nor double-mint.

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

	meta := mustTokenMetadata("grc20", z.TokenInitializer{Name: "Gno Token", Symbol: "GNOT", Decimals: 6})
	quoteToken := z.PredictWrappedTokenV2(u256.Zero(), uint32(channelId), []byte("ugnot"), z.MetadataImage(mustDecodeMeta(meta)))
	packet := core.NewPacket(types.ChannelId(2), channelId, mustPacketData(mustOrderInstruction(initOrder(quoteToken, meta))), types.Timestamp(1<<62))

	println("[SCENARIO] 2. First receive mints the voucher and records the receipt")
	firstRecv(cur, packet, quoteToken)
	println("")

	println("[SCENARIO] 3. Receiving the same packet again is a no-op (idempotent)")
	duplicateRecv(cur, packet, quoteToken)
}

// bootstrap installs the impls, grants the relayer role, and opens a client/
// connection/channel backed by the shared permissive mock light client.
func bootstrap(cur realm) types.ChannelId {
	testing.SetRealm(testing.NewUserRealm(adminAddr))
	core.UpdateImpl(cross(cur), coreImplPath)
	zkgm.UpdateImpl(cross(cur), zkgmImplPath)
	zkgm.SetRateLimitDisabled(cross(cur), true)
	zkgm.RegisterCoreApp(cross(cur))
	access.GrantRole(cross(cur), access.RelayerRole, adminAddr)
	// The shared mock LC realm self-registers via core.RegisterClient, so it is the
	// caller there — grant RELAYER to the mock realm's own address too.
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

func initOrder(quoteToken string, meta []byte) z.TokenOrderV2 {
	return z.TokenOrderV2{
		Sender:      []byte("remote-sender"),
		Receiver:    []byte(receiverAddr.String()),
		BaseToken:   []byte("ugnot"),
		BaseAmount:  u256.NewUint(100),
		QuoteToken:  []byte(quoteToken),
		QuoteAmount: u256.NewUint(100),
		Kind:        z.TOKEN_ORDER_KIND_INITIALIZE,
		Metadata:    meta,
	}
}

func firstRecv(cur realm, packet types.Packet, quoteToken string) {
	before := zkgm.VoucherBalanceOf(quoteToken, receiverAddr)

	testing.SetRealm(testing.NewUserRealm(adminAddr))
	core.PacketRecv(cross(cur), core.NewMsgPacketRecv([]types.Packet{packet}, [][]byte{nil}, nil, 1))

	after := zkgm.VoucherBalanceOf(quoteToken, receiverAddr)
	ufmt.Printf("[INFO] receiver voucher balance: %d -> %d (delta +%d)\n", before, after, after-before)
	ufmt.Printf("[INFO] packet receipt recorded: %t\n", receiptRecorded(packet))
	ufmt.Println("[EXPECTED] first receive should mint 100 and record the receipt")
}

func duplicateRecv(cur realm, packet types.Packet, quoteToken string) {
	before := zkgm.VoucherBalanceOf(quoteToken, receiverAddr)

	testing.SetRealm(testing.NewUserRealm(adminAddr))
	core.PacketRecv(cross(cur), core.NewMsgPacketRecv([]types.Packet{packet}, [][]byte{nil}, nil, 1))

	after := zkgm.VoucherBalanceOf(quoteToken, receiverAddr)
	ufmt.Printf("[INFO] receiver voucher balance: %d -> %d (delta +%d)\n", before, after, after-before)
	ufmt.Printf("[INFO] packet receipt still recorded: %t\n", receiptRecorded(packet))
	ufmt.Println("[EXPECTED] duplicate receive should be a no-op: balance unchanged, receipt still recorded")
}

// receiptRecorded re-targets the removed core.HasPacketReceipt to the current
// GetBatchReceipts getter: a recorded receipt resolves without error.
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
// [SCENARIO] 2. First receive mints the voucher and records the receipt
// [INFO] receiver voucher balance: 0 -> 100 (delta +100)
// [INFO] packet receipt recorded: true
// [EXPECTED] first receive should mint 100 and record the receipt
//
// [SCENARIO] 3. Receiving the same packet again is a no-op (idempotent)
// [INFO] receiver voucher balance: 100 -> 100 (delta +0)
// [INFO] packet receipt still recorded: true
// [EXPECTED] duplicate receive should be a no-op: balance unchanged, receipt still recorded
