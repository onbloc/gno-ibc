// PKGPATH: gno.land/r/onbloc/ibc/scenario/union/batch
package batch

// reject_nested_batch_child_filetest is the BY-TYPE batch scenario for the
// current batch limits (re-targeted from the legacy e2e zs89). A flat batch has no
// length cap: an 7-child batch of INITIALIZE orders mints all eight vouchers. A
// nested batch (a batch whose child is itself a batch) is rejected by aborting the
// whole recv transaction: executeBatch panics with execFatal on the disallowed
// opcode, which propagates uncaught out of OnRecvPacket (core does not recover recv
// panics), the same revert semantics as an only-maker child. This matters because a
// plain error return here would let OnRecvPacket commit a failure ack while any
// preceding child's mutations stayed committed — a double-payment when the source
// chain later refunds on that failure ack. The terminating panic is the assertion.

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

	quoteTokens, instructions := buildChildren(channelId)

	println("[SCENARIO] 2. A flat batch of 7 INITIALIZE children mints all eight (no length cap)")
	recvFlatBatch(cur, channelId, instructions, quoteTokens)
	println("")

	println("[SCENARIO] 3. A nested batch (batch inside batch) reverts the whole recv tx")
	recvNestedBatch(cur, channelId)
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

// buildChildren derives 7 distinct wrapped tokens and their INITIALIZE instructions
// (one unit each).
func buildChildren(channelId types.ChannelId) (quoteTokens []string, instructions []z.Instruction) {
	bases := []string{"zs89-a", "zs89-b", "zs89-c", "zs89-d", "zs89-e", "zs89-f", "zs89-g"}
	quoteTokens = make([]string, len(bases))
	instructions = make([]z.Instruction, len(bases))
	for i, base := range bases {
		meta := mustTokenMetadata("grc20", z.TokenInitializer{Name: base, Symbol: "ZS89", Decimals: 6})
		quoteTokens[i] = z.PredictWrappedTokenV2(u256.Zero(), uint32(channelId), []byte(base), z.MetadataImage(mustDecodeMeta(meta)))
		instructions[i] = mustOrderInstruction(z.TokenOrderV2{
			Sender:      []byte("remote-sender"),
			Receiver:    []byte(receiverAddr.String()),
			BaseToken:   []byte(base),
			BaseAmount:  u256.NewUint(1),
			QuoteToken:  []byte(quoteTokens[i]),
			QuoteAmount: u256.NewUint(1),
			Kind:        z.TOKEN_ORDER_KIND_INITIALIZE,
			Metadata:    meta,
		})
	}
	return quoteTokens, instructions
}

func recvFlatBatch(cur realm, channelId types.ChannelId, instructions []z.Instruction, quoteTokens []string) {
	packet := core.NewPacket(types.ChannelId(2), channelId, mustPacketData(mustBatchInstruction(z.Batch{Instructions: instructions})), types.Timestamp(1<<62))

	testing.SetRealm(testing.NewUserRealm(adminAddr))
	core.PacketRecv(cross(cur), core.NewMsgPacketRecv([]types.Packet{packet}, [][]byte{nil}, nil, 1))

	ufmt.Printf("[INFO] minted children: %d\n", mintedChildren(quoteTokens))
	ufmt.Printf("[INFO] packet receipt recorded: %t\n", receiptRecorded(packet))
	ufmt.Println("[EXPECTED] all 7 children minted; receipt recorded")
}

func recvNestedBatch(cur realm, channelId types.ChannelId) {
	nested := z.Batch{Instructions: []z.Instruction{mustBatchInstruction(z.Batch{})}}
	packet := core.NewPacket(types.ChannelId(2), channelId, mustPacketData(mustBatchInstruction(nested)), types.Timestamp(1<<62))

	testing.SetRealm(testing.NewUserRealm(adminAddr))
	core.PacketRecv(cross(cur), core.NewMsgPacketRecv([]types.Packet{packet}, [][]byte{nil}, nil, 1))
}

func mintedChildren(quoteTokens []string) int {
	n := 0
	for _, qt := range quoteTokens {
		if zkgm.VoucherBalanceOf(qt, receiverAddr) == 1 {
			n++
		}
	}
	return n
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
// [SCENARIO] 2. A flat batch of 7 INITIALIZE children mints all eight (no length cap)
// [INFO] minted children: 7
// [INFO] packet receipt recorded: true
// [EXPECTED] all 7 children minted; receipt recorded
//
// [SCENARIO] 3. A nested batch (batch inside batch) reverts the whole recv tx

// Error:
// invalid batch instruction
