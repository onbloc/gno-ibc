// PKGPATH: gno.land/r/onbloc/ibc/scenario/union/recovery
package recovery

// reject_recover_over_escrowed_amount_filetest: decreaseChannelBalanceV2 is
// the fund-safety check — recovering more than what's actually escrowed
// underflows and reverts instead of releasing funds the proxy never held.

import (
	"chain"
	"encoding/hex"
	"testing"

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
	overRecoverCoreImplPath         = "gno.land/r/onbloc/ibc/union/core/v1"
	overRecoverZkgmImplPath         = "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/v1"
	overRecoverZkgmRecoveryImplPath = "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/v2_locked_recovery"

	overRecoverAdminAddr      = address("g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5")
	overRecoverSenderAddr     = address("g1wymu47drhr0kuq2098m792lytgtj2nyx77yrsm")
	overRecoverRecipientAddr  = address("g1dyxy88p94acjnm8dmu9tfj2mv2ncvx83cagllu")
	overRecoverMockClientType = types.ClientType("scenario-mock-lc-over-recover")

	overRecoverDenom          = "ugnot"
	overRecoverEscrowedAmount = int64(1_000)
	overRecoverRemoteQuote    = "remote-ugnot"

	overRecoverZeroSaltHex = "0000000000000000000000000000000000000000000000000000000000000000"
)

func main(cur realm) {
	println("[SCENARIO] 1. Bootstrap IBC host and open a zkgm channel (impl = v1)")
	channelId := overRecoverBootstrap(cur)
	println("")

	println("[SCENARIO] 2. Sender locks 1000ugnot via a native ESCROW send (active, real use)")
	overRecoverSendNativeEscrowOrder(cur, channelId)
	println("")

	println("[SCENARIO] 3. Admin installs the recovery-only impl via UpdateImpl and unpauses")
	testing.SetRealm(testing.NewUserRealm(overRecoverAdminAddr))
	zkgm.UpdateImpl(cross(cur), overRecoverZkgmRecoveryImplPath)
	println("[INFO] impl switched to v2_locked_recovery")
	println("")

	println("[SCENARIO] 4. Admin attempts to recover 1001ugnot against a 1000ugnot escrow -> rejected")
	zkgm.SendRaw(cross(cur), uint32(channelId), uint64(1<<62), overRecoverZeroSaltHex, z.INSTR_VERSION_2, z.OP_TOKEN_ORDER, overRecoverRecoveryOperandHex([]byte(overRecoverDenom), []byte(overRecoverRemoteQuote), overRecoverEscrowedAmount+1, overRecoverRecipientAddr))
}

// overRecoverSendNativeEscrowOrder locks overRecoverEscrowedAmount ugnot into channel escrow.
func overRecoverSendNativeEscrowOrder(cur realm, channelId types.ChannelId) {
	order := z.TokenOrderV2{
		Sender:      []byte(overRecoverSenderAddr.String()),
		Receiver:    []byte("remote-receiver"),
		BaseToken:   []byte(overRecoverDenom),
		BaseAmount:  u256.NewUint(uint64(overRecoverEscrowedAmount)),
		QuoteToken:  []byte(overRecoverRemoteQuote),
		QuoteAmount: u256.NewUint(uint64(overRecoverEscrowedAmount)),
		Kind:        z.TOKEN_ORDER_KIND_ESCROW,
	}

	proxy := zkgm.ProxyAddress()
	testing.IssueCoins(proxy, chain.NewCoins(chain.NewCoin(overRecoverDenom, overRecoverEscrowedAmount)))

	testing.SetRealm(testing.NewUserRealm(overRecoverSenderAddr))
	testing.SetOriginSend(chain.NewCoins(chain.NewCoin(overRecoverDenom, overRecoverEscrowedAmount)))
	zkgm.Send(cross(cur), channelId, types.Timestamp(1<<62), [32]byte{}, overRecoverMustOrderInstruction(order))
}

func overRecoverBootstrap(cur realm) types.ChannelId {
	testing.SetRealm(testing.NewUserRealm(overRecoverAdminAddr))
	core.UpdateImpl(cross(cur), overRecoverCoreImplPath)
	zkgm.UpdateImpl(cross(cur), overRecoverZkgmImplPath)
	zkgm.SetRateLimitDisabled(cross(cur), true)
	zkgm.RegisterCoreApp(cross(cur))
	access.GrantRole(cross(cur), access.RelayerRole, overRecoverAdminAddr)

	core.RegisterClient(cross(cur), overRecoverMockClientType, func(_, _ []byte) (lightclient.Interface, error) {
		return &overRecoverMockLightClient{}, nil
	})
	core.CreateClient(cross(cur), core.NewMsgCreateClient(overRecoverMockClientType, nil, nil))
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

func overRecoverMustOrderInstruction(order z.TokenOrderV2) z.Instruction {
	operand, err := z.EncodeTokenOrderV2(order)
	if err != nil {
		panic(err)
	}
	return z.Instruction{Version: z.INSTR_VERSION_2, Opcode: z.OP_TOKEN_ORDER, Operand: operand}
}

// overRecoverRecoveryOperandHex ABI-encodes the recovery request for SendRaw's operandHex.
func overRecoverRecoveryOperandHex(baseToken, quoteToken []byte, amount int64, recipient address) string {
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

type overRecoverMockLightClient struct{}

func (m *overRecoverMockLightClient) VerifyMembership(uint64, []byte, []byte, []byte) error { return nil }
func (m *overRecoverMockLightClient) VerifyNonMembership(uint64, []byte, []byte) error      { return nil }
func (m *overRecoverMockLightClient) GetTimestamp() types.Timestamp                         { return types.Timestamp(1) }

func (m *overRecoverMockLightClient) GetTimestampAtHeight(uint64) (types.Timestamp, error) {
	return types.Timestamp(1), nil
}
func (m *overRecoverMockLightClient) GetLatestHeight() uint64        { return 1 }
func (m *overRecoverMockLightClient) GetCounterpartyChainID() string { return "mock-chain" }

func (m *overRecoverMockLightClient) Status() lightclient.Status { return lightclient.Active }

func (m *overRecoverMockLightClient) VerifyHeader(_ address, header []byte, _ address) (types.StateUpdate, error) {
	return types.StateUpdate{Height: 1, ClientStateBytes: header, ConsensusStateBytes: header}, nil
}

func (m *overRecoverMockLightClient) VerifyCreation(address, address) (types.ClientCreationResult, error) {
	return types.ClientCreationResult{}, nil
}

func (m *overRecoverMockLightClient) Misbehaviour(address, []byte, address) ([]byte, error) {
	return nil, overRecoverMockError("mock: misbehaviour unsupported")
}

type overRecoverMockError string

func (e overRecoverMockError) Error() string { return string(e) }

// Output:
// [SCENARIO] 1. Bootstrap IBC host and open a zkgm channel (impl = v1)
//
// [SCENARIO] 2. Sender locks 1000ugnot via a native ESCROW send (active, real use)
//
// [SCENARIO] 3. Admin installs the recovery-only impl via UpdateImpl and unpauses
// [INFO] impl switched to v2_locked_recovery
//
// [SCENARIO] 4. Admin attempts to recover 1001ugnot against a 1000ugnot escrow -> rejected

// Error:
// zkgm/channel_balance: underflow
