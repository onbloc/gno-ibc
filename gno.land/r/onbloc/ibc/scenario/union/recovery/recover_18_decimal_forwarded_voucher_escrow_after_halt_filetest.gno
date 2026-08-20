// PKGPATH: gno.land/r/onbloc/ibc/scenario/union/recovery
package recovery

// recover_18_decimal_forwarded_voucher_escrow_after_halt_filetest is the
// multi-hop FORWARD case (see recover_forwarded_voucher_escrow_after_halt_filetest)
// with 18 origin decimals: proves recovery moves the correct quantity when
// origin decimals exceed the ledger cap (6, ScaleExp=12) — BaseAmount is
// origin precision, same as an ordinary Send, and ledgerAmountOf downscales it.

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
	scaledCoreImplPath         = "gno.land/r/onbloc/ibc/union/core/v1"
	scaledZkgmImplPath         = "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/v1"
	scaledZkgmRecoveryImplPath = "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/v2_locked_recovery"

	scaledAdminAddr     = address("g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5")
	scaledHolderAddr    = address("g1wymu47drhr0kuq2098m792lytgtj2nyx77yrsm")
	scaledRecipientAddr = address("g1dyxy88p94acjnm8dmu9tfj2mv2ncvx83cagllu")

	scaledMockClientType = types.ClientType("scenario-mock-lc-scaled")

	scaledBaseDenom   = "remote-scaled-weth"
	scaledOnwardQuote = "onward-scaled-weth"

	// 2.5 units at 18 origin decimals; ScaleExp=12 makes the ledger amount 2_500_000.
	scaledOriginAmount = uint64(2_500_000_000_000_000_000)
	scaledLedgerAmount = int64(2_500_000)

	scaledZeroSaltHex = "0000000000000000000000000000000000000000000000000000000000000000"
)

