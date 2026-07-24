// PKGPATH: gno.land/r/onbloc/ibc/scenario/union/ratelimit
package ratelimit

// recv_salt_dedup_filetest is the BY-TYPE scenario for packet de-duplication via
// salt (re-targeted from the legacy e2e zs87). A packet's commitment is determined
// by its salt: the same sender+salt derives the same salt and yields the same
// packet commitment, while a different salt yields a distinct one. On receive, a
// repeated packet is swallowed by the receipt guard (no double mint), while a
// distinct-salt packet is processed independently.

import (
	"encoding/hex"
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

	tokenA := newToken(channelId, "ugnot", "Dedup Token", "DDP")
	tokenB := newToken(channelId, "uother", "Other Dedup Token", "DDP2")

	println("[SCENARIO] 2. Salt derivation and packet commitment are deterministic")
	saltA, saltB := saltDeterminism(channelId, tokenA, tokenB)
	println("")

	println("[SCENARIO] 3. A repeated packet (same salt) is swallowed by the receipt guard")
	dedupSameSalt(cur, channelId, tokenA, saltA)
	println("")

	println("[SCENARIO] 4. A different-salt packet is a distinct packet, processed independently")
	distinctSalt(cur, channelId, tokenB, saltB)
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

// token bundles a base denom with its metadata and the derived wrapped voucher.
type token struct {
	base       string
	meta       []byte
	quoteToken string
}

func newToken(channelId types.ChannelId, base, name, symbol string) token {
	meta := mustTokenMetadata("af739f34ddf951cbc24fdbba4f76213688e13627", z.TokenInitializer{Name: name, Symbol: symbol, Decimals: 6})
	quoteToken := z.PredictWrappedTokenV2(u256.Zero(), uint32(channelId), []byte(base), z.MetadataImage(mustDecodeMeta(meta)))
	return token{base: base, meta: meta, quoteToken: quoteToken}
}

func (t token) order() z.TokenOrderV2 {
	return z.TokenOrderV2{
		Sender:      []byte("same-sender"),
		Receiver:    []byte(receiverAddr.String()),
		BaseToken:   []byte(t.base),
		BaseAmount:  u256.NewUint(10),
		QuoteToken:  []byte(t.quoteToken),
		QuoteAmount: u256.NewUint(10),
		Kind:        z.TOKEN_ORDER_KIND_INITIALIZE,
		Metadata:    t.meta,
	}
}

// saltDeterminism asserts salt derivation determinism and packet-commitment
// determinism, returning the two derived salts used by the recv scenarios.
func saltDeterminism(channelId types.ChannelId, tokenA, tokenB token) (saltA, saltB [32]byte) {
	var rawA, rawB [32]byte
	rawA[31] = 1
	rawB[31] = 2

	sender := tokenA.order().Sender
	saltA = z.DeriveSenderSalt(sender, rawA)
	saltA2 := z.DeriveSenderSalt(sender, rawA)
	saltB = z.DeriveSenderSalt(sender, rawB)
	ufmt.Printf("[INFO] same sender+salt derives equal salt: %t\n", saltA == saltA2)
	ufmt.Printf("[INFO] different salt derives distinct salt: %t\n", saltA != saltB)

	packetA := saltedPacket(channelId, saltA, tokenA.order())
	packetA2 := saltedPacket(channelId, saltA, tokenA.order())
	packetB := saltedPacket(channelId, saltB, tokenB.order())
	ufmt.Printf("[INFO] same salt yields equal packet commitment: %t\n", commit(packetA) == commit(packetA2))
	ufmt.Printf("[INFO] different salt yields distinct packet commitment: %t\n", commit(packetA) != commit(packetB))
	ufmt.Println("[EXPECTED] both derivation and commitment should be deterministic in the salt")
	return saltA, saltB
}

func dedupSameSalt(cur realm, channelId types.ChannelId, t token, salt [32]byte) {
	packet := saltedPacket(channelId, salt, t.order())

	testing.SetRealm(testing.NewUserRealm(adminAddr))
	core.PacketRecv(cross(cur), core.NewMsgPacketRecv([]types.Packet{packet}, [][]byte{nil}, nil, 1))
	first := zkgm.VoucherBalanceOf(t.quoteToken, receiverAddr)

	testing.SetRealm(testing.NewUserRealm(adminAddr))
	core.PacketRecv(cross(cur), core.NewMsgPacketRecv([]types.Packet{packet}, [][]byte{nil}, nil, 1))
	second := zkgm.VoucherBalanceOf(t.quoteToken, receiverAddr)

	ufmt.Printf("[INFO] receiver balance after first recv: %d (receipt: %t)\n", first, receiptRecorded(packet))
	ufmt.Printf("[INFO] receiver balance after duplicate recv: %d\n", second)
	ufmt.Println("[EXPECTED] first recv mints 10; the duplicate is swallowed (balance stays 10)")
}

func distinctSalt(cur realm, channelId types.ChannelId, t token, salt [32]byte) {
	packet := saltedPacket(channelId, salt, t.order())

	testing.SetRealm(testing.NewUserRealm(adminAddr))
	core.PacketRecv(cross(cur), core.NewMsgPacketRecv([]types.Packet{packet}, [][]byte{nil}, nil, 1))

	ufmt.Printf("[INFO] distinct-salt packet receipt recorded: %t\n", receiptRecorded(packet))
	ufmt.Printf("[INFO] receiver balance of the other token: %d\n", zkgm.VoucherBalanceOf(t.quoteToken, receiverAddr))
	ufmt.Println("[EXPECTED] the different-salt packet mints its own token (10), independently")
}

func receiptRecorded(packet types.Packet) bool {
	_, err := core.GetBatchReceipts(core.CommitPacketsHash([]types.Packet{packet}))
	return err == nil
}

// --- encoding helpers ---

func saltedPacket(channelId types.ChannelId, salt [32]byte, order z.TokenOrderV2) types.Packet {
	data, err := z.EncodeZkgmPacket(z.ZkgmPacket{Salt: salt, Path: u256.Zero(), Instruction: mustOrderInstruction(order)})
	if err != nil {
		panic(err)
	}
	return core.NewPacket(types.ChannelId(2), channelId, data, types.Timestamp(1<<62))
}

func commit(packet types.Packet) types.H256 {
	return types.MustCommit(types.CommitPacket(packet))
}

func mustOrderInstruction(order z.TokenOrderV2) z.Instruction {
	operand, err := z.EncodeTokenOrderV2(order)
	if err != nil {
		panic(err)
	}
	return z.Instruction{Version: z.INSTR_VERSION_2, Opcode: z.OP_TOKEN_ORDER, Operand: operand}
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
// [SCENARIO] 2. Salt derivation and packet commitment are deterministic
// [INFO] same sender+salt derives equal salt: true
// [INFO] different salt derives distinct salt: true
// [INFO] same salt yields equal packet commitment: true
// [INFO] different salt yields distinct packet commitment: true
// [EXPECTED] both derivation and commitment should be deterministic in the salt
//
// [SCENARIO] 3. A repeated packet (same salt) is swallowed by the receipt guard
// [INFO] receiver balance after first recv: 10 (receipt: true)
// [INFO] receiver balance after duplicate recv: 10
// [EXPECTED] first recv mints 10; the duplicate is swallowed (balance stays 10)
//
// [SCENARIO] 4. A different-salt packet is a distinct packet, processed independently
// [INFO] distinct-salt packet receipt recorded: true
// [INFO] receiver balance of the other token: 10
// [EXPECTED] the different-salt packet mints its own token (10), independently
