// PKGPATH: gno.land/r/onbloc/ibc/scenario/union/recovery
package recovery

// recover_forwarded_voucher_escrow_after_halt_filetest covers the multi-hop
// FORWARD case, distinct from the plain Gno<>Union<>EVM path: the holder
// forwards an already-received voucher onward to a second (non-origin)
// channel via ESCROW, so it sits custodied in channelBalanceV2 rather than
// being burned. Contrast: sending that same voucher directly back to its
// origin (Gno -> Union -> EVM) uses UNESCROW, which burns it immediately at
// Send time — nothing ever lands in escrow, so there is no locked volume on
// Gno to recover in that direct case.

import (
	"encoding/hex"
	"testing"

	"gno.land/p/nt/ufmt/v0"
	"gno.land/p/onbloc/ibc/union/lightclient"
	types "gno.land/p/onbloc/ibc/union/types"
	z "gno.land/p/onbloc/ibc/union/zkgm"

	u256 "gno.land/p/onbloc/math/uint256"

	"gno.land/r/onbloc/ibc/union/access"
	zkgm "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm"
	_ "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/v1"
	_ "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/v2_locked_recovery"
	core "gno.land/r/onbloc/ibc/union/core"
	_ "gno.land/r/onbloc/ibc/union/core/v1"
)

const (
	voucherCoreImplPath         = "gno.land/r/onbloc/ibc/union/core/v1"
	voucherZkgmImplPath         = "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/v1"
	voucherZkgmRecoveryImplPath = "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/v2_locked_recovery"

	voucherAdminAddr  = address("g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5")
	voucherHolderAddr = address("g1wymu47drhr0kuq2098m792lytgtj2nyx77yrsm")
	// voucherRecipientAddr stands in for the EVM voucher holder's Gno address, verified off-chain.
	voucherRecipientAddr = address("g1dyxy88p94acjnm8dmu9tfj2mv2ncvx83cagllu")

	voucherMockClientType = types.ClientType("scenario-mock-lc-voucher")

	voucherBaseDenom   = "remote-weth"
	voucherAmount      = int64(1_000)
	voucherOnwardQuote = "onward-weth"

	voucherZeroSaltHex = "0000000000000000000000000000000000000000000000000000000000000000"
)

func main(cur realm) {
	println("[SCENARIO] 1. Bootstrap IBC host and open a zkgm channel (impl = v1)")
	channelId := bootstrap(cur)
	println("")

	println("[SCENARIO] 2. Recv mints 1000 units of a wrapped voucher to the holder")
	meta := mustTokenMetadata("af739f34ddf951cbc24fdbba4f76213688e13627", z.TokenInitializer{Name: "Wrapped WETH", Symbol: "WETH", Decimals: 6})
	voucherDenom := z.PredictWrappedTokenV2(u256.Zero(), uint32(channelId), []byte(voucherBaseDenom), z.MetadataImage(mustDecodeMeta(meta)))
	recvMint(cur, channelId, voucherDenom, meta)
	ufmt.Printf("[INFO] holder voucher balance: %d\n", zkgm.VoucherBalanceOf(voucherDenom, voucherHolderAddr))
	println("")

	println("[SCENARIO] 3. Holder escrows the voucher onward into a second channel's escrow")
	sendVoucherEscrowOrder(cur, channelId, voucherDenom)
	channelBalanceBefore := printVoucherAccounting(channelId, voucherDenom, "after escrow")
	println("")

	println("[SCENARIO] 4. Union halts: admin pauses the app")
	testing.SetRealm(testing.NewUserRealm(voucherAdminAddr))
	zkgm.Pausable(cross(cur), true)
	println("[INFO] app paused by admin")
	println("")

	println("[SCENARIO] 5. Admin installs the recovery-only impl via UpdateImpl (works regardless of pause)")
	testing.SetRealm(testing.NewUserRealm(voucherAdminAddr))
	zkgm.UpdateImpl(cross(cur), voucherZkgmRecoveryImplPath)
	println("[INFO] impl switched to v2_locked_recovery")
	println("")

	println("[SCENARIO] 6. Admin unpauses so SendRaw can reach the recovery impl, then recovers the escrow")
	testing.SetRealm(testing.NewUserRealm(voucherAdminAddr))
	zkgm.Pausable(cross(cur), false)
	zkgm.SendRaw(cross(cur), uint32(channelId), uint64(1<<62), voucherZeroSaltHex, z.INSTR_VERSION_2, z.OP_TOKEN_ORDER, voucherRecoveryOperandHex([]byte(voucherDenom), []byte(voucherOnwardQuote), voucherAmount, voucherRecipientAddr))
	println("[INFO] locked voucher released")
	channelBalanceAfter := printVoucherAccounting(channelId, voucherDenom, "after recovery")
	printDelta("channel balance", channelBalanceBefore, channelBalanceAfter)
	ufmt.Printf("[INFO] recipient voucher balance: %d\n", zkgm.VoucherBalanceOf(voucherDenom, voucherRecipientAddr))
	ufmt.Println("[EXPECTED] recipient voucher balance should be 1000 (released from escrow)")
}

