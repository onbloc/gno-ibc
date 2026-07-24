// PKGPATH: gno.land/r/onbloc/ibc/scenario/union/settlement
package settlement

// ack_failure_refund_filetest is the BY-TYPE settlement scenario for the failure-ack
// refund (re-targeted from the legacy e2e zs23, refund branch). A sender escrows a
// voucher into the proxy on send; when the counterparty returns a FAILURE
// acknowledgement, the escrow is refunded to the sender — the voucher moves back
// from the proxy to the sender and the proxy escrow returns to zero. Both sides of
// the refund are verified as balance diffs. (A protocol-success ack instead leaves
// the escrow settled — that no-op branch is covered by the send/ lock tests.)

import (
	"encoding/hex"
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
	senderAddr = address("g1wymu47drhr0kuq2098m792lytgtj2nyx77yrsm")
)

func main(cur realm) {
	println("[SCENARIO] 1. Bootstrap IBC host and open a zkgm channel")
	channelId := bootstrap(cur)
	println("")

	meta := mustTokenMetadata("af739f34ddf951cbc24fdbba4f76213688e13627", z.TokenInitializer{Name: "Gno Token", Symbol: "GNOT", Decimals: 6})
	quoteToken := z.PredictWrappedTokenV2(u256.Zero(), uint32(channelId), []byte("ugnot"), z.MetadataImage(mustDecodeMeta(meta)))

	println("[SCENARIO] 2. Fund the sender with 100 of the voucher via an INITIALIZE recv")
	fundSender(cur, channelId, quoteToken, meta)
	println("")

	println("[SCENARIO] 3. Send an ESCROW order locking 40 into the proxy")
	sendPacket := sendEscrow(cur, channelId, quoteToken)
	println("")

	println("[SCENARIO] 4. A FAILURE acknowledgement refunds the escrow to the sender")
	failureAckRefund(cur, sendPacket, quoteToken)
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

func fundSender(cur realm, channelId types.ChannelId, quoteToken string, meta []byte) {
	order := z.TokenOrderV2{
		Sender:      []byte("remote-sender"),
		Receiver:    []byte(senderAddr.String()),
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
	ufmt.Printf("[INFO] sender voucher balance: %d\n", zkgm.VoucherBalanceOf(quoteToken, senderAddr))
	ufmt.Println("[EXPECTED] sender should hold 100")
}

func sendEscrow(cur realm, channelId types.ChannelId, quoteToken string) types.Packet {
	order := z.TokenOrderV2{
		Sender:      []byte(senderAddr.String()),
		Receiver:    []byte("remote-receiver"),
		BaseToken:   []byte(quoteToken),
		BaseAmount:  u256.NewUint(40),
		QuoteToken:  []byte("ugnot"),
		QuoteAmount: u256.NewUint(40),
		Kind:        z.TOKEN_ORDER_KIND_ESCROW,
	}

	testing.SetRealm(testing.NewUserRealm(senderAddr))
	sendPacket := zkgm.Send(cross(cur), channelId, types.Timestamp(1<<62), [32]byte{}, mustOrderInstruction(order))

	ufmt.Printf("[INFO] sender voucher balance: %d\n", zkgm.VoucherBalanceOf(quoteToken, senderAddr))
	ufmt.Printf("[INFO] proxy escrow balance: %d\n", zkgm.VoucherBalanceOf(quoteToken, zkgm.ProxyAddress()))
	ufmt.Println("[EXPECTED] sender 100 -> 60, proxy escrow 0 -> 40")
	return sendPacket
}

func failureAckRefund(cur realm, sendPacket types.Packet, quoteToken string) {
	senderBefore := zkgm.VoucherBalanceOf(quoteToken, senderAddr)
	proxyBefore := zkgm.VoucherBalanceOf(quoteToken, zkgm.ProxyAddress())

	testing.SetRealm(testing.NewUserRealm(adminAddr))
	core.PacketAcknowledgement(cross(cur), core.NewMsgPacketAcknowledgement([]types.Packet{sendPacket}, [][]byte{failureAck()}, nil, 1))

	senderAfter := zkgm.VoucherBalanceOf(quoteToken, senderAddr)
	proxyAfter := zkgm.VoucherBalanceOf(quoteToken, zkgm.ProxyAddress())
	ufmt.Printf("[INFO] sender voucher balance: %d -> %d (delta +%d)\n", senderBefore, senderAfter, senderAfter-senderBefore)
	ufmt.Printf("[INFO] proxy escrow balance: %d -> %d (delta %d)\n", proxyBefore, proxyAfter, proxyAfter-proxyBefore)
	ufmt.Println("[EXPECTED] failure ack refunds 40: sender 60 -> 100, proxy escrow 40 -> 0")
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

func failureAck() []byte {
	ack, err := z.EncodeAck(z.Ack{Tag: new(u256.Uint).SetBytes(z.TAG_ACK_FAILURE[:])})
	if err != nil {
		panic(err)
	}
	return ack
}

// Output:
// [SCENARIO] 1. Bootstrap IBC host and open a zkgm channel
//
// [SCENARIO] 2. Fund the sender with 100 of the voucher via an INITIALIZE recv
// [INFO] sender voucher balance: 100
// [EXPECTED] sender should hold 100
//
// [SCENARIO] 3. Send an ESCROW order locking 40 into the proxy
// [INFO] sender voucher balance: 60
// [INFO] proxy escrow balance: 40
// [EXPECTED] sender 100 -> 60, proxy escrow 0 -> 40
//
// [SCENARIO] 4. A FAILURE acknowledgement refunds the escrow to the sender
// [INFO] sender voucher balance: 60 -> 100 (delta +40)
// [INFO] proxy escrow balance: 40 -> 0 (delta -40)
// [EXPECTED] failure ack refunds 40: sender 60 -> 100, proxy escrow 40 -> 0
