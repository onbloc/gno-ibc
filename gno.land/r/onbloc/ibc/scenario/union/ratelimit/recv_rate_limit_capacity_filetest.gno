// PKGPATH: gno.land/r/onbloc/ibc/scenario/union/ratelimit
package ratelimit

// recv_rate_limit_capacity_filetest is the BY-TYPE rate-limit scenario. With
// rate limiting enabled, the receive/fill of a quote denom is charged against that
// denom's token bucket: a fill within the remaining capacity mints, a fill that
// exceeds it is rejected (failure ack — nothing minted), and after the bucket refills
// over time (testing.SkipHeights, 5s per block, refillRate tokens/second) a fill
// succeeds again. (In the current model the rate limit is on the quote/fill side, not
// the send side; an unconfigured bucket while enabled would reject the fill outright.)

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

var theMeta []byte

func main(cur realm) {
	println("[SCENARIO] 1. Bootstrap, deploy the token, then enable a capacity-50 bucket (refill 50/s)")
	channelId, quoteToken := setup(cur)
	ufmt.Printf("[INFO] bucket available after config: %d\n", available(quoteToken))
	ufmt.Printf("[INFO] other bucket available after config: %d\n", available("other-denom"))
	println("")

	println("[SCENARIO] 2. A fill of 40 is within capacity -> minted")
	recvFill(cur, channelId, quoteToken, 40, [32]byte{2})
	println("")

	println("[SCENARIO] 3. A second fill of 40 exceeds the remaining capacity -> rejected (no mint)")
	recvFill(cur, channelId, quoteToken, 40, [32]byte{3})
	println("")

	println("[SCENARIO] 4. After the bucket refills (SkipHeights), a fill of 40 succeeds again")
	testing.SkipHeights(1) // 5s * 50/s refills the bucket to capacity
	recvFill(cur, channelId, quoteToken, 40, [32]byte{4})
	println("")

	println("[SCENARIO] 5. A configured bucket for another denom is isolated from quote fills")
	ufmt.Printf("[INFO] other bucket available after quote fills: %d\n", available("other-denom"))
	println("")

	println("[SCENARIO] 6. With rate limiting enabled, an unconfigured quote denom is rejected")
	recvInitialize(cur, channelId, "unope", "Nope Token", "NOPE", 10, [32]byte{5})
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

	theMeta = mustTokenMetadata("grc20", z.TokenInitializer{Name: "Gno Token", Symbol: "GNOT", Decimals: 6})
	quoteToken := z.PredictWrappedTokenV2(u256.Zero(), uint32(channelId), []byte("ugnot"), z.MetadataImage(mustDecodeMeta(theMeta)))

	// Deploy the wrapped token with a small INITIALIZE (rate limit still disabled).
	deploy := orderOf(z.TOKEN_ORDER_KIND_INITIALIZE, quoteToken, 1)
	core.PacketRecv(cross(cur), core.NewMsgPacketRecv([]types.Packet{saltedPacket(channelId, [32]byte{1}, deploy)}, [][]byte{nil}, nil, 1))

	// Enable rate limiting and configure the bucket for the quote denom.
	zkgm.SetRateLimitDisabled(cross(cur), false)
	zkgm.SetBucketConfig(cross(cur), quoteToken, u256.NewUint(50), u256.NewUint(50))
	zkgm.SetBucketConfig(cross(cur), "other-denom", u256.NewUint(77), u256.NewUint(1))
	return channelId, quoteToken
}

func recvFill(cur realm, channelId types.ChannelId, quoteToken string, amount int64, salt [32]byte) {
	before := zkgm.VoucherBalanceOf(quoteToken, receiverAddr)

	testing.SetRealm(testing.NewUserRealm(adminAddr))
	core.PacketRecv(cross(cur), core.NewMsgPacketRecv([]types.Packet{saltedPacket(channelId, salt, orderOf(z.TOKEN_ORDER_KIND_ESCROW, quoteToken, amount))}, [][]byte{nil}, nil, 1))

	after := zkgm.VoucherBalanceOf(quoteToken, receiverAddr)
	ufmt.Printf("[INFO] fill of %d: balance %d -> %d (delta +%d), bucket available %d\n", amount, before, after, after-before, available(quoteToken))
}

