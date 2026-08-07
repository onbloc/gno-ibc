// PKGPATH: gno.land/r/onbloc/ibc/scenario/union/ratelimit
package ratelimit

// recv_ratelimit_unconfigured_denom_rejected_filetest is the FAIL-CLOSED
// counterpart to recv_ratelimit_capacity_filetest: rate limiting is enabled
// (store.gno defaults rateLimitDisabled to true, so this must explicitly
// disable-the-disable) and the quote denom has no configured token bucket at
// all — not exceeded, not present. rateLimit (rate_limit.gno)
// treats an absent bucket as errTokenBucketAbsent, not as unlimited passage,
// so even a first-ever INITIALIZE deploy is rejected with a graceful failure
// ack before protocolFillMint ever runs: no voucher is deployed, nothing is
// minted, and the recv still commits a receipt (no panic).

import (
	"chain"
	"encoding/hex"
	"testing"

	"gno.land/p/nt/ufmt/v0"
	types "gno.land/p/onbloc/ibc/union/types"
	z "gno.land/p/onbloc/ibc/union/zkgm"

	u256 "gno.land/p/onbloc/math/uint256"

	"gno.land/r/demo/defi/grc20reg"
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
	receiverAddr = address("g1wymu47drhr0kuq2098m792lytgtj2nyx77yrsm")
)

func main(cur realm) {
	println("[SCENARIO] 1. Bootstrap IBC host and open a zkgm channel (rate limiting explicitly enabled)")
	channelId := bootstrap(cur)
	println("")

	println("[SCENARIO] 2. Receive an INITIALIZE order whose quote denom has no configured token bucket: rejected fail-closed")
	attemptInitializeWithoutBucket(cur, channelId)
}

func bootstrap(cur realm) types.ChannelId {
	testing.SetRealm(testing.NewUserRealm(adminAddr))
	core.UpdateImpl(cross(cur), coreImplPath)
	zkgm.UpdateImpl(cross(cur), zkgmImplPath)
	zkgm.SetRateLimitDisabled(cross(cur), false) // rate limiting is disabled by default; enable it explicitly
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

// attemptInitializeWithoutBucket receives a fresh INITIALIZE TokenOrder for a
// denom that has never had a token bucket configured. baseCovers is true
// (BaseAmount == QuoteAmount), so executeTokenOrderV2 reaches the
// protocol-fill branch's rateLimit check before protocolFillMint — and since
// rate limiting was never disabled and no bucket exists, it fails closed.
func attemptInitializeWithoutBucket(cur realm, channelId types.ChannelId) {
	meta := mustTokenMetadata("af739f34ddf951cbc24fdbba4f76213688e13627", z.TokenInitializer{Name: "Gno Token", Symbol: "GNOT", Decimals: 6})
	quoteToken := z.PredictWrappedTokenV2(u256.Zero(), uint32(channelId), []byte("ugnot"), z.MetadataImage(mustDecodeMeta(meta)))

	order := z.TokenOrderV2{
		Sender:      []byte("remote-sender"),
		Receiver:    []byte(receiverAddr.String()),
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

	deployed := grc20reg.Get(zkgm.ProxyPkgPath() + ".GNOT")
	channelBalance, channelBalanceErr := zkgm.GetChannelBalanceV2(channelId, u256.Zero(), "ugnot", []byte(quoteToken))

	ufmt.Printf("[INFO] receiver voucher balance: %d\n", zkgm.VoucherBalanceOf(quoteToken, receiverAddr))
	ufmt.Printf("[INFO] wrapped token deployed (grc20reg entry exists): %t\n", deployed != nil)
	ufmt.Printf("[INFO] packet receipt recorded: %t\n", receiptRecorded(packet))
	ufmt.Printf("[INFO] channel balance ledger untouched (not found): %t\n", channelBalanceErr != nil)
	_ = channelBalance
	ufmt.Println("[EXPECTED] receiver voucher balance should be 0 (no mint: rejected before protocolFillMint)")
	ufmt.Println("[EXPECTED] wrapped token deployed should be false (fail-closed, not fail-open)")
	ufmt.Println("[EXPECTED] packet receipt recorded should be true (graceful failure ack, no panic)")
	ufmt.Println("[EXPECTED] channel balance ledger untouched should be true (nothing was ever accounted for)")
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
// [SCENARIO] 1. Bootstrap IBC host and open a zkgm channel (rate limiting explicitly enabled)
//
// [SCENARIO] 2. Receive an INITIALIZE order whose quote denom has no configured token bucket: rejected fail-closed
// [INFO] receiver voucher balance: 0
// [INFO] wrapped token deployed (grc20reg entry exists): false
// [INFO] packet receipt recorded: true
// [INFO] channel balance ledger untouched (not found): true
// [EXPECTED] receiver voucher balance should be 0 (no mint: rejected before protocolFillMint)
// [EXPECTED] wrapped token deployed should be false (fail-closed, not fail-open)
// [EXPECTED] packet receipt recorded should be true (graceful failure ack, no panic)
// [EXPECTED] channel balance ledger untouched should be true (nothing was ever accounted for)
