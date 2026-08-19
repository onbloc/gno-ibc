// PKGPATH: gno.land/r/onbloc/ibc/scenario/union/recovery
package recovery

// recover_native_escrow_in_partial_installments_after_halt_filetest: recovery
// doesn't have to happen in one shot — two partial releases against the same
// escrow must both decrement channel balance and accumulate the recovered
// ledger correctly (1000 -> 600 -> 0, recovered 0 -> 400 -> 1000).

import (
	"chain"
	"chain/banker"
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
	partialCoreImplPath         = "gno.land/r/onbloc/ibc/union/core/v1"
	partialZkgmImplPath         = "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/v1"
	partialZkgmRecoveryImplPath = "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/v2_locked_recovery"

	partialAdminAddr      = address("g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5")
	partialSenderAddr     = address("g1wymu47drhr0kuq2098m792lytgtj2nyx77yrsm")
	partialRecipientAddr  = address("g1dyxy88p94acjnm8dmu9tfj2mv2ncvx83cagllu")
	partialMockClientType = types.ClientType("scenario-mock-lc-partial")

	partialDenom          = "ugnot"
	partialEscrowedAmount = int64(1_000)
	partialFirstAmount    = int64(400)
	partialSecondAmount   = int64(600)
	partialRemoteQuote    = "remote-ugnot"

	partialZeroSaltHex = "0000000000000000000000000000000000000000000000000000000000000000"
)

func main(cur realm) {
	println("[SCENARIO] 1. Bootstrap IBC host and open a zkgm channel (impl = v1)")
	channelId := partialBootstrap(cur)
	println("")

	println("[SCENARIO] 2. Sender locks 1000ugnot via a native ESCROW send (active, real use)")
	partialSendNativeEscrowOrder(cur, channelId)
	channelBalance0, recovered0 := partialPrintAccounting(channelId, "after send")
	println("")

	println("[SCENARIO] 3. Union halts: admin pauses, installs the recovery impl, then unpauses")
	testing.SetRealm(testing.NewUserRealm(partialAdminAddr))
	zkgm.Pausable(cross(cur), true)
	zkgm.UpdateImpl(cross(cur), partialZkgmRecoveryImplPath)
	zkgm.Pausable(cross(cur), false)
	println("[INFO] impl switched to v2_locked_recovery and app unpaused")
	println("")

	println("[SCENARIO] 4. Admin recovers the escrow in two installments: 400 then 600")
	zkgm.SendRaw(cross(cur), uint32(channelId), uint64(1<<62), partialZeroSaltHex, z.INSTR_VERSION_2, z.OP_TOKEN_ORDER, partialRecoveryOperandHex([]byte(partialDenom), []byte(partialRemoteQuote), partialFirstAmount, partialRecipientAddr))
	channelBalance1, recovered1 := partialPrintAccounting(channelId, "after 1st installment (400)")
	partialPrintDelta("channel balance", channelBalance0, channelBalance1)
	partialPrintDelta("recovered ledger", recovered0, recovered1)

	zkgm.SendRaw(cross(cur), uint32(channelId), uint64(1<<62), partialZeroSaltHex, z.INSTR_VERSION_2, z.OP_TOKEN_ORDER, partialRecoveryOperandHex([]byte(partialDenom), []byte(partialRemoteQuote), partialSecondAmount, partialRecipientAddr))
	channelBalance2, recovered2 := partialPrintAccounting(channelId, "after 2nd installment (600)")
	partialPrintDelta("channel balance", channelBalance1, channelBalance2)
	partialPrintDelta("recovered ledger", recovered1, recovered2)

	bk := banker.NewReadonlyBanker()
	ufmt.Printf("[INFO] recipient native balance: %d\n", bk.GetCoin(partialRecipientAddr, partialDenom))
	ufmt.Println("[EXPECTED] recipient native balance should be 1000 (400+600, fully released)")
}

// partialPrintDelta prints how much label changed between before and after.
func partialPrintDelta(label string, before, after *u256.Uint) {
	if after.Cmp(before) >= 0 {
		ufmt.Printf("[INFO] %s change: %s -> %s (+%s)\n", label, before.ToString(), after.ToString(), u256.Zero().Sub(after, before).ToString())
		return
	}
	ufmt.Printf("[INFO] %s change: %s -> %s (-%s)\n", label, before.ToString(), after.ToString(), u256.Zero().Sub(before, after).ToString())
}

// partialSendNativeEscrowOrder locks partialEscrowedAmount ugnot into channel escrow before the halt.
func partialSendNativeEscrowOrder(cur realm, channelId types.ChannelId) {
	order := z.TokenOrderV2{
		Sender:      []byte(partialSenderAddr.String()),
		Receiver:    []byte("remote-receiver"),
		BaseToken:   []byte(partialDenom),
		BaseAmount:  u256.NewUint(uint64(partialEscrowedAmount)),
		QuoteToken:  []byte(partialRemoteQuote),
		QuoteAmount: u256.NewUint(uint64(partialEscrowedAmount)),
		Kind:        z.TOKEN_ORDER_KIND_ESCROW,
	}

	proxy := zkgm.ProxyAddress()
	testing.IssueCoins(proxy, chain.NewCoins(chain.NewCoin(partialDenom, partialEscrowedAmount)))

	testing.SetRealm(testing.NewUserRealm(partialSenderAddr))
	testing.SetOriginSend(chain.NewCoins(chain.NewCoin(partialDenom, partialEscrowedAmount)))
	zkgm.Send(cross(cur), channelId, types.Timestamp(1<<62), [32]byte{}, partialMustOrderInstruction(order))
}

