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
	recoveryimpl "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/v2_locked_recovery"
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
	channelBalanceBefore, recoveredBefore := printAccounting(channelId, "after send")
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
	channelBalanceAfter, recoveredAfter := printAccounting(channelId, "after recovery")
	printDelta("channel balance", channelBalanceBefore, channelBalanceAfter)
	printDelta("recovered ledger", recoveredBefore, recoveredAfter)

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

// printAccounting prints channel balance, total locked, and the recovery
// ledger for lockedDenom, and returns (channelBalance, recovered) so the
// caller can print the before/after delta.
func printAccounting(channelId types.ChannelId, label string) (*u256.Uint, *u256.Uint) {
	channelBalance, err := zkgm.GetChannelBalanceV2(channelId, u256.Zero(), lockedDenom, []byte(remoteQuoteBase))
	if err != nil {
		panic(err)
	}
	locked, err := zkgm.GetLockedTokenAmount(lockedDenom)
	if err != nil {
		panic(err)
	}
	recovered := recoveryimpl.RecoveredLockedAmount(channelId, u256.Zero(), []byte(lockedDenom), []byte(remoteQuoteBase))

	bk := banker.NewReadonlyBanker()
	proxyBalance := bk.GetCoin(zkgm.ProxyAddress(), lockedDenom)

	ufmt.Printf("[INFO] %s: channel balance=%s locked total=%s recovered ledger=%s proxy real balance=%d\n", label, channelBalance.ToString(), locked.ToString(), recovered.ToString(), proxyBalance)

	return channelBalance, recovered
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
// [INFO] after send: channel balance=1000 locked total=0 recovered ledger=0 proxy real balance=1000
//
// [SCENARIO] 3. Union halts: admin pauses the app
// [INFO] app paused by admin
//
// [SCENARIO] 4. Admin installs the recovery-only impl via UpdateImpl (works regardless of pause)
// [INFO] impl switched to v2_locked_recovery
//
// [SCENARIO] 5. Admin unpauses so SendRaw can reach the recovery impl, then recovers the escrow
// [INFO] locked escrow released
// [INFO] after recovery: channel balance=0 locked total=0 recovered ledger=1000 proxy real balance=0
// [INFO] channel balance change: 1000 -> 0 (-1000)
// [INFO] recovered ledger change: 0 -> 1000 (+1000)
// [INFO] recipient native balance: 1000
// [EXPECTED] recipient native balance should be 1000 (released from escrow)

// Events:
// [
//   {
//     "type": "ZkgmImplUpdated",
//     "attrs": [
//       {
//         "key": "caller_pkg_path",
//         "value": ""
//       },
//       {
//         "key": "old_impl_path",
//         "value": ""
//       },
//       {
//         "key": "new_impl_path",
//         "value": "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/v1"
//       },
//       {
//         "key": "allowed_impls",
//         "value": "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/v1"
//       }
//     ],
//     "pkg_path": "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm"
//   },
//   {
//     "type": "ZkgmRateLimitDisabledSet",
//     "attrs": [
//       {
//         "key": "admin",
//         "value": "g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5"
//       },
//       {
//         "key": "disabled",
//         "value": "true"
//       }
//     ],
//     "pkg_path": "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm"
//   },
//   {
//     "type": "AppRegistered",
//     "attrs": [
//       {
//         "key": "port_id",
//         "value": "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm"
//       },
//       {
//         "key": "registrar_pkg_path",
//         "value": "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm"
//       },
//       {
//         "key": "admin_override",
//         "value": "false"
//       }
//     ],
//     "pkg_path": "gno.land/r/onbloc/ibc/union/core"
//   },
//   {
//     "type": "RoleGranted",
//     "attrs": [
//       {
//         "key": "role_id",
//         "value": "1"
//       },
//       {
//         "key": "account",
//         "value": "g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5"
//       },
//       {
//         "key": "since",
//         "value": "1234567890"
//       },
//       {
//         "key": "new_member",
//         "value": "true"
//       }
//     ],
//     "pkg_path": "gno.land/r/onbloc/ibc/union/access"
//   },
//   {
//     "type": "RegisterClient",
//     "attrs": [
//       {
//         "key": "client_type",
//         "value": "scenario-mock-lc"
//       }
//     ],
//     "pkg_path": "gno.land/r/onbloc/ibc/union/core"
//   },
//   {
//     "type": "CreateClient",
//     "attrs": [
//       {
//         "key": "client_id",
//         "value": "1"
//       },
//       {
//         "key": "client_type",
//         "value": "scenario-mock-lc"
//       },
//       {
//         "key": "counterparty_chain_id",
//         "value": "mock-chain"
//       }
//     ],
//     "pkg_path": "gno.land/r/onbloc/ibc/union/core"
//   },
//   {
//     "type": "ConnectionOpenInit",
//     "attrs": [
//       {
//         "key": "connection_id",
//         "value": "1"
//       },
//       {
//         "key": "client_id",
//         "value": "1"
//       },
//       {
//         "key": "counterparty_client_id",
//         "value": "99"
//       }
//     ],
//     "pkg_path": "gno.land/r/onbloc/ibc/union/core"
//   },
//   {
//     "type": "ConnectionOpenAck",
//     "attrs": [
//       {
//         "key": "connection_id",
//         "value": "1"
//       },
//       {
//         "key": "client_id",
//         "value": "1"
//       },
//       {
//         "key": "counterparty_client_id",
//         "value": "99"
//       },
//       {
//         "key": "counterparty_connection_id",
//         "value": "77"
//       }
//     ],
//     "pkg_path": "gno.land/r/onbloc/ibc/union/core"
//   },
//   {
//     "type": "ChannelOpenInit",
//     "attrs": [
//       {
//         "key": "port_id",
//         "value": "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm"
//       },
//       {
//         "key": "channel_id",
//         "value": "1"
//       },
//       {
//         "key": "counterparty_port_id",
//         "value": "0x676e6f2e6c616e642f722f6f6e626c6f632f6962632f756e696f6e2f617070732f75637330335f7a6b676d"
//       },
//       {
//         "key": "connection_id",
//         "value": "1"
//       },
//       {
//         "key": "connection_client_id",
//         "value": "1"
//       },
//       {
//         "key": "connection_counterparty_client_id",
//         "value": "99"
//       },
//       {
//         "key": "connection_counterparty_connection_id",
//         "value": "77"
//       },
//       {
//         "key": "version",
//         "value": "ucs03-zkgm-0"
//       }
//     ],
//     "pkg_path": "gno.land/r/onbloc/ibc/union/core"
//   },
//   {
//     "type": "ChannelOpenAck",
//     "attrs": [
//       {
//         "key": "port_id",
//         "value": "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm"
//       },
//       {
//         "key": "channel_id",
//         "value": "1"
//       },
//       {
//         "key": "counterparty_port_id",
//         "value": "0x676e6f2e6c616e642f722f6f6e626c6f632f6962632f756e696f6e2f617070732f75637330335f7a6b676d"
//       },
//       {
//         "key": "counterparty_channel_id",
//         "value": "2"
//       },
//       {
//         "key": "connection_id",
//         "value": "1"
//       },
//       {
//         "key": "connection_client_id",
//         "value": "1"
//       },
//       {
//         "key": "connection_counterparty_client_id",
//         "value": "99"
//       },
//       {
//         "key": "connection_counterparty_connection_id",
//         "value": "77"
//       },
//       {
//         "key": "version",
//         "value": "ucs03-zkgm-0"
//       }
//     ],
//     "pkg_path": "gno.land/r/onbloc/ibc/union/core"
//   },
//   {
//     "type": "PacketSend",
//     "attrs": [
//       {
//         "key": "packet_hash",
//         "value": "0xc64f71493f30a0a03654ee533142c21fffac1d621e5089d7f43c109bcbd2e625"
//       },
//       {
//         "key": "source_channel_id",
//         "value": "1"
//       },
//       {
//         "key": "source_channel_version",
//         "value": "ucs03-zkgm-0"
//       },
//       {
//         "key": "source_connection_id",
//         "value": "1"
//       },
//       {
//         "key": "source_connection_client_id",
//         "value": "1"
//       },
//       {
//         "key": "destination_channel_id",
//         "value": "2"
//       },
//       {
//         "key": "destination_connection_id",
//         "value": "77"
//       },
//       {
//         "key": "destination_connection_client_id",
//         "value": "99"
//       },
//       {
//         "key": "timeout_timestamp",
//         "value": "4611686018427387904"
//       },
//       {
//         "key": "packet_data_size",
//         "value": "1602"
//       },
//       {
//         "key": "packet_data[0]",
//         "value": "0x5fad00fe8b9c7bfa92f4909db17739d8e5b89fdeaa75af54e2f6b0f4846fb5a30000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000006000000000000000000000000000000000000000000000000000000000000000020000000000000000000000000000000000000000000000000000000000000003000000000000000000000000000000000000000000000000000000000000006000000000000000000000000000000000000000000000000000000000000002400000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000016000000000000000000000000000000000000000000000000000000000000001a000000000000000000000000000000000000000000000000000000000000003e800000000000000000000000000000000000000000000000000000000000001e000000000000000000000000000000000000000000000000000000000000003e8000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000002200000000000000000000000000000000000000000000000000000000000000028673177796d75343764726872306b7571323039386d3739326c797467746a326e797837377972736d000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000f72656d6f74652d72656365697665720000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000575676e6f74000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000c72656d6f74652d75676e6f7400000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"
//       }
//     ],
//     "pkg_path": "gno.land/r/onbloc/ibc/union/core"
//   },
//   {
//     "type": "ZkgmPaused",
//     "attrs": [
//       {
//         "key": "admin",
//         "value": "g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5"
//       }
//     ],
//     "pkg_path": "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm"
//   },
//   {
//     "type": "ZkgmImplUpdated",
//     "attrs": [
//       {
//         "key": "caller_pkg_path",
//         "value": ""
//       },
//       {
//         "key": "old_impl_path",
//         "value": "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/v1"
//       },
//       {
//         "key": "new_impl_path",
//         "value": "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/v2_locked_recovery"
//       },
//       {
//         "key": "allowed_impls",
//         "value": "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/v2_locked_recovery"
//       }
//     ],
//     "pkg_path": "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm"
//   },
//   {
//     "type": "ZkgmUnpaused",
//     "attrs": [
//       {
//         "key": "admin",
//         "value": "g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5"
//       }
//     ],
//     "pkg_path": "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm"
//   },
//   {
//     "type": "ZkgmNativeReleased",
//     "attrs": [
//       {
//         "key": "caller_pkg_path",
//         "value": ""
//       },
//       {
//         "key": "denom",
//         "value": "ugnot"
//       },
//       {
//         "key": "recipient",
//         "value": "g1dyxy88p94acjnm8dmu9tfj2mv2ncvx83cagllu"
//       },
//       {
//         "key": "amount",
//         "value": "1000"
//       }
//     ],
//     "pkg_path": "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm"
//   },
//   {
//     "type": "AdminRecoveredLockedToken",
//     "attrs": [
//       {
//         "key": "admin",
//         "value": "g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5"
//       },
//       {
//         "key": "channel_id",
//         "value": "1"
//       },
//       {
//         "key": "denom",
//         "value": "ugnot"
//       },
//       {
//         "key": "recipient",
//         "value": "g1dyxy88p94acjnm8dmu9tfj2mv2ncvx83cagllu"
//       },
//       {
//         "key": "origin_amount",
//         "value": "1000"
//       },
//       {
//         "key": "ledger_amount",
//         "value": "1000"
//       },
//       {
//         "key": "recovered_ledger_total",
//         "value": "1000"
//       }
//     ],
//     "pkg_path": "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/v2_locked_recovery"
//   }
// ]