func main(cur realm) {
	println("[SCENARIO] 1. Bootstrap IBC host and open a zkgm channel (impl = v1)")
	channelId := bootstrap(cur)
	println("")

	println("[SCENARIO] 2. Recv mints 2.5 units (18 origin decimals) of a wrapped voucher to the holder")
	meta := mustTokenMetadata("af739f34ddf951cbc24fdbba4f76213688e13627", z.TokenInitializer{Name: "Scaled WETH", Symbol: "SWETH", Decimals: 18})
	voucherDenom := z.PredictWrappedTokenV2(u256.Zero(), uint32(channelId), []byte(scaledBaseDenom), z.MetadataImage(mustDecodeMeta(meta)))
	recvMintScaled(cur, channelId, voucherDenom, meta)
	ufmt.Printf("[INFO] holder voucher ledger balance: %d\n", zkgm.VoucherBalanceOf(voucherDenom, scaledHolderAddr))
	ufmt.Println("[EXPECTED] 2500000 (2.5e18 origin / 10^12 ScaleExp)")
	println("")

	println("[SCENARIO] 3. Holder escrows the voucher onward into a second channel's escrow")
	sendScaledVoucherEscrowOrder(cur, channelId, voucherDenom)
	channelBalanceBefore := printScaledAccounting(channelId, voucherDenom, "after escrow")
	println("")

	println("[SCENARIO] 4. Union halts: admin pauses the app")
	testing.SetRealm(testing.NewUserRealm(scaledAdminAddr))
	zkgm.Pausable(cross(cur), true)
	println("[INFO] app paused by admin")
	println("")

	println("[SCENARIO] 5. Admin installs the recovery-only impl via UpdateImpl (works regardless of pause)")
	testing.SetRealm(testing.NewUserRealm(scaledAdminAddr))
	zkgm.UpdateImpl(cross(cur), scaledZkgmRecoveryImplPath)
	println("[INFO] impl switched to v2_locked_recovery")
	println("")

	println("[SCENARIO] 6. Admin unpauses so SendRaw can reach the recovery impl, then recovers the full escrow using the origin-precision amount (2.5e18 -> 2500000 ledger)")
	testing.SetRealm(testing.NewUserRealm(scaledAdminAddr))
	zkgm.Pausable(cross(cur), false)
	// scaledOriginAmount (2.5e18), not scaledLedgerAmount: recovery takes the
	// same origin-precision units as an ordinary Send and downscales via the
	// voucher's ScaleExp, matching the off-chain EVM snapshot an admin would read.
	zkgm.SendRaw(cross(cur), uint32(channelId), uint64(1<<62), scaledZeroSaltHex, z.INSTR_VERSION_2, z.OP_TOKEN_ORDER, scaledRecoveryOperandHex([]byte(voucherDenom), []byte(scaledOnwardQuote), u256.NewUint(scaledOriginAmount), scaledRecipientAddr))
	println("[INFO] locked voucher released")
	channelBalanceAfter := printScaledAccounting(channelId, voucherDenom, "after recovery")
	printDelta("channel balance", channelBalanceBefore, channelBalanceAfter)
	ufmt.Printf("[INFO] recipient voucher ledger balance: %d\n", zkgm.VoucherBalanceOf(voucherDenom, scaledRecipientAddr))
	ufmt.Println("[EXPECTED] 2500000: the full ledger-precision escrow, not 10^-12 of it")
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

func recvMintScaled(cur realm, channelId types.ChannelId, voucherDenom string, meta []byte) {
	order := z.TokenOrderV2{
		Sender:      []byte("remote-sender"),
		Receiver:    []byte(scaledHolderAddr.String()),
		BaseToken:   []byte(scaledBaseDenom),
		BaseAmount:  u256.NewUint(scaledOriginAmount),
		QuoteToken:  []byte(voucherDenom),
		QuoteAmount: u256.NewUint(scaledOriginAmount),
		Kind:        z.TOKEN_ORDER_KIND_INITIALIZE,
		Metadata:    meta,
	}
	packet := core.NewPacket(types.ChannelId(2), channelId, mustPacketData(mustOrderInstruction(order)), types.Timestamp(1<<62))

	testing.SetRealm(testing.NewUserRealm(scaledAdminAddr))
	core.PacketRecv(cross(cur), core.NewMsgPacketRecv([]types.Packet{packet}, [][]byte{nil}, nil, 1))
}

// sendScaledVoucherEscrowOrder forwards the held voucher onward (ESCROW, not
// UNESCROW) using the full origin-precision amount.
func sendScaledVoucherEscrowOrder(cur realm, channelId types.ChannelId, voucherDenom string) {
	order := z.TokenOrderV2{
		Sender:      []byte(scaledHolderAddr.String()),
		Receiver:    []byte("onward-receiver"),
		BaseToken:   []byte(voucherDenom),
		BaseAmount:  u256.NewUint(scaledOriginAmount),
		QuoteToken:  []byte(scaledOnwardQuote),
		QuoteAmount: u256.NewUint(scaledOriginAmount),
		Kind:        z.TOKEN_ORDER_KIND_ESCROW,
	}

	testing.SetRealm(testing.NewUserRealm(scaledHolderAddr))
	zkgm.Send(cross(cur), channelId, types.Timestamp(1<<62), [32]byte{}, mustOrderInstruction(order))
}

// printScaledAccounting prints channel balance for voucherDenom, and returns
// channelBalance for delta printing.
func printScaledAccounting(channelId types.ChannelId, voucherDenom string, label string) *u256.Uint {
	channelBalance, err := zkgm.GetChannelBalanceV2(channelId, u256.Zero(), voucherDenom, []byte(scaledOnwardQuote))
	if err != nil {
		panic(err)
	}

	ufmt.Printf("[INFO] %s: channel balance=%s proxy voucher ledger balance=%d\n", label, channelBalance.ToString(), zkgm.VoucherBalanceOf(voucherDenom, zkgm.ProxyAddress()))

	return channelBalance
}

func bootstrap(cur realm) types.ChannelId {
	testing.SetRealm(testing.NewUserRealm(scaledAdminAddr))
	core.UpdateImpl(cross(cur), scaledCoreImplPath)
	zkgm.UpdateImpl(cross(cur), scaledZkgmImplPath)
	zkgm.SetRateLimitDisabled(cross(cur), true)
	zkgm.RegisterCoreApp(cross(cur))
	access.GrantRole(cross(cur), access.RelayerRole, scaledAdminAddr)

	core.RegisterClient(cross(cur), scaledMockClientType, func(_, _ []byte) (lightclient.Interface, error) {
		return &mockScaledLightClient{}, nil
	})
	core.CreateClient(cross(cur), core.NewMsgCreateClient(scaledMockClientType, nil, nil))
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

// scaledRecoveryOperandHex ABI-encodes the recovery request for SendRaw's
// operandHex. originAmount is a *u256.Uint, not int64, since the impl accepts
// origin-precision amounts that can exceed int64 range (see the ledger amount
// itself, which is what actually gets narrowed to int64).
func scaledRecoveryOperandHex(baseToken, quoteToken []byte, originAmount *u256.Uint, recipient address) string {
	order := z.TokenOrderV2{
		BaseToken:   baseToken,
		QuoteToken:  quoteToken,
		BaseAmount:  originAmount,
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

type mockScaledLightClient struct{}

func (m *mockScaledLightClient) VerifyMembership(uint64, []byte, []byte, []byte) error { return nil }
func (m *mockScaledLightClient) VerifyNonMembership(uint64, []byte, []byte) error      { return nil }
func (m *mockScaledLightClient) GetTimestamp() types.Timestamp                         { return types.Timestamp(1) }

func (m *mockScaledLightClient) GetTimestampAtHeight(uint64) (types.Timestamp, error) {
	return types.Timestamp(1), nil
}
func (m *mockScaledLightClient) GetLatestHeight() uint64        { return 1 }
func (m *mockScaledLightClient) GetCounterpartyChainID() string { return "mock-chain" }

func (m *mockScaledLightClient) Status() lightclient.Status { return lightclient.Active }

func (m *mockScaledLightClient) VerifyHeader(_ address, header []byte, _ address) (types.StateUpdate, error) {
	return types.StateUpdate{Height: 1, ClientStateBytes: header, ConsensusStateBytes: header}, nil
}

func (m *mockScaledLightClient) VerifyCreation(address, address) (types.ClientCreationResult, error) {
	return types.ClientCreationResult{}, nil
}

func (m *mockScaledLightClient) Misbehaviour(address, []byte, address) ([]byte, error) {
	return nil, mockScaledError("mock: misbehaviour unsupported")
}

type mockScaledError string

func (e mockScaledError) Error() string { return string(e) }

// Output:
// [SCENARIO] 1. Bootstrap IBC host and open a zkgm channel (impl = v1)
//
// [SCENARIO] 2. Recv mints 2.5 units (18 origin decimals) of a wrapped voucher to the holder
// [INFO] holder voucher ledger balance: 2500000
// [EXPECTED] 2500000 (2.5e18 origin / 10^12 ScaleExp)
//
// [SCENARIO] 3. Holder escrows the voucher onward into a second channel's escrow
// [INFO] after escrow: channel balance=2500000 proxy voucher ledger balance=2500000
//
// [SCENARIO] 4. Union halts: admin pauses the app
// [INFO] app paused by admin
//
// [SCENARIO] 5. Admin installs the recovery-only impl via UpdateImpl (works regardless of pause)
// [INFO] impl switched to v2_locked_recovery
//
// [SCENARIO] 6. Admin unpauses so SendRaw can reach the recovery impl, then recovers the full escrow using the origin-precision amount (2.5e18 -> 2500000 ledger)
// [INFO] locked voucher released
// [INFO] after recovery: channel balance=0 proxy voucher ledger balance=0
// [INFO] channel balance change: 2500000 -> 0 (-2500000)
// [INFO] recipient voucher ledger balance: 2500000
// [EXPECTED] 2500000: the full ledger-precision escrow, not 10^-12 of it