// partialPrintAccounting prints channel balance and the recovery ledger for
// partialDenom, and returns (channelBalance, recovered) for delta printing.
func partialPrintAccounting(channelId types.ChannelId, label string) (*u256.Uint, *u256.Uint) {
	channelBalance, err := zkgm.GetChannelBalanceV2(channelId, u256.Zero(), partialDenom, []byte(partialRemoteQuote))
	if err != nil {
		panic(err)
	}
	recovered := recoveryimpl.RecoveredLockedAmount(channelId, u256.Zero(), []byte(partialDenom), []byte(partialRemoteQuote))

	ufmt.Printf("[INFO] %s: channel balance=%s recovered ledger=%s\n", label, channelBalance.ToString(), recovered.ToString())

	return channelBalance, recovered
}

func partialBootstrap(cur realm) types.ChannelId {
	testing.SetRealm(testing.NewUserRealm(partialAdminAddr))
	core.UpdateImpl(cross(cur), partialCoreImplPath)
	zkgm.UpdateImpl(cross(cur), partialZkgmImplPath)
	zkgm.SetRateLimitDisabled(cross(cur), true)
	zkgm.RegisterCoreApp(cross(cur))
	access.GrantRole(cross(cur), access.RelayerRole, partialAdminAddr)

	core.RegisterClient(cross(cur), partialMockClientType, func(_, _ []byte) (lightclient.Interface, error) {
		return &partialMockLightClient{}, nil
	})
	core.CreateClient(cross(cur), core.NewMsgCreateClient(partialMockClientType, nil, nil))
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

func partialMustOrderInstruction(order z.TokenOrderV2) z.Instruction {
	operand, err := z.EncodeTokenOrderV2(order)
	if err != nil {
		panic(err)
	}
	return z.Instruction{Version: z.INSTR_VERSION_2, Opcode: z.OP_TOKEN_ORDER, Operand: operand}
}

// partialRecoveryOperandHex ABI-encodes the recovery request for SendRaw's operandHex.
func partialRecoveryOperandHex(baseToken, quoteToken []byte, amount int64, recipient address) string {
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

type partialMockLightClient struct{}

func (m *partialMockLightClient) VerifyMembership(uint64, []byte, []byte, []byte) error { return nil }
func (m *partialMockLightClient) VerifyNonMembership(uint64, []byte, []byte) error      { return nil }
func (m *partialMockLightClient) GetTimestamp() types.Timestamp                         { return types.Timestamp(1) }

func (m *partialMockLightClient) GetTimestampAtHeight(uint64) (types.Timestamp, error) {
	return types.Timestamp(1), nil
}
func (m *partialMockLightClient) GetLatestHeight() uint64        { return 1 }
func (m *partialMockLightClient) GetCounterpartyChainID() string { return "mock-chain" }

func (m *partialMockLightClient) Status() lightclient.Status { return lightclient.Active }

func (m *partialMockLightClient) VerifyHeader(_ address, header []byte, _ address) (types.StateUpdate, error) {
	return types.StateUpdate{Height: 1, ClientStateBytes: header, ConsensusStateBytes: header}, nil
}

func (m *partialMockLightClient) VerifyCreation(address, address) (types.ClientCreationResult, error) {
	return types.ClientCreationResult{}, nil
}

func (m *partialMockLightClient) Misbehaviour(address, []byte, address) ([]byte, error) {
	return nil, partialMockError("mock: misbehaviour unsupported")
}

type partialMockError string

func (e partialMockError) Error() string { return string(e) }

// Output:
// [SCENARIO] 1. Bootstrap IBC host and open a zkgm channel (impl = v1)
//
// [SCENARIO] 2. Sender locks 1000ugnot via a native ESCROW send (active, real use)
// [INFO] after send: channel balance=1000 recovered ledger=0
//
// [SCENARIO] 3. Union halts: admin pauses, installs the recovery impl, then unpauses
// [INFO] impl switched to v2_locked_recovery and app unpaused
//
// [SCENARIO] 4. Admin recovers the escrow in two installments: 400 then 600
// [INFO] after 1st installment (400): channel balance=600 recovered ledger=400
// [INFO] channel balance change: 1000 -> 600 (-400)
// [INFO] recovered ledger change: 0 -> 400 (+400)
// [INFO] after 2nd installment (600): channel balance=0 recovered ledger=1000
// [INFO] channel balance change: 600 -> 0 (-600)
// [INFO] recovered ledger change: 400 -> 1000 (+600)
// [INFO] recipient native balance: 1000
// [EXPECTED] recipient native balance should be 1000 (400+600, fully released)
