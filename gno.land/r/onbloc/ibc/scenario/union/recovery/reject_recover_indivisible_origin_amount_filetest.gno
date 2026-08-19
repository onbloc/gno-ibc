// PKGPATH: gno.land/r/onbloc/ibc/scenario/union/recovery
package recovery

// reject_recover_indivisible_origin_amount_filetest: recovery's origin-precision
// BaseAmount must divide evenly by the voucher's ScaleExp (same rule an ordinary
// Send enforces) — a runbook typo that's off by one sub-ledger unit is rejected
// before any state moves, rather than silently rounding.

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
	recoveryimpl "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/v2_locked_recovery"
	core "gno.land/r/onbloc/ibc/union/core"
	_ "gno.land/r/onbloc/ibc/union/core/v1"
)

const (
	indivisibleCoreImplPath         = "gno.land/r/onbloc/ibc/union/core/v1"
	indivisibleZkgmImplPath         = "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/v1"
	indivisibleZkgmRecoveryImplPath = "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/v2_locked_recovery"

	indivisibleAdminAddr     = address("g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5")
	indivisibleHolderAddr    = address("g1wymu47drhr0kuq2098m792lytgtj2nyx77yrsm")
	indivisibleRecipientAddr = address("g1dyxy88p94acjnm8dmu9tfj2mv2ncvx83cagllu")

	indivisibleMockClientType = types.ClientType("scenario-mock-lc-indivisible")

	indivisibleBaseDenom   = "remote-indivisible-weth"
	indivisibleOnwardQuote = "onward-indivisible-weth"

	// 2.5 units at 18 origin decimals (ScaleExp=12, ledger amount 2_500_000);
	// +1 is one sub-ledger unit of dust, not divisible by 10^12.
	indivisibleOriginAmount    = uint64(2_500_000_000_000_000_000)
	indivisibleBadOriginAmount = uint64(2_500_000_000_000_000_001)

	indivisibleZeroSaltHex = "0000000000000000000000000000000000000000000000000000000000000000"
)

func main(cur realm) {
	println("[SCENARIO] 1. Bootstrap IBC host and open a zkgm channel (impl = v1)")
	channelId := indivisibleBootstrap(cur)
	println("")

	println("[SCENARIO] 2. Recv mints 2.5 units (18 origin decimals) of a wrapped voucher to the holder")
	meta := indivisibleMustTokenMetadata("af739f34ddf951cbc24fdbba4f76213688e13627", z.TokenInitializer{Name: "Indivisible WETH", Symbol: "IWETH", Decimals: 18})
	voucherDenom := z.PredictWrappedTokenV2(u256.Zero(), uint32(channelId), []byte(indivisibleBaseDenom), z.MetadataImage(indivisibleMustDecodeMeta(meta)))
	indivisibleRecvMint(cur, channelId, voucherDenom, meta)
	println("")

	println("[SCENARIO] 3. Holder escrows the voucher onward into a second channel's escrow")
	indivisibleSendVoucherEscrowOrder(cur, channelId, voucherDenom)
	channelBalanceBefore, recoveredBefore := indivisiblePrintAccounting(channelId, voucherDenom, "after escrow")
	println("")

	println("[SCENARIO] 4. Union halts: admin pauses, installs the recovery impl, then unpauses")
	testing.SetRealm(testing.NewUserRealm(indivisibleAdminAddr))
	zkgm.Pausable(cross(cur), true)
	zkgm.UpdateImpl(cross(cur), indivisibleZkgmRecoveryImplPath)
	zkgm.Pausable(cross(cur), false)
	println("[INFO] impl switched to v2_locked_recovery and app unpaused")
	println("")

	println("[SCENARIO] 5. Admin attempts recovery with one sub-ledger unit of dust (2_500_000_000_000_000_001) -> rejected before any state moves")
	ufmt.Printf("[INFO] escrowed before the attempt: channel balance=%s recovered ledger=%s\n", channelBalanceBefore.ToString(), recoveredBefore.ToString())
	zkgm.SendRaw(cross(cur), uint32(channelId), uint64(1<<62), indivisibleZeroSaltHex, z.INSTR_VERSION_2, z.OP_TOKEN_ORDER, indivisibleRecoveryOperandHex([]byte(voucherDenom), []byte(indivisibleOnwardQuote), indivisibleBadOriginAmount, indivisibleRecipientAddr))
}

