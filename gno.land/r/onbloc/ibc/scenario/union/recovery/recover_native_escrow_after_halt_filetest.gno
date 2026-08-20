// PKGPATH: gno.land/r/onbloc/ibc/scenario/union/recovery
package recovery

// recover_native_escrow_after_halt_filetest is the NORMAL-path scenario: admin
// pauses, installs v2_locked_recovery via UpdateImpl, unpauses so SendRaw can
// reach its repurposed Send, then releases a channel's native escrow.

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
	_ "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/v2_locked_recovery"
	core "gno.land/r/onbloc/ibc/union/core"
	_ "gno.land/r/onbloc/ibc/union/core/v1"
)

const (
	coreImplPath         = "gno.land/r/onbloc/ibc/union/core/v1"
	zkgmImplPath         = "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/v1"
	zkgmRecoveryImplPath = "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/v2_locked_recovery"

	adminAddr  = address("g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5")
	senderAddr = address("g1wymu47drhr0kuq2098m792lytgtj2nyx77yrsm")
	// recipientAddr stands in for the EVM voucher holder's Gno address, verified off-chain.
	recipientAddr = address("g1dyxy88p94acjnm8dmu9tfj2mv2ncvx83cagllu")

	mockClientType = types.ClientType("scenario-mock-lc")

	lockedDenom     = "ugnot"
	lockedAmount    = int64(1_000)
	remoteQuoteBase = "remote-ugnot"

	zeroSaltHex = "0000000000000000000000000000000000000000000000000000000000000000"
)

