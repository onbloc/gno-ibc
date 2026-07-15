// PKGPATH: gno.land/r/onbloc/ibc/scenario/union/ratelimit
package ratelimit

// bucket_ratelimit_available_and_exceeded_filetest verifies the token bucket through the
// real execution path. The rate limiter is not poked directly: each receive runs
// executeTokenOrderV2, which calls the impl's rateLimit(quoteDenom, QuoteAmount) and so
// charges the configured bucket. The effect is then observed by querying the bucket back
// with zkgm.GetTokenBucket(denom) and reading Available:
//   - a fill within capacity mints and Available drops by the filled amount,
//   - a fill that exceeds the remaining Available is rejected (failure ack, nothing
//     minted) and Available is left unchanged — the ErrRateLimitExceeded outcome,
//   - after the chain clock advances (testing.SkipHeights, 5s per block) the bucket
//     refills (refillRate/second, capped at capacity) and the next fill succeeds.
//
// The bucket is capacity 100, refill 10/s. Refill is lazy — GetTokenBucket reads the
// stored bucket, which only catches up when the next rateLimit call runs during a recv.

import (
	"encoding/hex"
	"chain"
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
	receiverAddr = address("g1wymu47drhr0kuq2098m792lytgtj2nyx77yrsm")
)

var theMeta []byte

func main(cur realm) {
	println("[SCENARIO] 1. Bootstrap, deploy the token, enable a capacity-100 refill-10/s bucket")
	channelId, quoteToken := setup(cur)
	ufmt.Printf("[INFO] bucket available after config: %d\n", available(quoteToken))
	ufmt.Println("[EXPECTED] 100")
	println("")

	println("[SCENARIO] 2. recv fill 40 (executeTokenOrderV2): minted, bucket charged via rateLimit")
	recvFill(cur, channelId, quoteToken, 40, [32]byte{2})
	println("")

	println("[SCENARIO] 3. recv fill 40 again (same block): minted, bucket charged")
	recvFill(cur, channelId, quoteToken, 40, [32]byte{3})
	println("")

	println("[SCENARIO] 4. recv fill 40 over the remaining 20: rate limited -> no mint, bucket unchanged")
	recvFill(cur, channelId, quoteToken, 40, [32]byte{4})
	println("")

	println("[SCENARIO] 5. Advance the chain 10s, recv fill 40: bucket refilled to capacity, fill succeeds")
	testing.SkipHeights(2) // 2 blocks * 5s = 10s; rateLimit refills 10/s * 10s = 100 (capped at 100)
	recvFill(cur, channelId, quoteToken, 40, [32]byte{5})
}

func setup(cur realm) (types.ChannelId, string) {
	testing.SetRealm(testing.NewUserRealm(adminAddr))
	core.UpdateImpl(cross(cur), coreImplPath)
	zkgm.UpdateImpl(cross(cur), zkgmImplPath)
	zkgm.SetRateLimitDisabled(cross(cur), true) // disabled while deploying the token
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

	theMeta = mustTokenMetadata("af739f34ddf951cbc24fdbba4f76213688e13627", z.TokenInitializer{Name: "Gno Token", Symbol: "GNOT", Decimals: 6})
	quoteToken := z.PredictWrappedTokenV2(u256.Zero(), uint32(channelId), []byte("ugnot"), z.MetadataImage(mustDecodeMeta(theMeta)))

	// Deploy the wrapped token with a small INITIALIZE (rate limit still disabled).
	deploy := orderOf(z.TOKEN_ORDER_KIND_INITIALIZE, quoteToken, 1)
	core.PacketRecv(cross(cur), core.NewMsgPacketRecv([]types.Packet{saltedPacket(channelId, [32]byte{1}, deploy)}, [][]byte{nil}, nil, 1))

	// Enable rate limiting and configure the bucket for the quote denom.
	zkgm.SetRateLimitDisabled(cross(cur), false)
	zkgm.SetBucketConfig(cross(cur), quoteToken, u256.NewUint(100), u256.NewUint(10))
	return channelId, quoteToken
}

// recvFill receives an ESCROW fill of the quote denom through the core/app recv path
// (executeTokenOrderV2 -> rateLimit) and reports the minted delta and the bucket's
// Available read back via zkgm.GetTokenBucket before and after.
func recvFill(cur realm, channelId types.ChannelId, quoteToken string, amount int64, salt [32]byte) {
	balBefore := zkgm.VoucherBalanceOf(quoteToken, receiverAddr)
	availBefore := available(quoteToken)

	testing.SetRealm(testing.NewUserRealm(adminAddr))
	core.PacketRecv(cross(cur), core.NewMsgPacketRecv([]types.Packet{saltedPacket(channelId, salt, orderOf(z.TOKEN_ORDER_KIND_ESCROW, quoteToken, amount))}, [][]byte{nil}, nil, 1))

	balAfter := zkgm.VoucherBalanceOf(quoteToken, receiverAddr)
	availAfter := available(quoteToken)
	ufmt.Printf("[INFO] fill %d: minted +%d, bucket available %d -> %d\n", amount, balAfter-balBefore, availBefore, availAfter)
}

func available(denom string) uint64 {
	bucket, err := zkgm.GetTokenBucket(denom)
	if err != nil {
		panic(err)
	}
	return bucket.Available.Uint64()
}

func orderOf(kind uint8, quoteToken string, amount int64) z.TokenOrderV2 {
	return z.TokenOrderV2{
		Sender:      []byte("remote-sender"),
		Receiver:    []byte(receiverAddr.String()),
		BaseToken:   []byte("ugnot"),
		BaseAmount:  u256.NewUint(uint64(amount)),
		QuoteToken:  []byte(quoteToken),
		QuoteAmount: u256.NewUint(uint64(amount)),
		Kind:        kind,
		Metadata:    theMeta,
	}
}

func saltedPacket(channelId types.ChannelId, salt [32]byte, order z.TokenOrderV2) types.Packet {
	data, err := z.EncodeZkgmPacket(z.ZkgmPacket{Salt: salt, Path: u256.Zero(), Instruction: mustOrderInstruction(order)})
	if err != nil {
		panic(err)
	}
	return core.NewPacket(types.ChannelId(2), channelId, data, types.Timestamp(1<<62))
}

// --- encoding helpers ---

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
// [SCENARIO] 1. Bootstrap, deploy the token, enable a capacity-100 refill-10/s bucket
// [INFO] bucket available after config: 100
// [EXPECTED] 100
//
// [SCENARIO] 2. recv fill 40 (executeTokenOrderV2): minted, bucket charged via rateLimit
// [INFO] fill 40: minted +40, bucket available 100 -> 60
//
// [SCENARIO] 3. recv fill 40 again (same block): minted, bucket charged
// [INFO] fill 40: minted +40, bucket available 60 -> 20
//
// [SCENARIO] 4. recv fill 40 over the remaining 20: rate limited -> no mint, bucket unchanged
// [INFO] fill 40: minted +0, bucket available 20 -> 20
//
// [SCENARIO] 5. Advance the chain 10s, recv fill 40: bucket refilled to capacity, fill succeeds
// [INFO] fill 40: minted +40, bucket available 20 -> 60
