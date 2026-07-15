// PKGPATH: gno.land/r/onbloc/ibc/scenario/union/upgrade
package upgrade

// voucher_ledger_survives_upgrade_filetest is the LEDGER-preservation upgrade scenario
// (S-3.4). The open question was whether the voucher ledger needs migrating when the
// impl package is swapped. It does not: the voucher store is proxy-owned (the proxy's
// Store, injected into the impl constructor by UpdateImpl), so a re-installed impl reads
// and writes the very same ledger. This file proves both directions across an upgrade:
// after minting 100 to the holder and re-installing the impl, the balance is still 100
// (the new impl READS the surviving ledger), and an ESCROW send of 40 then burns from it
// down to 60 (the new impl WRITES the surviving ledger). No migration step is required.

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
)

func main(cur realm) {
	println("[SCENARIO] 1. Bootstrap IBC host and open a zkgm channel")
	channelId := bootstrap(cur)
	println("")

	meta := mustTokenMetadata("\xaf\x73\x9f\x34\xdd\xf9\x51\xcb\xc2\x4f\xdb\xba\x4f\x76\x21\x36\x88\xe1\x36\x27", z.TokenInitializer{Name: "Gno Token", Symbol: "GNOT", Decimals: 6})
	quoteToken := z.PredictWrappedTokenV2(u256.Zero(), uint32(channelId), []byte("ugnot"), z.MetadataImage(mustDecodeMeta(meta)))

	println("[SCENARIO] 2. Mint 100 of the voucher to the holder")
	mint(cur, channelId, quoteToken, meta)
	ufmt.Printf("[INFO] holder voucher balance: %d\n", zkgm.VoucherBalanceOf(quoteToken, holderAddr))
	ufmt.Println("[EXPECTED] 100")
	println("")

	println("[SCENARIO] 3. Re-install the impl, then READ the ledger: balance survives")
	reinstallImpl(cur)
	ufmt.Printf("[INFO] holder voucher balance after re-install: %d\n", zkgm.VoucherBalanceOf(quoteToken, holderAddr))
	ufmt.Println("[EXPECTED] 100 (new impl reads the proxy-owned ledger; no migration)")
	println("")

	println("[SCENARIO] 4. WRITE the surviving ledger under the new impl: ESCROW send burns 40")
	sendEscrow(cur, channelId, quoteToken)
	ufmt.Printf("[INFO] holder voucher balance after send: %d, proxy escrow: %d\n", zkgm.VoucherBalanceOf(quoteToken, holderAddr), zkgm.VoucherBalanceOf(quoteToken, zkgm.ProxyAddress()))
	ufmt.Println("[EXPECTED] holder 100 -> 60, proxy escrow 40: the new impl writes the same ledger")
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

func mint(cur realm, channelId types.ChannelId, quoteToken string, meta []byte) {
	order := z.TokenOrderV2{
		Sender:      []byte("remote-sender"),
		Receiver:    []byte(holderAddr.String()),
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
}

func reinstallImpl(cur realm) {
	testing.SetRealm(testing.NewUserRealm(adminAddr))
	zkgm.UpdateImpl(cross(cur), zkgmImplPath)
}

func sendEscrow(cur realm, channelId types.ChannelId, quoteToken string) {
	order := z.TokenOrderV2{
		Sender:      []byte(holderAddr.String()),
		Receiver:    []byte("remote-receiver"),
		BaseToken:   []byte(quoteToken),
		BaseAmount:  u256.NewUint(40),
		QuoteToken:  []byte("ugnot"),
		QuoteAmount: u256.NewUint(40),
		Kind:        z.TOKEN_ORDER_KIND_ESCROW,
	}

	testing.SetRealm(testing.NewUserRealm(holderAddr))
	zkgm.Send(cross(cur), channelId, types.Timestamp(1<<62), [32]byte{}, mustOrderInstruction(order))
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
// [SCENARIO] 2. Mint 100 of the voucher to the holder
// [INFO] holder voucher balance: 100
// [EXPECTED] 100
//
// [SCENARIO] 3. Re-install the impl, then READ the ledger: balance survives
// [INFO] holder voucher balance after re-install: 100
// [EXPECTED] 100 (new impl reads the proxy-owned ledger; no migration)
//
// [SCENARIO] 4. WRITE the surviving ledger under the new impl: ESCROW send burns 40
// [INFO] holder voucher balance after send: 60, proxy escrow: 40
// [EXPECTED] holder 100 -> 60, proxy escrow 40: the new impl writes the same ledger
