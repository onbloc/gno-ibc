// PKGPATH: gno.land/r/onbloc/ibc/scenario/union/settlement
package settlement

// voucher_supply_conservation_filetest is the NORMAL-path settlement scenario for
// wrapped-voucher supply conservation (re-targeted from the legacy e2e zs21
// conservation invariant, voucher side). Mints (INITIALIZE + ESCROW receives) add to
// the holder's voucher balance and an UNESCROW send burns from it; at every step the
// holder's balance must equal Σmint − Σburn exactly — no voucher is created or
// destroyed off-ledger.

import (
	"encoding/hex"
	"chain"
	"testing"

	"gno.land/p/nt/ufmt/v0"
	"gno.land/p/onbloc/ibc/union/types"
	z "gno.land/p/onbloc/ibc/union/zkgm"

	u256 "gno.land/p/gnoswap/uint256"

	"gno.land/r/demo/defi/grc20reg"
	mocklc "gno.land/r/onbloc/ibc/testing/mock/lightclient"
	"gno.land/r/onbloc/ibc/union/access"
	zkgm "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm"
	_ "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/v1"
	"gno.land/r/onbloc/ibc/union/core"
	_ "gno.land/r/onbloc/ibc/union/core/v1"
)

const (
	coreImplPath  = "gno.land/r/onbloc/ibc/union/core/v1"
	zkgmImplPath  = "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/v1"
	mockLcPkgPath = "gno.land/r/onbloc/ibc/testing/mock/lightclient"

	adminAddr  = address("g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5")
	holderAddr = address("g1wymu47drhr0kuq2098m792lytgtj2nyx77yrsm")
)

// running Σmint − Σburn, tracked alongside the on-ledger balance.
var expected int64

func main(cur realm) {
	println("[SCENARIO] 1. Bootstrap IBC host and open a zkgm channel")
	channelId := bootstrap(cur)
	println("")

	meta := mustTokenMetadata("af739f34ddf951cbc24fdbba4f76213688e13627", z.TokenInitializer{Name: "Gno Token", Symbol: "GNOT", Decimals: 6})
	quoteToken := z.PredictWrappedTokenV2(u256.Zero(), uint32(channelId), []byte("ugnot"), z.MetadataImage(mustDecodeMeta(meta)))

	println("[SCENARIO] 2. INITIALIZE recv mints 100")
	mintRecv(cur, channelId, quoteToken, meta, z.TOKEN_ORDER_KIND_INITIALIZE, 100)
	println("")

	println("[SCENARIO] 3. ESCROW recv mints 50 more into the same voucher")
	mintRecv(cur, channelId, quoteToken, meta, z.TOKEN_ORDER_KIND_ESCROW, 50)
	println("")

	println("[SCENARIO] 4. UNESCROW send burns 80 from the holder")
	burnSend(cur, channelId, quoteToken, 80)
	println("")

	println("[SCENARIO] 5. Conservation: holder balance and token total supply equal Σmint − Σburn")
	conservation(quoteToken)
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

func mintRecv(cur realm, channelId types.ChannelId, quoteToken string, meta []byte, kind uint8, amount int64) {
	order := z.TokenOrderV2{
		Sender:      []byte("remote-sender"),
		Receiver:    []byte(holderAddr.String()),
		BaseToken:   []byte("ugnot"),
		BaseAmount:  u256.NewUint(uint64(amount)),
		QuoteToken:  []byte(quoteToken),
		QuoteAmount: u256.NewUint(uint64(amount)),
		Kind:        kind,
		Metadata:    meta,
	}
	packet := core.NewPacket(types.ChannelId(2), channelId, mustPacketData(mustOrderInstruction(order)), types.Timestamp(1<<62))

	testing.SetRealm(testing.NewUserRealm(adminAddr))
	core.PacketRecv(cross(cur), core.NewMsgPacketRecv([]types.Packet{packet}, [][]byte{nil}, nil, 1))

	expected += amount
	reportBalance(quoteToken, "after mint")
}

func burnSend(cur realm, channelId types.ChannelId, quoteToken string, amount int64) {
	order := z.TokenOrderV2{
		Sender:      []byte(holderAddr.String()),
		Receiver:    []byte("remote-receiver"),
		BaseToken:   []byte(quoteToken),
		BaseAmount:  u256.NewUint(uint64(amount)),
		QuoteToken:  []byte("ugnot"),
		QuoteAmount: u256.NewUint(uint64(amount)),
		Kind:        z.TOKEN_ORDER_KIND_UNESCROW,
	}

	testing.SetRealm(testing.NewUserRealm(holderAddr))
	_ = zkgm.Send(cross(cur), channelId, types.Timestamp(1<<62), [32]byte{}, mustOrderInstruction(order))

	expected -= amount
	reportBalance(quoteToken, "after burn")
}

func reportBalance(quoteToken, label string) {
	ufmt.Printf("[INFO] holder voucher balance %s: %d (Σmint−Σburn = %d)\n", label, zkgm.VoucherBalanceOf(quoteToken, holderAddr), expected)
}

func conservation(quoteToken string) {
	bal := zkgm.VoucherBalanceOf(quoteToken, holderAddr)
	supply := grc20reg.MustGet(zkgm.ProxyPkgPath() + "." + quoteToken[len("ibc/"):]).TotalSupply()
	ufmt.Printf("[INFO] holder balance = %d, Σmint−Σburn = %d, conserved = %t\n", bal, expected, bal == expected)
	ufmt.Printf("[INFO] token total supply = %d, Σmint−Σburn = %d, conserved = %t\n", supply, expected, supply == expected)
	ufmt.Println("[EXPECTED] holder balance and token total supply should equal 100 + 50 − 80 = 70 (conserved)")
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

func mustTokenMetadata(implementationHex string, ti z.TokenInitializer) []byte {
	implementation, err := hex.DecodeString(implementationHex)
	if err != nil {
		panic(err)
	}
	initBytes, err := z.EncodeTokenInitializer(ti)
	if err != nil {
		panic(err)
	}
	meta, err := z.EncodeTokenMetadata(z.TokenMetadata{Implementation: implementation, Initializer: initBytes})
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
// [SCENARIO] 2. INITIALIZE recv mints 100
// [INFO] holder voucher balance after mint: 100 (Σmint−Σburn = 100)
//
// [SCENARIO] 3. ESCROW recv mints 50 more into the same voucher
// [INFO] holder voucher balance after mint: 150 (Σmint−Σburn = 150)
//
// [SCENARIO] 4. UNESCROW send burns 80 from the holder
// [INFO] holder voucher balance after burn: 70 (Σmint−Σburn = 70)
//
// [SCENARIO] 5. Conservation: holder balance and token total supply equal Σmint − Σburn
// [INFO] holder balance = 70, Σmint−Σburn = 70, conserved = true
// [INFO] token total supply = 70, Σmint−Σburn = 70, conserved = true
// [EXPECTED] holder balance and token total supply should equal 100 + 50 − 80 = 70 (conserved)