func indivisibleRecvMint(cur realm, channelId types.ChannelId, voucherDenom string, meta []byte) {
	order := z.TokenOrderV2{
		Sender:      []byte("remote-sender"),
		Receiver:    []byte(indivisibleHolderAddr.String()),
		BaseToken:   []byte(indivisibleBaseDenom),
		BaseAmount:  u256.NewUint(indivisibleOriginAmount),
		QuoteToken:  []byte(voucherDenom),
		QuoteAmount: u256.NewUint(indivisibleOriginAmount),
		Kind:        z.TOKEN_ORDER_KIND_INITIALIZE,
		Metadata:    meta,
	}
	packet := core.NewPacket(types.ChannelId(2), channelId, indivisibleMustPacketData(indivisibleMustOrderInstruction(order)), types.Timestamp(1<<62))

	testing.SetRealm(testing.NewUserRealm(indivisibleAdminAddr))
	core.PacketRecv(cross(cur), core.NewMsgPacketRecv([]types.Packet{packet}, [][]byte{nil}, nil, 1))
}

// indivisibleSendVoucherEscrowOrder forwards the held voucher onward (ESCROW, not UNESCROW).
func indivisibleSendVoucherEscrowOrder(cur realm, channelId types.ChannelId, voucherDenom string) {
	order := z.TokenOrderV2{
		Sender:      []byte(indivisibleHolderAddr.String()),
		Receiver:    []byte("onward-receiver"),
		BaseToken:   []byte(voucherDenom),
		BaseAmount:  u256.NewUint(indivisibleOriginAmount),
		QuoteToken:  []byte(indivisibleOnwardQuote),
		QuoteAmount: u256.NewUint(indivisibleOriginAmount),
		Kind:        z.TOKEN_ORDER_KIND_ESCROW,
	}

	testing.SetRealm(testing.NewUserRealm(indivisibleHolderAddr))
	zkgm.Send(cross(cur), channelId, types.Timestamp(1<<62), [32]byte{}, indivisibleMustOrderInstruction(order))
}

// indivisiblePrintAccounting prints channel balance and the recovery ledger for
// voucherDenom, and returns (channelBalance, recovered) for before/after comparison.
func indivisiblePrintAccounting(channelId types.ChannelId, voucherDenom string, label string) (*u256.Uint, *u256.Uint) {
	channelBalance, err := zkgm.GetChannelBalanceV2(channelId, u256.Zero(), voucherDenom, []byte(indivisibleOnwardQuote))
	if err != nil {
		panic(err)
	}
	recovered := recoveryimpl.RecoveredLockedAmount(channelId, u256.Zero(), []byte(voucherDenom), []byte(indivisibleOnwardQuote))

	ufmt.Printf("[INFO] %s: channel balance=%s recovered ledger=%s\n", label, channelBalance.ToString(), recovered.ToString())

	return channelBalance, recovered
}