func main(cur realm) {
	println("[SCENARIO] 1. Bootstrap IBC host and open a zkgm channel (impl = v1)")
	channelId := bootstrap(cur)
	println("")

	println("[SCENARIO] 2. Sender locks 1000ugnot via a native ESCROW send (active, real use)")
	sendNativeEscrowOrder(cur, channelId)
	channelBalanceBefore := printAccounting(channelId, "after send")
	println("")

	println("[SCENARIO] 3. Union halts: admin pauses the app")
	testing.SetRealm(testing.NewUserRealm(adminAddr))
	zkgm.Pausable(cross(cur), true)
	println("[INFO] app paused by admin")
	println("")

	println("[SCENARIO] 4. Admin installs the recovery-only impl via UpdateImpl (works regardless of pause)")
	testing.SetRealm(testing.NewUserRealm(adminAddr))
	zkgm.UpdateImpl(cross(cur), zkgmRecoveryImplPath)
	println("[INFO] impl switched to v2_locked_recovery")
	println("")

	println("[SCENARIO] 5. Admin unpauses so SendRaw can reach the recovery impl, then recovers the escrow")
	testing.SetRealm(testing.NewUserRealm(adminAddr))
	zkgm.Pausable(cross(cur), false)
	zkgm.SendRaw(cross(cur), uint32(channelId), uint64(1<<62), zeroSaltHex, z.INSTR_VERSION_2, z.OP_TOKEN_ORDER, recoveryOperandHex([]byte(lockedDenom), []byte(remoteQuoteBase), lockedAmount, recipientAddr))
	println("[INFO] locked escrow released")
	channelBalanceAfter := printAccounting(channelId, "after recovery")
	printDelta("channel balance", channelBalanceBefore, channelBalanceAfter)

	bk := banker.NewReadonlyBanker()
	ufmt.Printf("[INFO] recipient native balance: %d\n", bk.GetCoin(recipientAddr, lockedDenom))
	ufmt.Println("[EXPECTED] recipient native balance should be 1000 (released from escrow)")
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

// sendNativeEscrowOrder locks lockedAmount ugnot into channel escrow before the halt.
func sendNativeEscrowOrder(cur realm, channelId types.ChannelId) {
	order := z.TokenOrderV2{
		Sender:      []byte(senderAddr.String()),
		Receiver:    []byte("remote-receiver"),
		BaseToken:   []byte(lockedDenom),
		BaseAmount:  u256.NewUint(uint64(lockedAmount)),
		QuoteToken:  []byte(remoteQuoteBase),
		QuoteAmount: u256.NewUint(uint64(lockedAmount)),
		Kind:        z.TOKEN_ORDER_KIND_ESCROW,
	}

	proxy := zkgm.ProxyAddress()
	testing.IssueCoins(proxy, chain.NewCoins(chain.NewCoin(lockedDenom, lockedAmount)))

	testing.SetRealm(testing.NewUserRealm(senderAddr))
	testing.SetOriginSend(chain.NewCoins(chain.NewCoin(lockedDenom, lockedAmount)))
	zkgm.Send(cross(cur), channelId, types.Timestamp(1<<62), [32]byte{}, mustOrderInstruction(order))
}

// printAccounting prints channel balance and total locked for lockedDenom,
// and returns channelBalance so the caller can print the before/after delta.
func printAccounting(channelId types.ChannelId, label string) *u256.Uint {
	channelBalance, err := zkgm.GetChannelBalanceV2(channelId, u256.Zero(), lockedDenom, []byte(remoteQuoteBase))
	if err != nil {
		panic(err)
	}
	locked, err := zkgm.GetLockedTokenAmount(lockedDenom)
	if err != nil {
		panic(err)
	}

	bk := banker.NewReadonlyBanker()
	proxyBalance := bk.GetCoin(zkgm.ProxyAddress(), lockedDenom)

	ufmt.Printf("[INFO] %s: channel balance=%s locked total=%s proxy real balance=%d\n", label, channelBalance.ToString(), locked.ToString(), proxyBalance)

	return channelBalance
}

func bootstrap(cur realm) types.ChannelId {
	testing.SetRealm(testing.NewUserRealm(adminAddr))
	core.UpdateImpl(cross(cur), coreImplPath)
	zkgm.UpdateImpl(cross(cur), zkgmImplPath)
	zkgm.SetRateLimitDisabled(cross(cur), true)
	zkgm.RegisterCoreApp(cross(cur))
	access.GrantRole(cross(cur), access.RelayerRole, adminAddr)

	core.RegisterClient(cross(cur), mockClientType, func(_, _ []byte) (lightclient.Interface, error) {
		return &mockLightClient{}, nil
	})
	core.CreateClient(cross(cur), core.NewMsgCreateClient(mockClientType, nil, nil))
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

// recoveryOperandHex ABI-encodes the recovery request for SendRaw's operandHex.
func recoveryOperandHex(baseToken, quoteToken []byte, amount int64, recipient address) string {
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

type mockLightClient struct{}

func (m *mockLightClient) VerifyMembership(uint64, []byte, []byte, []byte) error { return nil }
func (m *mockLightClient) VerifyNonMembership(uint64, []byte, []byte) error      { return nil }
func (m *mockLightClient) GetTimestamp() types.Timestamp                         { return types.Timestamp(1) }

func (m *mockLightClient) GetTimestampAtHeight(uint64) (types.Timestamp, error) {
	return types.Timestamp(1), nil
}
func (m *mockLightClient) GetLatestHeight() uint64        { return 1 }
func (m *mockLightClient) GetCounterpartyChainID() string { return "mock-chain" }

func (m *mockLightClient) Status() lightclient.Status { return lightclient.Active }

func (m *mockLightClient) VerifyHeader(_ address, header []byte, _ address) (types.StateUpdate, error) {
	return types.StateUpdate{Height: 1, ClientStateBytes: header, ConsensusStateBytes: header}, nil
}

func (m *mockLightClient) VerifyCreation(address, address) (types.ClientCreationResult, error) {
	return types.ClientCreationResult{}, nil
}

func (m *mockLightClient) Misbehaviour(address, []byte, address) ([]byte, error) {
	return nil, mockError("mock: misbehaviour unsupported")
}

type mockError string

func (e mockError) Error() string { return string(e) }

// Output:
// [SCENARIO] 1. Bootstrap IBC host and open a zkgm channel (impl = v1)
//
// [SCENARIO] 2. Sender locks 1000ugnot via a native ESCROW send (active, real use)
// [INFO] after send: channel balance=1000 locked total=0 proxy real balance=1000
//
// [SCENARIO] 3. Union halts: admin pauses the app
// [INFO] app paused by admin
//
// [SCENARIO] 4. Admin installs the recovery-only impl via UpdateImpl (works regardless of pause)
// [INFO] impl switched to v2_locked_recovery
//
// [SCENARIO] 5. Admin unpauses so SendRaw can reach the recovery impl, then recovers the escrow
// [INFO] locked escrow released
// [INFO] after recovery: channel balance=0 locked total=0 proxy real balance=0
// [INFO] channel balance change: 1000 -> 0 (-1000)
// [INFO] recipient native balance: 1000
// [EXPECTED] recipient native balance should be 1000 (released from escrow)
