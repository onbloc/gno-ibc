// PKGPATH: gno.land/r/onbloc/ibc/scenario/union/ratelimit
package ratelimit

// recv_ratelimit_marketmaker_fill_bypass_filetest proves that a
// market-maker fill is NOT subject to the token bucket. rateLimit is only
// called from executeTokenOrderV2's two protocol-fill sites (token_order.gno);
// marketMakerFillV2 never calls it. This file drains a bucket to zero via
// protocol-fill recvs, confirms a further protocol-fill is rejected by the
// exhausted bucket, then shows an under-quoted order — which falls back to
// marketMakerFillV2 — still succeeds by fronting from the maker's own voucher
// balance, entirely independent of the bucket's exhausted state.

import (
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
	makerAddr    = address("g1dyxy88p94acjnm8dmu9tfj2mv2ncvx83cagllu")
	receiverAddr = address("g1wymu47drhr0kuq2098m792lytgtj2nyx77yrsm")
)

func main(cur realm) {
	println("[SCENARIO] 1. Bootstrap IBC host and open a zkgm channel")
	channelId := bootstrap(cur)
	println("")

	meta := mustTokenMetadata("grc20", z.TokenInitializer{Name: "Gno Token", Symbol: "GNOT", Decimals: 6})
	quoteToken := z.PredictWrappedTokenV2(u256.Zero(), uint32(channelId), []byte("ugnot"), z.MetadataImage(mustDecodeMeta(meta)))

	println("[SCENARIO] 2. Fund the maker with 100 of the voucher via a protocol-fill INITIALIZE recv")
	fundMaker(cur, channelId, quoteToken, meta)
	println("")

	println("[SCENARIO] 3. Enable rate limiting with a capacity-50 bucket for the quote denom")
	enableRateLimit(cur, quoteToken)
	println("")

	println("[SCENARIO] 4. Drain the bucket with a protocol-fill ESCROW recv of 50: mints, bucket exhausted")
	drainBucketWithProtocolFill(cur, channelId, quoteToken)
	println("")

	println("[SCENARIO] 5. A further protocol-fill recv is rate limited: no mint, bucket stays at 0")
	attemptProtocolFillOverExhaustedBucket(cur, channelId, quoteToken)
	println("")

	println("[SCENARIO] 6. An under-quoted order falls back to a market-maker fill: succeeds despite the exhausted bucket")
	receiveUnderQuotedEscrowAsMaker(cur, channelId, quoteToken)
}

func bootstrap(cur realm) types.ChannelId {
	testing.SetRealm(testing.NewUserRealm(adminAddr))
	core.UpdateImpl(cross(cur), coreImplPath)
	zkgm.UpdateImpl(cross(cur), zkgmImplPath)
	zkgm.SetRateLimitDisabled(cross(cur), true) // disabled while deploying and funding
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

// fundMaker mints 100 of the wrapped voucher to the maker via a normal
// protocol-fill INITIALIZE recv (rate limiting still disabled), so the maker
// has a real balance to front from in step 6.
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

	ufmt.Printf("[INFO] maker voucher balance: %d\n", zkgm.VoucherBalanceOf(quoteToken, makerAddr))
	ufmt.Println("[EXPECTED] maker voucher balance should be 100")
}

// enableRateLimit turns rate limiting on and configures a capacity-50 bucket
// for the quote denom. No block time is skipped between the recvs below, so
// the (minimal, non-zero) refill rate never kicks in.
func enableRateLimit(cur realm, quoteToken string) {
	testing.SetRealm(testing.NewUserRealm(adminAddr))
	zkgm.SetRateLimitDisabled(cross(cur), false)
	zkgm.SetBucketConfig(cross(cur), quoteToken, u256.NewUint(50), u256.NewUint(1))

	ufmt.Printf("[INFO] bucket available: %d\n", available(quoteToken))
	ufmt.Println("[EXPECTED] bucket available should be 50 (capacity)")
}

// drainBucketWithProtocolFill receives a fully-quoted ESCROW order (Base ==
// Quote, so executeTokenOrderV2 protocol-fills it). The protocol-fill path
// calls rateLimit, charging the bucket down to 0.
func drainBucketWithProtocolFill(cur realm, channelId types.ChannelId, quoteToken string) {
	order := z.TokenOrderV2{
		Sender:      []byte("remote-sender"),
		Receiver:    []byte(receiverAddr.String()),
		BaseToken:   []byte("ugnot"),
		BaseAmount:  u256.NewUint(50),
		QuoteToken:  []byte(quoteToken),
		QuoteAmount: u256.NewUint(50),
		Kind:        z.TOKEN_ORDER_KIND_ESCROW,
	}
	packet := core.NewPacket(types.ChannelId(2), channelId, mustPacketData(mustOrderInstruction(order)), types.Timestamp(1<<62))

	testing.SetRealm(testing.NewUserRealm(adminAddr))
	core.PacketRecv(cross(cur), core.NewMsgPacketRecv([]types.Packet{packet}, [][]byte{nil}, nil, 1))

	ufmt.Printf("[INFO] receiver voucher balance: %d\n", zkgm.VoucherBalanceOf(quoteToken, receiverAddr))
	ufmt.Printf("[INFO] bucket available: %d\n", available(quoteToken))
	ufmt.Println("[EXPECTED] receiver voucher balance should be 50 (protocol-minted)")
	ufmt.Println("[EXPECTED] bucket available should be 0 (fully charged)")
}

