// PKGPATH: gno.land/r/onbloc/ibc/scenario/union/settlement
package settlement

// fee_distribution_on_recv_filetest is the NORMAL-path settlement scenario for the
// relayer fee split on receive (re-targeted from the legacy e2e zs22, voucher
// half). When a received TokenOrder's QuoteAmount is less than its BaseAmount, the
// receiver is minted the QuoteAmount and the relayer (the PacketRecv caller) is
// minted the difference as its fee. Both sides of the split are verified as balance
// diffs. (The legacy native-unescrow fee half depends on the send/native escrow
// path and is covered separately.)

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

	// adminAddr is the bootstrap admin and the relayer that drives PacketRecv, so it
	// is the fee recipient for the split below.
	adminAddr    = address("g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5")
	receiverAddr = address("g1wymu47drhr0kuq2098m792lytgtj2nyx77yrsm")
)

func main(cur realm) {
	println("[SCENARIO] 1. Bootstrap IBC host and open a zkgm channel")
	channelId := bootstrap(cur)
	println("")

	meta := mustTokenMetadata("\xaf\x73\x9f\x34\xdd\xf9\x51\xcb\xc2\x4f\xdb\xba\x4f\x76\x21\x36\x88\xe1\x36\x27", z.TokenInitializer{Name: "Fee Token", Symbol: "FEE", Decimals: 6})
	quoteToken := z.PredictWrappedTokenV2(u256.Zero(), uint32(channelId), []byte("ufee"), z.MetadataImage(mustDecodeMeta(meta)))

	println("[SCENARIO] 2. Receive an order with QuoteAmount < BaseAmount: receiver gets the quote, relayer keeps the fee")
	receiveWithFee(cur, channelId, quoteToken, meta)
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

func receiveWithFee(cur realm, channelId types.ChannelId, quoteToken string, meta []byte) {
	order := z.TokenOrderV2{
		Sender:      []byte("remote-sender"),
		Receiver:    []byte(receiverAddr.String()),
		BaseToken:   []byte("ufee"),
		BaseAmount:  u256.NewUint(100),
		QuoteToken:  []byte(quoteToken),
		QuoteAmount: u256.NewUint(88),
		Kind:        z.TOKEN_ORDER_KIND_INITIALIZE,
		Metadata:    meta,
	}
	packet := core.NewPacket(types.ChannelId(2), channelId, mustPacketData(mustOrderInstruction(order)), types.Timestamp(1<<62))

	recvBefore := zkgm.VoucherBalanceOf(quoteToken, receiverAddr)
	feeBefore := zkgm.VoucherBalanceOf(quoteToken, adminAddr)

	testing.SetRealm(testing.NewUserRealm(adminAddr)) // admin is the relayer / fee recipient
	core.PacketRecv(cross(cur), core.NewMsgPacketRecv([]types.Packet{packet}, [][]byte{nil}, nil, 1))

	recvAfter := zkgm.VoucherBalanceOf(quoteToken, receiverAddr)
	feeAfter := zkgm.VoucherBalanceOf(quoteToken, adminAddr)

	ufmt.Printf("[INFO] receiver voucher balance: %d -> %d (delta +%d)\n", recvBefore, recvAfter, recvAfter-recvBefore)
	ufmt.Printf("[INFO] relayer fee voucher balance: %d -> %d (delta +%d)\n", feeBefore, feeAfter, feeAfter-feeBefore)
	ufmt.Println("[EXPECTED] receiver should get 88 (quote) and the relayer should keep 12 (base - quote)")
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
// [SCENARIO] 2. Receive an order with QuoteAmount < BaseAmount: receiver gets the quote, relayer keeps the fee
// [INFO] receiver voucher balance: 0 -> 88 (delta +88)
// [INFO] relayer fee voucher balance: 0 -> 12 (delta +12)
// [EXPECTED] receiver should get 88 (quote) and the relayer should keep 12 (base - quote)
