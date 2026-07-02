// PKGPATH: gno.land/r/onbloc/ibc/scenario/union/decimals
package decimals

// recv_18dec_scale_down_filetest is the BY-TYPE scenario for 18-decimal amount
// scaling (re-targeted from the legacy e2e zs25). An 18-decimal token (1e18 wei)
// is received via an INITIALIZE order and minted as the 6-decimal local amount.
// An UNESCROW send then submits the 18-decimal wire amount and burns the
// corresponding 6-decimal local voucher amount.

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

	adminAddr  = address("g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5")
	holderAddr = address("g1wymu47drhr0kuq2098m792lytgtj2nyx77yrsm")

	// weiAmount is 1e18 — a full 18-decimal unit. It fits in uint64.
	weiAmount = uint64(1000000000000000000)
	localAmount = uint64(1000000)
)

func main(cur realm) {
	println("[SCENARIO] 1. Bootstrap IBC host and open a zkgm channel")
	channelId := bootstrap(cur)
	println("")

	meta := mustTokenMetadata("grc20", z.TokenInitializer{Name: "Ether Token", Symbol: "ETH", Decimals: 18})
	quoteToken := z.PredictWrappedTokenV2(u256.Zero(), uint32(channelId), []byte("wei"), z.MetadataImage(mustDecodeMeta(meta)))

	println("[SCENARIO] 2. Receive an 18-dec INITIALIZE order: scaled down to 6-dec local amount")
	recvInitialize(cur, channelId, quoteToken, meta)
	println("")

	println("[SCENARIO] 3. UNESCROW send with 1e18 wire amount burns the local 1e6 amount")
	unescrowSend(cur, channelId, quoteToken)
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

func recvInitialize(cur realm, channelId types.ChannelId, quoteToken string, meta []byte) {
	order := z.TokenOrderV2{
		Sender:      []byte("remote-sender"),
		Receiver:    []byte(holderAddr.String()),
		BaseToken:   []byte("wei"),
		BaseAmount:  u256.NewUint(weiAmount),
		QuoteToken:  []byte(quoteToken),
		QuoteAmount: u256.NewUint(weiAmount),
		Kind:        z.TOKEN_ORDER_KIND_INITIALIZE,
		Metadata:    meta,
	}
	packet := core.NewPacket(types.ChannelId(2), channelId, mustPacketData(mustOrderInstruction(order)), types.Timestamp(1<<62))

	before := zkgm.VoucherBalanceOf(quoteToken, holderAddr)

	testing.SetRealm(testing.NewUserRealm(adminAddr))
	core.PacketRecv(cross(cur), core.NewMsgPacketRecv([]types.Packet{packet}, [][]byte{nil}, nil, 1))

	after := zkgm.VoucherBalanceOf(quoteToken, holderAddr)
	ufmt.Printf("[INFO] holder voucher balance: %d -> %d\n", before, after)
	ufmt.Println("[EXPECTED] minted balance should equal 1000000 (1e6 local, scaled down from 1e18 wire)")
}

func unescrowSend(cur realm, channelId types.ChannelId, quoteToken string) {
	order := z.TokenOrderV2{
		Sender:      []byte(holderAddr.String()),
		Receiver:    []byte("remote-receiver"),
		BaseToken:   []byte(quoteToken),
		BaseAmount:  u256.NewUint(weiAmount),
		QuoteToken:  []byte("wei"),
		QuoteAmount: u256.NewUint(weiAmount),
		Kind:        z.TOKEN_ORDER_KIND_UNESCROW,
	}

	before := zkgm.VoucherBalanceOf(quoteToken, holderAddr)

	testing.SetRealm(testing.NewUserRealm(holderAddr))
	_ = zkgm.Send(cross(cur), channelId, types.Timestamp(1<<62), [32]byte{}, mustOrderInstruction(order))

	after := zkgm.VoucherBalanceOf(quoteToken, holderAddr)
	ufmt.Printf("[INFO] holder voucher balance: %d -> %d\n", before, after)
	ufmt.Println("[EXPECTED] UNESCROW send should burn the local 1e6 amount, leaving 0")
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
// [SCENARIO] 2. Receive an 18-dec INITIALIZE order: scaled down to 6-dec local amount
// [INFO] holder voucher balance: 0 -> 1000000
// [EXPECTED] minted balance should equal 1000000 (1e6 local, scaled down from 1e18 wire)
//
// [SCENARIO] 3. UNESCROW send with 1e18 wire amount burns the local 1e6 amount
// [INFO] holder voucher balance: 1000000 -> 0
// [EXPECTED] UNESCROW send should burn the local 1e6 amount, leaving 0