// attemptProtocolFillOverExhaustedBucket receives another fully-quoted ESCROW
// order while the bucket is exhausted. executeTokenOrderV2 still tries the
// protocol-fill path (Base == Quote), so rateLimit rejects it: no mint, and
// the ack fails, but no panic.
func attemptProtocolFillOverExhaustedBucket(cur realm, channelId types.ChannelId, quoteToken string) {
	order := z.TokenOrderV2{
		Sender:      []byte("remote-sender"),
		Receiver:    []byte(receiverAddr.String()),
		BaseToken:   []byte("ugnot"),
		BaseAmount:  u256.NewUint(5),
		QuoteToken:  []byte(quoteToken),
		QuoteAmount: u256.NewUint(5),
		Kind:        z.TOKEN_ORDER_KIND_ESCROW,
	}
	packet := core.NewPacket(types.ChannelId(2), channelId, mustPacketData(mustOrderInstruction(order)), types.Timestamp(1<<62))

	testing.SetRealm(testing.NewUserRealm(adminAddr))
	core.PacketRecv(cross(cur), core.NewMsgPacketRecv([]types.Packet{packet}, [][]byte{nil}, nil, 1))

	ufmt.Printf("[INFO] receiver voucher balance: %d\n", zkgm.VoucherBalanceOf(quoteToken, receiverAddr))
	ufmt.Printf("[INFO] bucket available: %d\n", available(quoteToken))
	ufmt.Println("[EXPECTED] receiver voucher balance should still be 50 (rate limited: no mint)")
	ufmt.Println("[EXPECTED] bucket available should still be 0 (unchanged)")
}

// receiveUnderQuotedEscrowAsMaker receives an ESCROW order whose BaseAmount
// (5) is less than its QuoteAmount (20). executeTokenOrderV2 cannot
// protocol-fill an under-quoted order, so it falls back to marketMakerFillV2,
// which never calls rateLimit — the maker (who submits this recv itself,
// making it the relayer) fronts the 20-unit quote to the receiver from its
// own voucher balance, regardless of the bucket's exhausted state.
func receiveUnderQuotedEscrowAsMaker(cur realm, channelId types.ChannelId, quoteToken string) {
	order := z.TokenOrderV2{
		Sender:      []byte("remote-sender"),
		Receiver:    []byte(receiverAddr.String()),
		BaseToken:   []byte("ugnot"),
		BaseAmount:  u256.NewUint(5),
		QuoteToken:  []byte(quoteToken),
		QuoteAmount: u256.NewUint(20),
		Kind:        z.TOKEN_ORDER_KIND_ESCROW,
	}
	packet := core.NewPacket(types.ChannelId(2), channelId, mustPacketData(mustOrderInstruction(order)), types.Timestamp(1<<62))

	testing.SetRealm(testing.NewUserRealm(makerAddr))
	core.PacketRecv(cross(cur), core.NewMsgPacketRecv([]types.Packet{packet}, [][]byte{nil}, nil, 1))

	ufmt.Printf("[INFO] maker voucher balance: %d\n", zkgm.VoucherBalanceOf(quoteToken, makerAddr))
	ufmt.Printf("[INFO] receiver voucher balance: %d\n", zkgm.VoucherBalanceOf(quoteToken, receiverAddr))
	ufmt.Printf("[INFO] bucket available: %d\n", available(quoteToken))
	ufmt.Println("[EXPECTED] maker voucher balance should be 80 (100 - 20 fronted to the receiver)")
	ufmt.Println("[EXPECTED] receiver voucher balance should be 70 (50 protocol-minted + 20 fronted by the maker)")
	ufmt.Println("[EXPECTED] bucket available should still be 0 (marketMakerFillV2 never calls rateLimit)")
}

func available(denom string) uint64 {
	bucket, err := zkgm.GetTokenBucket(denom)
	if err != nil {
		panic(err)
	}
	return bucket.Available.Uint64()
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
// [SCENARIO] 2. Fund the maker with 100 of the voucher via a protocol-fill INITIALIZE recv
// [INFO] maker voucher balance: 100
// [EXPECTED] maker voucher balance should be 100
//
// [SCENARIO] 3. Enable rate limiting with a capacity-50 bucket for the quote denom
// [INFO] bucket available: 50
// [EXPECTED] bucket available should be 50 (capacity)
//
// [SCENARIO] 4. Drain the bucket with a protocol-fill ESCROW recv of 50: mints, bucket exhausted
// [INFO] receiver voucher balance: 50
// [INFO] bucket available: 0
// [EXPECTED] receiver voucher balance should be 50 (protocol-minted)
// [EXPECTED] bucket available should be 0 (fully charged)
//
// [SCENARIO] 5. A further protocol-fill recv is rate limited: no mint, bucket stays at 0
// [INFO] receiver voucher balance: 50
// [INFO] bucket available: 0
// [EXPECTED] receiver voucher balance should still be 50 (rate limited: no mint)
// [EXPECTED] bucket available should still be 0 (unchanged)
//
// [SCENARIO] 6. An under-quoted order falls back to a market-maker fill: succeeds despite the exhausted bucket
// [INFO] maker voucher balance: 80
// [INFO] receiver voucher balance: 70
// [INFO] bucket available: 0
// [EXPECTED] maker voucher balance should be 80 (100 - 20 fronted to the receiver)
// [EXPECTED] receiver voucher balance should be 70 (50 protocol-minted + 20 fronted by the maker)
// [EXPECTED] bucket available should still be 0 (marketMakerFillV2 never calls rateLimit)
