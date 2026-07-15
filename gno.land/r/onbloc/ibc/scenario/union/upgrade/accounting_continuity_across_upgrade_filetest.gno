// PKGPATH: gno.land/r/onbloc/ibc/scenario/union/upgrade
package upgrade

// accounting_continuity_across_upgrade_filetest is the NORMAL-path upgrade scenario for
// behaviour continuity (S-3.1). It exercises a receive both before and after an impl
// re-install and shows the accounting is continuous: an INITIALIZE recv mints 100, the
// admin re-installs the impl (rebuilding it against the same proxy-owned store), and a
// follow-up ESCROW recv of the same wrapped token mints 50 more for a cumulative 150.
// Recv works identically on either side of the upgrade and the ledger accumulates across
// it, so the swap is invisible to accounting. (Only the v1 constructor is registered, so
// UpdateImpl re-points to the same path; the model allows pointing at any registered
// constructor, but the store — and thus the accounting — is always the proxy's.)

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

	println("[SCENARIO] 2. Before upgrade: INITIALIZE recv mints 100")
	recvMint(cur, channelId, quoteToken, meta, z.TOKEN_ORDER_KIND_INITIALIZE, 100, saltSeed(1))
	ufmt.Printf("[INFO] voucher balance: %d\n", zkgm.VoucherBalanceOf(quoteToken, receiverAddr))
	ufmt.Println("[EXPECTED] 100")
	println("")

	println("[SCENARIO] 3. Re-install the impl (rebuilt against the same proxy-owned store)")
	reinstallImpl(cur)
	println("")

	println("[SCENARIO] 4. After upgrade: ESCROW recv mints 50 more, accounting continues")
	recvMint(cur, channelId, quoteToken, meta, z.TOKEN_ORDER_KIND_ESCROW, 50, saltSeed(2))
	ufmt.Printf("[INFO] voucher balance: %d\n", zkgm.VoucherBalanceOf(quoteToken, receiverAddr))
	ufmt.Println("[EXPECTED] 150 (100 pre-upgrade + 50 post-upgrade): the ledger is continuous across the swap")
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

func recvMint(cur realm, channelId types.ChannelId, quoteToken string, meta []byte, kind uint8, amount uint64, salt [32]byte) {
	order := z.TokenOrderV2{
		Sender:      []byte("remote-sender"),
		Receiver:    []byte(receiverAddr.String()),
		BaseToken:   []byte("ugnot"),
		BaseAmount:  u256.NewUint(amount),
		QuoteToken:  []byte(quoteToken),
		QuoteAmount: u256.NewUint(amount),
		Kind:        kind,
		Metadata:    meta,
	}
	packet := core.NewPacket(types.ChannelId(2), channelId, saltedPacketData(salt, mustOrderInstruction(order)), types.Timestamp(1<<62))

	testing.SetRealm(testing.NewUserRealm(adminAddr))
	core.PacketRecv(cross(cur), core.NewMsgPacketRecv([]types.Packet{packet}, [][]byte{nil}, nil, 1))
}

func reinstallImpl(cur realm) {
	testing.SetRealm(testing.NewUserRealm(adminAddr))
	zkgm.UpdateImpl(cross(cur), zkgmImplPath)
	println("[INFO] impl re-installed")
}

func saltSeed(b byte) [32]byte {
	var s [32]byte
	s[31] = b
	return s
}

// --- encoding helpers ---

func mustOrderInstruction(order z.TokenOrderV2) z.Instruction {
	operand, err := z.EncodeTokenOrderV2(order)
	if err != nil {
		panic(err)
	}
	return z.Instruction{Version: z.INSTR_VERSION_2, Opcode: z.OP_TOKEN_ORDER, Operand: operand}
}

func saltedPacketData(salt [32]byte, instr z.Instruction) []byte {
	data, err := z.EncodeZkgmPacket(z.ZkgmPacket{Salt: salt, Path: u256.Zero(), Instruction: instr})
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
// [SCENARIO] 2. Before upgrade: INITIALIZE recv mints 100
// [INFO] voucher balance: 100
// [EXPECTED] 100
//
// [SCENARIO] 3. Re-install the impl (rebuilt against the same proxy-owned store)
// [INFO] impl re-installed
//
// [SCENARIO] 4. After upgrade: ESCROW recv mints 50 more, accounting continues
// [INFO] voucher balance: 150
// [EXPECTED] 150 (100 pre-upgrade + 50 post-upgrade): the ledger is continuous across the swap