func indivisibleBootstrap(cur realm) types.ChannelId {
	testing.SetRealm(testing.NewUserRealm(indivisibleAdminAddr))
	core.UpdateImpl(cross(cur), indivisibleCoreImplPath)
	zkgm.UpdateImpl(cross(cur), indivisibleZkgmImplPath)
	zkgm.SetRateLimitDisabled(cross(cur), true)
	zkgm.RegisterCoreApp(cross(cur))
	access.GrantRole(cross(cur), access.RelayerRole, indivisibleAdminAddr)

	core.RegisterClient(cross(cur), indivisibleMockClientType, func(_, _ []byte) (lightclient.Interface, error) {
		return &indivisibleMockLightClient{}, nil
	})
	core.CreateClient(cross(cur), core.NewMsgCreateClient(indivisibleMockClientType, nil, nil))
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

func indivisibleMustOrderInstruction(order z.TokenOrderV2) z.Instruction {
	operand, err := z.EncodeTokenOrderV2(order)
	if err != nil {
		panic(err)
	}
	return z.Instruction{Version: z.INSTR_VERSION_2, Opcode: z.OP_TOKEN_ORDER, Operand: operand}
}

func indivisibleMustPacketData(instr z.Instruction) []byte {
	data, err := z.EncodeZkgmPacket(z.ZkgmPacket{Path: u256.Zero(), Instruction: instr})
	if err != nil {
		panic(err)
	}
	return data
}

func indivisibleMustTokenMetadata(implementationHex string, ti z.TokenInitializer) []byte {
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

func indivisibleMustDecodeMeta(bz []byte) z.TokenMetadata {
	meta, err := z.DecodeTokenMetadata(bz)
	if err != nil {
		panic(err)
	}
	return meta
}

// indivisibleRecoveryOperandHex ABI-encodes the recovery request for SendRaw's operandHex.
func indivisibleRecoveryOperandHex(baseToken, quoteToken []byte, originAmount uint64, recipient address) string {
	order := z.TokenOrderV2{
		BaseToken:   baseToken,
		QuoteToken:  quoteToken,
		BaseAmount:  u256.NewUint(originAmount),
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

type indivisibleMockLightClient struct{}

func (m *indivisibleMockLightClient) VerifyMembership(uint64, []byte, []byte, []byte) error { return nil }
func (m *indivisibleMockLightClient) VerifyNonMembership(uint64, []byte, []byte) error      { return nil }
func (m *indivisibleMockLightClient) GetTimestamp() types.Timestamp                         { return types.Timestamp(1) }

func (m *indivisibleMockLightClient) GetTimestampAtHeight(uint64) (types.Timestamp, error) {
	return types.Timestamp(1), nil
}
func (m *indivisibleMockLightClient) GetLatestHeight() uint64        { return 1 }
func (m *indivisibleMockLightClient) GetCounterpartyChainID() string { return "mock-chain" }

func (m *indivisibleMockLightClient) Status() lightclient.Status { return lightclient.Active }

func (m *indivisibleMockLightClient) VerifyHeader(_ address, header []byte, _ address) (types.StateUpdate, error) {
	return types.StateUpdate{Height: 1, ClientStateBytes: header, ConsensusStateBytes: header}, nil
}

func (m *indivisibleMockLightClient) VerifyCreation(address, address) (types.ClientCreationResult, error) {
	return types.ClientCreationResult{}, nil
}

func (m *indivisibleMockLightClient) Misbehaviour(address, []byte, address) ([]byte, error) {
	return nil, indivisibleMockError("mock: misbehaviour unsupported")
}

type indivisibleMockError string

func (e indivisibleMockError) Error() string { return string(e) }

// Output:
// [SCENARIO] 1. Bootstrap IBC host and open a zkgm channel (impl = v1)
//
// [SCENARIO] 2. Recv mints 2.5 units (18 origin decimals) of a wrapped voucher to the holder
//
// [SCENARIO] 3. Holder escrows the voucher onward into a second channel's escrow
// [INFO] after escrow: channel balance=2500000 recovered ledger=0
//
// [SCENARIO] 4. Union halts: admin pauses, installs the recovery impl, then unpauses
// [INFO] impl switched to v2_locked_recovery and app unpaused
//
// [SCENARIO] 5. Admin attempts recovery with one sub-ledger unit of dust (2_500_000_000_000_000_001) -> rejected before any state moves
// [INFO] escrowed before the attempt: channel balance=2500000 recovered ledger=0

// Error:
// zkgm: amount not divisible by token scale factor
