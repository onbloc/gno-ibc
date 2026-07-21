// PKGPATH: gno.land/r/onbloc/ibc/scenario/union/batch
package batch

// recv_batch_token_order_partial_failure_filetest is the PARTIAL-SUCCESS batch
// scenario: one child fails for an ordinary (non-only-maker) reason while its
// sibling commits normally. executeBatch only aborts the whole batch on a Go
// error or an ACK_ERR_ONLY_MAKER child ack (batch.gno:41-59); an ordinary
// business-level rejection returns (RecvPacketResult{Failure ack}, nil error),
// so the loop just records that child's failure ack and continues. Child 0 here
// is an ESCROW order whose quote token exactly matches the predicted (legacy,
// no-metadata-image) wrapped denom for its base token, but no voucher was ever
// deployed for it — the orphan-voucher guard in executeTokenOrderV2
// (token_order.gno: ESCROW case) rejects it with a plain failure ack, not
// ACK_ERR_ONLY_MAKER. Child 1 is an unrelated INITIALIZE order that mints
// normally. The observable proof of "partial success": child 1 mints, child 0's
// predicted quote token is never minted, and the packet still commits a receipt
// (no panic — the outer batch ack is SUCCESS even though one child failed).

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
	receiverAddr = address("g1wymu47drhr0kuq2098m792lytgtj2nyx77yrsm")
)

func main(cur realm) {
	println("[SCENARIO] 1. Bootstrap IBC host and open a zkgm channel")
	channelId := bootstrap(cur)
	println("")

	println("[SCENARIO] 2. Receive a batch where child 0 (orphan ESCROW) fails and child 1 (INITIALIZE) mints")
	recvPartialFailureBatch(cur, channelId)
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

func recvPartialFailureBatch(cur realm, channelId types.ChannelId) {
	// child 0: ESCROW whose quote token matches the legacy (no metadata image)
	// predicted wrapped denom for "orphan-base", but that denom has never been
	// deployed via INITIALIZE — rejected as an orphan voucher (plain failure ack).
	orphanBase := "orphan-base"
	orphanQuote := z.PredictWrappedToken(u256.Zero(), uint32(channelId), []byte(orphanBase))

	// child 1: a fresh INITIALIZE order that mints normally.
	initBase := "fresh-base"
	meta := mustTokenMetadata("grc20", z.TokenInitializer{Name: "Fresh Token", Symbol: "FRESH", Decimals: 6})
	initQuote := z.PredictWrappedTokenV2(u256.Zero(), uint32(channelId), []byte(initBase), z.MetadataImage(mustDecodeMeta(meta)))

	batch := z.Batch{Instructions: []z.Instruction{
		mustOrderInstruction(z.TokenOrderV2{
			Sender:      []byte("remote-sender"),
			Receiver:    []byte(receiverAddr.String()),
			BaseToken:   []byte(orphanBase),
			BaseAmount:  u256.NewUint(40),
			QuoteToken:  []byte(orphanQuote),
			QuoteAmount: u256.NewUint(40),
			Kind:        z.TOKEN_ORDER_KIND_ESCROW,
		}),
		mustOrderInstruction(z.TokenOrderV2{
			Sender:      []byte("remote-sender"),
			Receiver:    []byte(receiverAddr.String()),
			BaseToken:   []byte(initBase),
			BaseAmount:  u256.NewUint(100),
			QuoteToken:  []byte(initQuote),
			QuoteAmount: u256.NewUint(100),
			Kind:        z.TOKEN_ORDER_KIND_INITIALIZE,
			Metadata:    meta,
		}),
	}}
	packet := core.NewPacket(types.ChannelId(2), channelId, mustPacketData(mustBatchInstruction(batch)), types.Timestamp(1<<62))

	testing.SetRealm(testing.NewUserRealm(adminAddr))
	core.PacketRecv(cross(cur), core.NewMsgPacketRecv([]types.Packet{packet}, [][]byte{nil}, nil, 1))

	ufmt.Printf("[INFO] child 0 (orphan ESCROW) quote token balance: %d\n", zkgm.VoucherBalanceOf(orphanQuote, receiverAddr))
	ufmt.Printf("[INFO] child 1 (INITIALIZE) quote token balance: %d\n", zkgm.VoucherBalanceOf(initQuote, receiverAddr))
	ufmt.Printf("[INFO] packet receipt recorded: %t\n", receiptRecorded(packet))
	ufmt.Println("[EXPECTED] child 0 fails closed (0 minted), child 1 mints 100, no panic, receipt recorded (partial success)")
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
// [SCENARIO] 2. Receive a batch where child 0 (orphan ESCROW) fails and child 1 (INITIALIZE) mints
// [INFO] child 0 (orphan ESCROW) quote token balance: 0
// [INFO] child 1 (INITIALIZE) quote token balance: 100
// [INFO] packet receipt recorded: true
// [EXPECTED] child 0 fails closed (0 minted), child 1 mints 100, no panic, receipt recorded (partial success)
