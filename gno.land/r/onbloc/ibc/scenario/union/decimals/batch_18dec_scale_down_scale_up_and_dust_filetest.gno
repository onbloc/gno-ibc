// PKGPATH: gno.land/r/onbloc/ibc/scenario/union/decimals
package decimals

// batch_18dec_scale_down_scale_up_and_dust_filetest covers decimal policy inside
// OP_BATCH children. A received batch scales an 18-dec INITIALIZE amount down to
// the 6-dec local voucher amount, a dusty batch child is rejected without minting,
// and a sent batch submits the wire amount while locking the local voucher amount.

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
	holderAddr = address("g1wymu47drhr0kuq2098m792lytgtj2nyx77yrsm")

	wireAmount     = uint64(1000000000000000000)
	localAmount    = uint64(1000000)
	dustWireAmount = uint64(1000000000001)
)

func main(cur realm) {
	println("[SCENARIO] 1. Bootstrap IBC host and open a zkgm channel")
	channelId := bootstrap(cur)
	println("")

	meta := mustTokenMetadata("af739f34ddf951cbc24fdbba4f76213688e13627", z.TokenInitializer{Name: "Batch Ether Token", Symbol: "BETH", Decimals: 18})
	quoteToken := z.PredictWrappedTokenV2(u256.Zero(), uint32(channelId), []byte("batchwei"), z.MetadataImage(mustDecodeMeta(meta)))

	println("[SCENARIO] 2. Receive OP_BATCH with 18-dec INITIALIZE child: scaled down to 6-dec local")
	recvBatchInitialize(cur, channelId, quoteToken, meta, wireAmount)
	println("")

	println("[SCENARIO] 3. Receive OP_BATCH with dusty INITIALIZE child: rejected without minting")
	recvBatchInitialize(cur, channelId, quoteToken, meta, dustWireAmount)
	println("")

	println("[SCENARIO] 4. Send OP_BATCH with voucher child: wire amount locks local voucher amount")
	sendBatchEscrow(cur, channelId, quoteToken)
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

func recvBatchInitialize(cur realm, channelId types.ChannelId, quoteToken string, meta []byte, amount uint64) {
	order := z.TokenOrderV2{
		Sender:      []byte("remote-sender"),
		Receiver:    []byte(holderAddr.String()),
		BaseToken:   []byte("batchwei"),
		BaseAmount:  u256.NewUint(amount),
		QuoteToken:  []byte(quoteToken),
		QuoteAmount: u256.NewUint(amount),
		Kind:        z.TOKEN_ORDER_KIND_INITIALIZE,
		Metadata:    meta,
	}
	packet := core.NewPacket(types.ChannelId(2), channelId, mustPacketData(mustBatchInstruction(z.Batch{Instructions: []z.Instruction{mustOrderInstruction(order)}})), types.Timestamp(1<<62))

	before := zkgm.VoucherBalanceOf(quoteToken, holderAddr)

	testing.SetRealm(testing.NewUserRealm(adminAddr))
	core.PacketRecv(cross(cur), core.NewMsgPacketRecv([]types.Packet{packet}, [][]byte{nil}, nil, 1))

	after := zkgm.VoucherBalanceOf(quoteToken, holderAddr)
	ufmt.Printf("[INFO] batch child wire amount: %d\n", amount)
	ufmt.Printf("[INFO] holder voucher balance: %d -> %d\n", before, after)
}

func sendBatchEscrow(cur realm, channelId types.ChannelId, quoteToken string) {
	order := z.TokenOrderV2{
		Sender:      []byte(holderAddr.String()),
		Receiver:    []byte("remote-receiver"),
		BaseToken:   []byte(quoteToken),
		BaseAmount:  u256.NewUint(wireAmount),
		QuoteToken:  []byte("batchwei"),
		QuoteAmount: u256.NewUint(wireAmount),
		Kind:        z.TOKEN_ORDER_KIND_ESCROW,
	}

	before := zkgm.VoucherBalanceOf(quoteToken, holderAddr)
	beforeProxy := zkgm.VoucherBalanceOf(quoteToken, zkgm.ProxyAddress())

	testing.SetRealm(testing.NewUserRealm(holderAddr))
	sendPacket := zkgm.Send(cross(cur), channelId, types.Timestamp(1<<62), [32]byte{}, mustBatchInstruction(z.Batch{Instructions: []z.Instruction{mustOrderInstruction(order)}}))

	after := zkgm.VoucherBalanceOf(quoteToken, holderAddr)
	afterProxy := zkgm.VoucherBalanceOf(quoteToken, zkgm.ProxyAddress())
	decodedOrder := mustDecodeBatchOrder(sendPacket)
	ufmt.Printf("[INFO] holder voucher balance: %d -> %d\n", before, after)
	ufmt.Printf("[INFO] proxy voucher balance: %d -> %d\n", beforeProxy, afterProxy)
	ufmt.Printf("[INFO] packet BaseAmount (decoded): %s\n", decodedOrder.BaseAmount.ToString())
	ufmt.Printf("[INFO] packet QuoteAmount (decoded): %s\n", decodedOrder.QuoteAmount.ToString())
	ufmt.Println("[EXPECTED] batch send locks 1000000 local units from 1000000000000000000 wire units")
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

func mustDecodeBatchOrder(packet types.Packet) z.TokenOrderV2 {
	zkgmPacket, err := z.DecodeZkgmPacket(packet.Data)
	if err != nil {
		panic(err)
	}
	batch, err := z.DecodeBatch(zkgmPacket.Instruction.Operand)
	if err != nil {
		panic(err)
	}
	order, err := z.DecodeTokenOrderV2(batch.Instructions[0].Operand)
	if err != nil {
		panic(err)
	}
	return order
}

// Output:
// [SCENARIO] 1. Bootstrap IBC host and open a zkgm channel
//
// [SCENARIO] 2. Receive OP_BATCH with 18-dec INITIALIZE child: scaled down to 6-dec local
// [INFO] batch child wire amount: 1000000000000000000
// [INFO] holder voucher balance: 0 -> 1000000
//
// [SCENARIO] 3. Receive OP_BATCH with dusty INITIALIZE child: rejected without minting
// [INFO] batch child wire amount: 1000000000001
// [INFO] holder voucher balance: 1000000 -> 1000000
//
// [SCENARIO] 4. Send OP_BATCH with voucher child: wire amount locks local voucher amount
// [INFO] holder voucher balance: 1000000 -> 0
// [INFO] proxy voucher balance: 0 -> 1000000
// [INFO] packet BaseAmount (decoded): 1000000000000000000
// [INFO] packet QuoteAmount (decoded): 1000000000000000000
// [EXPECTED] batch send locks 1000000 local units from 1000000000000000000 wire units
