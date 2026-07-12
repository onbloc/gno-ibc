// PKGPATH: gno.land/r/onbloc/ibc/scenario/union/relayer
package relayer

// relayer_fee_follows_submitter_filetest is the BY-TYPE relayer scenario for relayer
// hand-off / drop-out (S-5.1, S-5.2). Delivery is permissionless among relayers: a
// packet is not bound to the relayer that produced it, so if one relayer drops out
// another can submit the proof and complete delivery. The protocol attributes the fee
// (BaseAmount - QuoteAmount, minted in the quote voucher) to *whichever* relayer
// submits that PacketRecv. This file delivers two independent orders through two
// different relayer addresses and verifies each fee lands on the submitting relayer —
// proving the reward follows the actual submitter, which is exactly what makes hand-off
// after a drop-out safe. Distinct packet salts keep the two receives from colliding on
// the receipt-dedup guard (the racing-duplicate case S-5.3 is covered separately by
// settlement/duplicate_recv_noop).

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
	relayerAAddr = address("g1wymu47drhr0kuq2098m792lytgtj2nyx77yrsm")
	relayerBAddr = address("g1dyxy88p94acjnm8dmu9tfj2mv2ncvx83cagllu")
	receiverAddr = address("g1qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqluuxe")
)

func main(cur realm) {
	println("[SCENARIO] 1. Bootstrap IBC host, open a channel, authorize two relayers")
	channelId := bootstrap(cur)
	println("")

	meta := mustTokenMetadata("grc20", z.TokenInitializer{Name: "Relay Token", Symbol: "RLY", Decimals: 6})
	quoteToken := z.PredictWrappedTokenV2(u256.Zero(), uint32(channelId), []byte("urly"), z.MetadataImage(mustDecodeMeta(meta)))

	println("[SCENARIO] 2. Relayer A delivers the first order (INITIALIZE): A keeps the fee")
	deliver(cur, channelId, quoteToken, meta, relayerAAddr, z.TOKEN_ORDER_KIND_INITIALIZE, 100, 90, "A")
	println("")

	println("[SCENARIO] 3. Relayer A drops out; relayer B delivers the second order: B keeps the fee")
	deliver(cur, channelId, quoteToken, meta, relayerBAddr, z.TOKEN_ORDER_KIND_ESCROW, 100, 80, "B")
	println("[EXPECTED] each fee follows the submitting relayer: A +10, B +20 (delivery is not bound to one relayer)")
}

func bootstrap(cur realm) types.ChannelId {
	testing.SetRealm(testing.NewUserRealm(adminAddr))
	core.UpdateImpl(cross(cur), coreImplPath)
	zkgm.UpdateImpl(cross(cur), zkgmImplPath)
	zkgm.SetRateLimitDisabled(cross(cur), true)
	zkgm.RegisterCoreApp(cross(cur))
	access.GrantRole(cross(cur), access.RelayerRole, adminAddr)
	access.GrantRole(cross(cur), access.RelayerRole, chain.PackageAddress(mockLcPkgPath))
	access.GrantRole(cross(cur), access.RelayerRole, relayerAAddr)
	access.GrantRole(cross(cur), access.RelayerRole, relayerBAddr)

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

// deliver receives one fee-bearing order submitted by relayerAddr and verifies the fee
// (base-quote) is minted to that relayer. The two orders differ in Kind (INITIALIZE vs
// ESCROW) and amounts, so their packet commitments differ and neither salt nor the
// receipt-dedup guard is in play. Metadata is only consumed by the INITIALIZE deploy.
func deliver(cur realm, channelId types.ChannelId, quoteToken string, meta []byte, relayerAddr address, kind uint8, base, quote uint64, label string) {
	order := z.TokenOrderV2{
		Sender:      []byte("remote-sender"),
		Receiver:    []byte(receiverAddr.String()),
		BaseToken:   []byte("urly"),
		BaseAmount:  u256.NewUint(base),
		QuoteToken:  []byte(quoteToken),
		QuoteAmount: u256.NewUint(quote),
		Kind:        kind,
		Metadata:    meta,
	}
	packet := core.NewPacket(types.ChannelId(2), channelId, mustPacketData(mustOrderInstruction(order)), types.Timestamp(1<<62))

	feeBefore := zkgm.VoucherBalanceOf(quoteToken, relayerAddr)

	testing.SetRealm(testing.NewUserRealm(relayerAddr))
	core.PacketRecv(cross(cur), core.NewMsgPacketRecv([]types.Packet{packet}, [][]byte{nil}, nil, 1))

	feeAfter := zkgm.VoucherBalanceOf(quoteToken, relayerAddr)
	ufmt.Printf("[INFO] relayer %s fee voucher: %d -> %d (delta +%d)\n", label, feeBefore, feeAfter, feeAfter-feeBefore)
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
// [SCENARIO] 1. Bootstrap IBC host, open a channel, authorize two relayers
//
// [SCENARIO] 2. Relayer A delivers the first order (INITIALIZE): A keeps the fee
// [INFO] relayer A fee voucher: 0 -> 10 (delta +10)
//
// [SCENARIO] 3. Relayer A drops out; relayer B delivers the second order: B keeps the fee
// [INFO] relayer B fee voucher: 0 -> 20 (delta +20)
// [EXPECTED] each fee follows the submitting relayer: A +10, B +20 (delivery is not bound to one relayer)