func recvInitialize(cur realm, channelId types.ChannelId, baseToken string, name string, symbol string, amount int64, salt [32]byte) {
	meta := mustTokenMetadata("grc20", z.TokenInitializer{Name: name, Symbol: symbol, Decimals: 6})
	quoteToken := z.PredictWrappedTokenV2(u256.Zero(), uint32(channelId), []byte(baseToken), z.MetadataImage(mustDecodeMeta(meta)))
	before := zkgm.VoucherBalanceOf(quoteToken, receiverAddr)
	packet := saltedPacket(channelId, salt, z.TokenOrderV2{
		Sender:      []byte("remote-sender"),
		Receiver:    []byte(receiverAddr.String()),
		BaseToken:   []byte(baseToken),
		BaseAmount:  u256.NewUint(uint64(amount)),
		QuoteToken:  []byte(quoteToken),
		QuoteAmount: u256.NewUint(uint64(amount)),
		Kind:        z.TOKEN_ORDER_KIND_INITIALIZE,
		Metadata:    meta,
	})

	testing.SetRealm(testing.NewUserRealm(adminAddr))
	core.PacketRecv(cross(cur), core.NewMsgPacketRecv([]types.Packet{packet}, [][]byte{nil}, nil, 1))

	after := zkgm.VoucherBalanceOf(quoteToken, receiverAddr)
	ufmt.Printf("[INFO] unconfigured initialize: balance %d -> %d (delta +%d)\n", before, after, after-before)
	ufmt.Printf("[INFO] unconfigured failure ack committed: %t\n", ackCommitted(packet, universalErrorAck()))
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

func ackCommitted(packet types.Packet, ack []byte) bool {
	batchHash := core.CommitPacketsHash([]types.Packet{packet})
	got, _ := core.GetBatchReceipts(batchHash)
	want := types.CommitAck(ack)
	return got == want
}

// --- encoding helpers ---

func mustOrderInstruction(order z.TokenOrderV2) z.Instruction {
	operand, err := z.EncodeTokenOrderV2(order)
	if err != nil {
		panic(err)
	}
	return z.Instruction{Version: z.INSTR_VERSION_2, Opcode: z.OP_TOKEN_ORDER, Operand: operand}
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

func universalErrorAck() []byte {
	ack, err := z.EncodeAck(z.Ack{Tag: u256.NewUint(0), InnerAck: []byte{}})
	if err != nil {
		panic(err)
	}
	return ack
}

// Output:
// [SCENARIO] 1. Bootstrap, deploy the token, then enable a capacity-50 bucket (refill 50/s)
// [INFO] bucket available after config: 50
// [INFO] other bucket available after config: 77
//
// [SCENARIO] 2. A fill of 40 is within capacity -> minted
// [INFO] fill of 40: balance 1 -> 41 (delta +40), bucket available 10
//
// [SCENARIO] 3. A second fill of 40 exceeds the remaining capacity -> rejected (no mint)
// [INFO] fill of 40: balance 41 -> 41 (delta +0), bucket available 10
//
// [SCENARIO] 4. After the bucket refills (SkipHeights), a fill of 40 succeeds again
// [INFO] fill of 40: balance 41 -> 81 (delta +40), bucket available 10
//
// [SCENARIO] 5. A configured bucket for another denom is isolated from quote fills
// [INFO] other bucket available after quote fills: 77
//
// [SCENARIO] 6. With rate limiting enabled, an unconfigured quote denom is rejected
// [INFO] unconfigured initialize: balance 0 -> 0 (delta +0)
// [INFO] unconfigured failure ack committed: true
