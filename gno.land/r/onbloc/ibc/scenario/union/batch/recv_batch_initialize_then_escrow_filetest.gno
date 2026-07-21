// PKGPATH: gno.land/r/onbloc/ibc/scenario/union/batch
package batch

// recv_batch_initialize_then_escrow_filetest is the INTRA-BATCH DEPENDENCY
// scenario: child 0 is an INITIALIZE order that deploys a brand-new wrapped
// voucher, and child 1 in the SAME batch/packet is an ESCROW order for that
// same voucher. This is different from the two-packet INITIALIZE-then-ESCROW
// receive files (token_receive_*_escrow_protocol_fill_filetest.gno), which use
// two separate core.PacketRecv calls. Here both children run inside one
// executeBatch loop (batch.gno:34-60), which executes children sequentially
// and commits each child's state before the next runs — so by the time child
// 1's ESCROW branch checks v.store.HasVoucher / GetMetadataImageOf
// (token_order.gno: ESCROW case), child 0's deploy has already registered the
// voucher and its metadata image. The ESCROW child therefore protocol-fills
// (mints more of the just-deployed voucher) instead of being rejected as an
// orphan, all within a single recv transaction.

import (
	"chain"
	"testing"

	"gno.land/p/nt/ufmt/v0"
	types "gno.land/p/onbloc/ibc/union/types"
	z "gno.land/p/onbloc/ibc/union/zkgm"

	u256 "gno.land/p/gnoswap/uint256"

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

	adminAddr     = address("g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5")
	receiverAAddr = address("g1dyxy88p94acjnm8dmu9tfj2mv2ncvx83cagllu")
	receiverBAddr = address("g1wymu47drhr0kuq2098m792lytgtj2nyx77yrsm")
)

func main(cur realm) {
	println("[SCENARIO] 1. Bootstrap IBC host and open a zkgm channel")
	channelId := bootstrap(cur)
	println("")

	println("[SCENARIO] 2. Receive a single batch of [INITIALIZE, ESCROW] for the same token: both mint")
	recvInitializeThenEscrowBatch(cur, channelId)
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

func recvInitializeThenEscrowBatch(cur realm, channelId types.ChannelId) {
	baseToken := "ugnot"
	meta := mustTokenMetadata("grc20", z.TokenInitializer{Name: "Gno Token", Symbol: "GNOT", Decimals: 6})
	quoteToken := z.PredictWrappedTokenV2(u256.Zero(), uint32(channelId), []byte(baseToken), z.MetadataImage(mustDecodeMeta(meta)))

	batch := z.Batch{Instructions: []z.Instruction{
		// child 0: deploys the wrapped voucher and mints 100 to receiver A.
		mustOrderInstruction(z.TokenOrderV2{
			Sender:      []byte("remote-sender"),
			Receiver:    []byte(receiverAAddr.String()),
			BaseToken:   []byte(baseToken),
			BaseAmount:  u256.NewUint(100),
			QuoteToken:  []byte(quoteToken),
			QuoteAmount: u256.NewUint(100),
			Kind:        z.TOKEN_ORDER_KIND_INITIALIZE,
			Metadata:    meta,
		}),
		// child 1: ESCROW for the SAME voucher child 0 just deployed, in the
		// same packet. It must see child 0's committed voucher state to
		// protocol-fill instead of being rejected as an orphan.
		mustOrderInstruction(z.TokenOrderV2{
			Sender:      []byte("remote-sender"),
			Receiver:    []byte(receiverBAddr.String()),
			BaseToken:   []byte(baseToken),
			BaseAmount:  u256.NewUint(50),
			QuoteToken:  []byte(quoteToken),
			QuoteAmount: u256.NewUint(50),
			Kind:        z.TOKEN_ORDER_KIND_ESCROW,
		}),
	}}
	packet := core.NewPacket(types.ChannelId(2), channelId, mustPacketData(mustBatchInstruction(batch)), types.Timestamp(1<<62))

	testing.SetRealm(testing.NewUserRealm(adminAddr))
	core.PacketRecv(cross(cur), core.NewMsgPacketRecv([]types.Packet{packet}, [][]byte{nil}, nil, 1))

	token := grc20reg.MustGet(zkgm.ProxyPkgPath() + "." + quoteToken[len("ibc/"):])
	ufmt.Printf("[INFO] deployed token name/symbol/decimals: %s/%s/%d\n", token.GetName(), token.GetSymbol(), token.GetDecimals())
	ufmt.Printf("[INFO] deployed token total supply: %d\n", token.TotalSupply())
	ufmt.Printf("[INFO] receiver A balance (child 0, INITIALIZE): %d\n", zkgm.VoucherBalanceOf(quoteToken, receiverAAddr))
	ufmt.Printf("[INFO] receiver B balance (child 1, ESCROW): %d\n", zkgm.VoucherBalanceOf(quoteToken, receiverBAddr))
	ufmt.Printf("[INFO] packet receipt recorded: %t\n", receiptRecorded(packet))
	ufmt.Println("[EXPECTED] child 0 actually deployed the grc20 (name/symbol/decimals/supply match); both children commit in the same recv tx: A=100, B=50, no orphan rejection for child 1")
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

func mustBatchInstruction(b z.Batch) z.Instruction {
	operand, err := z.EncodeBatch(b)
	if err != nil {
		panic(err)
	}
	return z.Instruction{Version: z.INSTR_VERSION_0, Opcode: z.OP_BATCH, Operand: operand}
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
// [SCENARIO] 2. Receive a single batch of [INITIALIZE, ESCROW] for the same token: both mint
// [INFO] deployed token name/symbol/decimals: Gno Token/GNOT/6
// [INFO] deployed token total supply: 150
// [INFO] receiver A balance (child 0, INITIALIZE): 100
// [INFO] receiver B balance (child 1, ESCROW): 50
// [INFO] packet receipt recorded: true
// [EXPECTED] child 0 actually deployed the grc20 (name/symbol/decimals/supply match); both children commit in the same recv tx: A=100, B=50, no orphan rejection for child 1
