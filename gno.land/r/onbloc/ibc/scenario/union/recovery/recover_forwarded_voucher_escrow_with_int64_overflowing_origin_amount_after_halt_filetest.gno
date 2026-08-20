// PKGPATH: gno.land/r/onbloc/ibc/scenario/union/recovery
package recovery

// recover_forwarded_voucher_escrow_with_int64_overflowing_origin_amount_after_halt_filetest:
// the recovery operand carries origin-precision amounts as *u256.Uint (not
// int64) precisely because a raw origin value can exceed int64 range while
// still downscaling to a valid int64 ledger amount. 15 units at 18 origin
// decimals (1.5e19) exceeds math.MaxInt64 (~9.22e18); its ledger amount
// (ScaleExp=12) is 15_000_000, comfortably within int64.

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
	overflowCoreImplPath         = "gno.land/r/onbloc/ibc/union/core/v1"
	overflowZkgmImplPath         = "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/v1"
	overflowZkgmRecoveryImplPath = "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/v2_locked_recovery"

	overflowAdminAddr     = address("g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5")
	overflowHolderAddr    = address("g1wymu47drhr0kuq2098m792lytgtj2nyx77yrsm")
	overflowRecipientAddr = address("g1dyxy88p94acjnm8dmu9tfj2mv2ncvx83cagllu")

	overflowMockClientType = types.ClientType("scenario-mock-lc-overflow")

	overflowBaseDenom   = "remote-overflow-weth"
	overflowOnwardQuote = "onward-overflow-weth"

	// 15 units at 18 origin decimals; exceeds math.MaxInt64 (9_223_372_036_854_775_807).
	// ScaleExp=12 makes the ledger amount 15_000_000.
	overflowOriginAmount = uint64(15_000_000_000_000_000_000)
	overflowLedgerAmount = int64(15_000_000)

	overflowZeroSaltHex = "0000000000000000000000000000000000000000000000000000000000000000"
)

func main(cur realm) {
	println("[SCENARIO] 1. Bootstrap IBC host and open a zkgm channel (impl = v1)")
	channelId := overflowBootstrap(cur)
	println("")

	println("[SCENARIO] 2. Recv mints 15 units (18 origin decimals, exceeds int64) of a wrapped voucher to the holder")
	meta := overflowMustTokenMetadata("af739f34ddf951cbc24fdbba4f76213688e13627", z.TokenInitializer{Name: "Overflow WETH", Symbol: "OWETH", Decimals: 18})
	voucherDenom := z.PredictWrappedTokenV2(u256.Zero(), uint32(channelId), []byte(overflowBaseDenom), z.MetadataImage(overflowMustDecodeMeta(meta)))
	overflowRecvMint(cur, channelId, voucherDenom, meta)
	ufmt.Printf("[INFO] holder voucher ledger balance: %d\n", zkgm.VoucherBalanceOf(voucherDenom, overflowHolderAddr))
	ufmt.Println("[EXPECTED] 15000000 (1.5e19 origin / 10^12 ScaleExp)")
	println("")

	println("[SCENARIO] 3. Holder escrows the voucher onward into a second channel's escrow")
	overflowSendVoucherEscrowOrder(cur, channelId, voucherDenom)
	channelBalanceBefore := overflowPrintAccounting(channelId, voucherDenom, "after escrow")
	println("")

	println("[SCENARIO] 4. Union halts: admin pauses, installs the recovery impl, then unpauses")
	testing.SetRealm(testing.NewUserRealm(overflowAdminAddr))
	zkgm.Pausable(cross(cur), true)
	zkgm.UpdateImpl(cross(cur), overflowZkgmRecoveryImplPath)
	zkgm.Pausable(cross(cur), false)
	println("[INFO] impl switched to v2_locked_recovery and app unpaused")
	println("")

	println("[SCENARIO] 5. Admin recovers using the raw origin amount, which itself overflows int64")
	zkgm.SendRaw(cross(cur), uint32(channelId), uint64(1<<62), overflowZeroSaltHex, z.INSTR_VERSION_2, z.OP_TOKEN_ORDER, overflowRecoveryOperandHex([]byte(voucherDenom), []byte(overflowOnwardQuote), u256.NewUint(overflowOriginAmount), overflowRecipientAddr))
	println("[INFO] locked voucher released")
	channelBalanceAfter := overflowPrintAccounting(channelId, voucherDenom, "after recovery")
	overflowPrintDelta("channel balance", channelBalanceBefore, channelBalanceAfter)
	ufmt.Printf("[INFO] recipient voucher ledger balance: %d\n", zkgm.VoucherBalanceOf(voucherDenom, overflowRecipientAddr))
	ufmt.Println("[EXPECTED] 15000000: the origin amount's u256 representation never narrows to int64")
}