// printDelta prints how much label changed between before and after (signed,
// since a bare u256 subtraction would panic/wrap on decrease).
func printDelta(label string, before, after *u256.Uint) {
	if after.Cmp(before) >= 0 {
		ufmt.Printf("[INFO] %s change: %s -> %s (+%s)\n", label, before.ToString(), after.ToString(), u256.Zero().Sub(after, before).ToString())
		return
	}
	ufmt.Printf("[INFO] %s change: %s -> %s (-%s)\n", label, before.ToString(), after.ToString(), u256.Zero().Sub(before, after).ToString())
}

func recvMint(cur realm, channelId types.ChannelId, voucherDenom string, meta []byte) {
	order := z.TokenOrderV2{
		Sender:      []byte("remote-sender"),
		Receiver:    []byte(voucherHolderAddr.String()),
		BaseToken:   []byte(voucherBaseDenom),
		BaseAmount:  u256.NewUint(uint64(voucherAmount)),
		QuoteToken:  []byte(voucherDenom),
		QuoteAmount: u256.NewUint(uint64(voucherAmount)),
		Kind:        z.TOKEN_ORDER_KIND_INITIALIZE,
		Metadata:    meta,
	}
	packet := core.NewPacket(types.ChannelId(2), channelId, mustPacketData(mustOrderInstruction(order)), types.Timestamp(1<<62))

	testing.SetRealm(testing.NewUserRealm(voucherAdminAddr))
	core.PacketRecv(cross(cur), core.NewMsgPacketRecv([]types.Packet{packet}, [][]byte{nil}, nil, 1))
}

// sendVoucherEscrowOrder forwards the held voucher onward (ESCROW, not
// UNESCROW) into this channel's escrow instead of back to its origin.
func sendVoucherEscrowOrder(cur realm, channelId types.ChannelId, voucherDenom string) {
	order := z.TokenOrderV2{
		Sender:      []byte(voucherHolderAddr.String()),
		Receiver:    []byte("onward-receiver"),
		BaseToken:   []byte(voucherDenom),
		BaseAmount:  u256.NewUint(uint64(voucherAmount)),
		QuoteToken:  []byte(voucherOnwardQuote),
		QuoteAmount: u256.NewUint(uint64(voucherAmount)),
		Kind:        z.TOKEN_ORDER_KIND_ESCROW,
	}

	testing.SetRealm(testing.NewUserRealm(voucherHolderAddr))
	zkgm.Send(cross(cur), channelId, types.Timestamp(1<<62), [32]byte{}, mustOrderInstruction(order))
}

// printVoucherAccounting prints channel balance for voucherDenom, and returns
// channelBalance for delta printing.
func printVoucherAccounting(channelId types.ChannelId, voucherDenom string, label string) *u256.Uint {
	channelBalance, err := zkgm.GetChannelBalanceV2(channelId, u256.Zero(), voucherDenom, []byte(voucherOnwardQuote))
	if err != nil {
		panic(err)
	}

	ufmt.Printf("[INFO] %s: channel balance=%s proxy voucher balance=%d\n", label, channelBalance.ToString(), zkgm.VoucherBalanceOf(voucherDenom, zkgm.ProxyAddress()))

	return channelBalance
}

