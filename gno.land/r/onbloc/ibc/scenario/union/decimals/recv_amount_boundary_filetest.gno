// PKGPATH: gno.land/r/onbloc/ibc/scenario/union/decimals
package decimals

// recv_amount_boundary_filetest is the BY-TYPE scenario for the int64 amount
// boundary on receive (S-2.7). A wrapped voucher balance is an int64, so the
// minted amount must fit. On a fresh token (supply 0), a zero amount skips minting,
// an amount up to MaxInt64 mints exactly, and an amount of MaxInt64+1 overflows
// int64 and is rejected (failure acknowledgement, nothing minted). Each amount is
// asserted on its own fresh token via the resulting balance.

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

	maxInt64 = uint64(9223372036854775807) // math.MaxInt64
)

func main(cur realm) {
	println("[SCENARIO] 1. Bootstrap IBC host and open a zkgm channel")
	channelId := bootstrap(cur)
	println("")

	println("[SCENARIO] 2. amount = 0: minting is skipped (QuoteAmount is zero)")
	recvAmount(cur, channelId, "bnd-zero", "Zero", u256.NewUint(0), 0, true)
	println("")

	println("[SCENARIO] 3. amount = MaxInt64: mints exactly (fits int64)")
	recvAmount(cur, channelId, "bnd-max", "Max", u256.NewUint(maxInt64), int64(maxInt64), true)
	println("")

	println("[SCENARIO] 4. amount = MaxInt64 + 1: overflows int64, rejected (nothing minted)")
	recvAmount(cur, channelId, "bnd-over", "Over", new(u256.Uint).Add(u256.NewUint(maxInt64), u256.NewUint(1)), 0, false)
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

// recvAmount receives a fresh-token INITIALIZE order of the given amount and reports
// the resulting (int64) voucher balance.
func recvAmount(cur realm, channelId types.ChannelId, base, name string, amount *u256.Uint, wantBalance int64, wantSuccess bool) {
	meta := mustTokenMetadata("grc20", z.TokenInitializer{Name: name, Symbol: "BND", Decimals: 6})
	quoteToken := z.PredictWrappedTokenV2(u256.Zero(), uint32(channelId), []byte(base), z.MetadataImage(mustDecodeMeta(meta)))
	order := z.TokenOrderV2{
		Sender:      []byte("remote-sender"),
		Receiver:    []byte(receiverAddr.String()),
		BaseToken:   []byte(base),
		BaseAmount:  amount,
		QuoteToken:  []byte(quoteToken),
		QuoteAmount: amount,
		Kind:        z.TOKEN_ORDER_KIND_INITIALIZE,
		Metadata:    meta,
	}
	packet := core.NewPacket(types.ChannelId(2), channelId, mustPacketData(mustOrderInstruction(order)), types.Timestamp(1<<62))

	testing.SetRealm(testing.NewUserRealm(adminAddr))
	core.PacketRecv(cross(cur), core.NewMsgPacketRecv([]types.Packet{packet}, [][]byte{nil}, nil, 1))

	ack := expectedAck(wantSuccess)
	ackSuccess, protocolFill := decodeAckResult(ack)
	ackCommitted := committedAck(packet, ack)
	balance := zkgm.VoucherBalanceOf(quoteToken, receiverAddr)
	if balance != wantBalance || !ackCommitted || ackSuccess != wantSuccess || (wantSuccess && !protocolFill) {
		panic("amount boundary ack/state mismatch")
	}

	ufmt.Printf("[INFO] requested amount %s -> minted balance %d\n", amount.ToString(), balance)
	ufmt.Printf("[INFO] committed ack matches expected: %t\n", ackCommitted)
	ufmt.Printf("[INFO] decoded ack success/protocol fill: %t/%t\n", ackSuccess, protocolFill)
	ufmt.Printf("[INFO] receipt recorded: %t\n", receiptRecorded(packet))
}

func committedAck(packet types.Packet, ack []byte) bool {
	got, err := core.GetBatchReceipts(core.CommitPacketsHash([]types.Packet{packet}))
	return err == nil && got == types.CommitAcks([][]byte{ack})
}

func decodeAckResult(ackBytes []byte) (bool, bool) {
	ack, err := z.DecodeAck(ackBytes)
	if err != nil {
		panic(err)
	}
	success := ack.Tag.Eq(new(u256.Uint).SetBytes(z.TAG_ACK_SUCCESS[:]))
	if !success {
		return false, false
	}

	orderAck, err := z.DecodeTokenOrderAck(ack.InnerAck)
	if err != nil {
		panic(err)
	}

	return true, orderAck.FillType.Eq(new(u256.Uint).SetBytes(z.FILL_TYPE_PROTOCOL[:]))
}

func expectedAck(success bool) []byte {
	if !success {
		ack, err := z.EncodeAck(z.Ack{Tag: u256.NewUint(0), InnerAck: []byte{}})
		if err != nil {
			panic(err)
		}
		return ack
	}

	inner, err := z.EncodeTokenOrderAck(z.TokenOrderAck{FillType: new(u256.Uint).SetBytes(z.FILL_TYPE_PROTOCOL[:])})
	if err != nil {
		panic(err)
	}
	ack, err := z.EncodeAck(z.Ack{Tag: new(u256.Uint).SetBytes(z.TAG_ACK_SUCCESS[:]), InnerAck: inner})
	if err != nil {
		panic(err)
	}
	return ack
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
// [SCENARIO] 2. amount = 0: minting is skipped (QuoteAmount is zero)
// [INFO] requested amount 0 -> minted balance 0
// [INFO] committed ack matches expected: true
// [INFO] decoded ack success/protocol fill: true/true
// [INFO] receipt recorded: true
//
// [SCENARIO] 3. amount = MaxInt64: mints exactly (fits int64)
// [INFO] requested amount 9223372036854775807 -> minted balance 9223372036854775807
// [INFO] committed ack matches expected: true
// [INFO] decoded ack success/protocol fill: true/true
// [INFO] receipt recorded: true
//
// [SCENARIO] 4. amount = MaxInt64 + 1: overflows int64, rejected (nothing minted)
// [INFO] requested amount 9223372036854775808 -> minted balance 0
// [INFO] committed ack matches expected: true
// [INFO] decoded ack success/protocol fill: false/false
// [INFO] receipt recorded: true