// overflowPrintDelta prints how much label changed between before and after.
func overflowPrintDelta(label string, before, after *u256.Uint) {
	if after.Cmp(before) >= 0 {
		ufmt.Printf("[INFO] %s change: %s -> %s (+%s)\n", label, before.ToString(), after.ToString(), u256.Zero().Sub(after, before).ToString())
		return
	}
	ufmt.Printf("[INFO] %s change: %s -> %s (-%s)\n", label, before.ToString(), after.ToString(), u256.Zero().Sub(before, after).ToString())
}

func overflowRecvMint(cur realm, channelId types.ChannelId, voucherDenom string, meta []byte) {
	order := z.TokenOrderV2{
		Sender:      []byte("remote-sender"),
		Receiver:    []byte(overflowHolderAddr.String()),
		BaseToken:   []byte(overflowBaseDenom),
		BaseAmount:  u256.NewUint(overflowOriginAmount),
		QuoteToken:  []byte(voucherDenom),
		QuoteAmount: u256.NewUint(overflowOriginAmount),
		Kind:        z.TOKEN_ORDER_KIND_INITIALIZE,
		Metadata:    meta,
	}
	packet := core.NewPacket(types.ChannelId(2), channelId, overflowMustPacketData(overflowMustOrderInstruction(order)), types.Timestamp(1<<62))

	testing.SetRealm(testing.NewUserRealm(overflowAdminAddr))
	core.PacketRecv(cross(cur), core.NewMsgPacketRecv([]types.Packet{packet}, [][]byte{nil}, nil, 1))
}

// overflowSendVoucherEscrowOrder forwards the held voucher onward (ESCROW, not
// UNESCROW) using the full origin-precision amount.
func overflowSendVoucherEscrowOrder(cur realm, channelId types.ChannelId, voucherDenom string) {
	order := z.TokenOrderV2{
		Sender:      []byte(overflowHolderAddr.String()),
		Receiver:    []byte("onward-receiver"),
		BaseToken:   []byte(voucherDenom),
		BaseAmount:  u256.NewUint(overflowOriginAmount),
		QuoteToken:  []byte(overflowOnwardQuote),
		QuoteAmount: u256.NewUint(overflowOriginAmount),
		Kind:        z.TOKEN_ORDER_KIND_ESCROW,
	}

	testing.SetRealm(testing.NewUserRealm(overflowHolderAddr))
	zkgm.Send(cross(cur), channelId, types.Timestamp(1<<62), [32]byte{}, overflowMustOrderInstruction(order))
}

// overflowPrintAccounting prints channel balance for voucherDenom, and
// returns channelBalance for delta printing.
func overflowPrintAccounting(channelId types.ChannelId, voucherDenom string, label string) *u256.Uint {
	channelBalance, err := zkgm.GetChannelBalanceV2(channelId, u256.Zero(), voucherDenom, []byte(overflowOnwardQuote))
	if err != nil {
		panic(err)
	}

	ufmt.Printf("[INFO] %s: channel balance=%s proxy voucher ledger balance=%d\n", label, channelBalance.ToString(), zkgm.VoucherBalanceOf(voucherDenom, zkgm.ProxyAddress()))

	return channelBalance
}