func bootstrap(cur realm) types.ChannelId {
	testing.SetRealm(testing.NewUserRealm(voucherAdminAddr))
	core.UpdateImpl(cross(cur), voucherCoreImplPath)
	zkgm.UpdateImpl(cross(cur), voucherZkgmImplPath)
	zkgm.SetRateLimitDisabled(cross(cur), true)
	zkgm.RegisterCoreApp(cross(cur))
	access.GrantRole(cross(cur), access.RelayerRole, voucherAdminAddr)

	core.RegisterClient(cross(cur), voucherMockClientType, func(_, _ []byte) (lightclient.Interface, error) {
		return &mockVoucherLightClient{}, nil
	})
	core.CreateClient(cross(cur), core.NewMsgCreateClient(voucherMockClientType, nil, nil))
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

// voucherRecoveryOperandHex ABI-encodes the recovery request for SendRaw's operandHex.
func voucherRecoveryOperandHex(baseToken, quoteToken []byte, amount int64, recipient address) string {
	order := z.TokenOrderV2{
		BaseToken:   baseToken,
		QuoteToken:  quoteToken,
		BaseAmount:  u256.NewUint(uint64(amount)),
		QuoteAmount: u256.Zero(),
		Receiver:    []byte(recipient.String()),
		Kind:        z.TOKEN_ORDER_KIND_ESCROW,
	}
	operand, err := z.EncodeTokenOrderV2(order)
	if err != nil {
		panic(err)
	}
	return hex.EncodeToString(operand)
}

// --- permissive mock light client (accepts any proof) ---

type mockVoucherLightClient struct{}

func (m *mockVoucherLightClient) VerifyMembership(uint64, []byte, []byte, []byte) error { return nil }
func (m *mockVoucherLightClient) VerifyNonMembership(uint64, []byte, []byte) error      { return nil }
func (m *mockVoucherLightClient) GetTimestamp() types.Timestamp                         { return types.Timestamp(1) }

func (m *mockVoucherLightClient) GetTimestampAtHeight(uint64) (types.Timestamp, error) {
	return types.Timestamp(1), nil
}
func (m *mockVoucherLightClient) GetLatestHeight() uint64        { return 1 }
func (m *mockVoucherLightClient) GetCounterpartyChainID() string { return "mock-chain" }

func (m *mockVoucherLightClient) Status() lightclient.Status { return lightclient.Active }

func (m *mockVoucherLightClient) VerifyHeader(_ address, header []byte, _ address) (types.StateUpdate, error) {
	return types.StateUpdate{Height: 1, ClientStateBytes: header, ConsensusStateBytes: header}, nil
}

func (m *mockVoucherLightClient) VerifyCreation(address, address) (types.ClientCreationResult, error) {
	return types.ClientCreationResult{}, nil
}

func (m *mockVoucherLightClient) Misbehaviour(address, []byte, address) ([]byte, error) {
	return nil, mockVoucherError("mock: misbehaviour unsupported")
}

type mockVoucherError string

func (e mockVoucherError) Error() string { return string(e) }

// Output:
// [SCENARIO] 1. Bootstrap IBC host and open a zkgm channel (impl = v1)
//
// [SCENARIO] 2. Recv mints 1000 units of a wrapped voucher to the holder
// [INFO] holder voucher balance: 1000
//
// [SCENARIO] 3. Holder escrows the voucher onward into a second channel's escrow
// [INFO] after escrow: channel balance=1000 proxy voucher balance=1000
//
// [SCENARIO] 4. Union halts: admin pauses the app
// [INFO] app paused by admin
//
// [SCENARIO] 5. Admin installs the recovery-only impl via UpdateImpl (works regardless of pause)
// [INFO] impl switched to v2_locked_recovery
//
// [SCENARIO] 6. Admin unpauses so SendRaw can reach the recovery impl, then recovers the escrow
// [INFO] locked voucher released
// [INFO] after recovery: channel balance=0 proxy voucher balance=0
// [INFO] channel balance change: 1000 -> 0 (-1000)
// [INFO] recipient voucher balance: 1000
// [EXPECTED] recipient voucher balance should be 1000 (released from escrow)