func overflowBootstrap(cur realm) types.ChannelId {
	testing.SetRealm(testing.NewUserRealm(overflowAdminAddr))
	core.UpdateImpl(cross(cur), overflowCoreImplPath)
	zkgm.UpdateImpl(cross(cur), overflowZkgmImplPath)
	zkgm.SetRateLimitDisabled(cross(cur), true)
	zkgm.RegisterCoreApp(cross(cur))
	access.GrantRole(cross(cur), access.RelayerRole, overflowAdminAddr)

	core.RegisterClient(cross(cur), overflowMockClientType, func(_, _ []byte) (lightclient.Interface, error) {
		return &overflowMockLightClient{}, nil
	})
	core.CreateClient(cross(cur), core.NewMsgCreateClient(overflowMockClientType, nil, nil))
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

func overflowMustOrderInstruction(order z.TokenOrderV2) z.Instruction {
	operand, err := z.EncodeTokenOrderV2(order)
	if err != nil {
		panic(err)
	}
	return z.Instruction{Version: z.INSTR_VERSION_2, Opcode: z.OP_TOKEN_ORDER, Operand: operand}
}

func overflowMustPacketData(instr z.Instruction) []byte {
	data, err := z.EncodeZkgmPacket(z.ZkgmPacket{Path: u256.Zero(), Instruction: instr})
	if err != nil {
		panic(err)
	}
	return data
}

func overflowMustTokenMetadata(implementationHex string, ti z.TokenInitializer) []byte {
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

func overflowMustDecodeMeta(bz []byte) z.TokenMetadata {
	meta, err := z.DecodeTokenMetadata(bz)
	if err != nil {
		panic(err)
	}
	return meta
}

// overflowRecoveryOperandHex ABI-encodes the recovery request for SendRaw's operandHex.
func overflowRecoveryOperandHex(baseToken, quoteToken []byte, originAmount *u256.Uint, recipient address) string {
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

type overflowMockLightClient struct{}

func (m *overflowMockLightClient) VerifyMembership(uint64, []byte, []byte, []byte) error { return nil }
func (m *overflowMockLightClient) VerifyNonMembership(uint64, []byte, []byte) error      { return nil }
func (m *overflowMockLightClient) GetTimestamp() types.Timestamp                         { return types.Timestamp(1) }

func (m *overflowMockLightClient) GetTimestampAtHeight(uint64) (types.Timestamp, error) {
	return types.Timestamp(1), nil
}
func (m *overflowMockLightClient) GetLatestHeight() uint64        { return 1 }
func (m *overflowMockLightClient) GetCounterpartyChainID() string { return "mock-chain" }

func (m *overflowMockLightClient) Status() lightclient.Status { return lightclient.Active }

func (m *overflowMockLightClient) VerifyHeader(_ address, header []byte, _ address) (types.StateUpdate, error) {
	return types.StateUpdate{Height: 1, ClientStateBytes: header, ConsensusStateBytes: header}, nil
}

func (m *overflowMockLightClient) VerifyCreation(address, address) (types.ClientCreationResult, error) {
	return types.ClientCreationResult{}, nil
}

func (m *overflowMockLightClient) Misbehaviour(address, []byte, address) ([]byte, error) {
	return nil, overflowMockError("mock: misbehaviour unsupported")
}

type overflowMockError string

func (e overflowMockError) Error() string { return string(e) }

// Output:
// [SCENARIO] 1. Bootstrap IBC host and open a zkgm channel (impl = v1)
//
// [SCENARIO] 2. Recv mints 15 units (18 origin decimals, exceeds int64) of a wrapped voucher to the holder
// [INFO] holder voucher ledger balance: 15000000
// [EXPECTED] 15000000 (1.5e19 origin / 10^12 ScaleExp)
//
// [SCENARIO] 3. Holder escrows the voucher onward into a second channel's escrow
// [INFO] after escrow: channel balance=15000000 proxy voucher ledger balance=15000000
//
// [SCENARIO] 4. Union halts: admin pauses, installs the recovery impl, then unpauses
// [INFO] impl switched to v2_locked_recovery and app unpaused
//
// [SCENARIO] 5. Admin recovers using the raw origin amount, which itself overflows int64
// [INFO] locked voucher released
// [INFO] after recovery: channel balance=0 proxy voucher ledger balance=0
// [INFO] channel balance change: 15000000 -> 0 (-15000000)
// [INFO] recipient voucher ledger balance: 15000000
// [EXPECTED] 15000000: the origin amount's u256 representation never narrows to int64
