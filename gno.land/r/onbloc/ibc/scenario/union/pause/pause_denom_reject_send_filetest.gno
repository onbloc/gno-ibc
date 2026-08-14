// PKGPATH: gno.land/r/onbloc/ibc/scenario/union/pause
package pause

// reject_send_while_denom_paused_filetest is the EXCEPTION-path pause scenario
// for the per-denom pause gate. Unlike the global Pausable switch, PausableDenom
// is scoped to the one paused denom: a send of a different denom is unaffected,
// while any order (verifyTokenOrderV2 checks every kind, not just
// INITIALIZE/ESCROW) whose base token is the paused denom is rejected before
// any funds are escrowed. The rejection is the terminating panic ("denom
// paused"), matched by the // Error: directive.

import (
	"chain"
	"chain/banker"
	"testing"

	"gno.land/p/nt/ufmt/v0"
	"gno.land/p/onbloc/ibc/union/lightclient"
	types "gno.land/p/onbloc/ibc/union/types"
	z "gno.land/p/onbloc/ibc/union/zkgm"

	u256 "gno.land/p/onbloc/math/uint256"

	"gno.land/r/onbloc/ibc/union/access"
	zkgm "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm"
	_ "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/v1"
	core "gno.land/r/onbloc/ibc/union/core"
	_ "gno.land/r/onbloc/ibc/union/core/v1"
)

const (
	coreImplPath = "gno.land/r/onbloc/ibc/union/core/v1"
	zkgmImplPath = "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/v1"

	adminAddr      = address("g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5")
	senderAddr     = address("g1wymu47drhr0kuq2098m792lytgtj2nyx77yrsm")
	mockClientType = types.ClientType("scenario-mock-lc")

	pausedDenom   = "ugnot"
	unpausedDenom = "uatom"
)

func main(cur realm) {
	println("[SCENARIO] 1. Bootstrap IBC host and open a zkgm channel")
	channelId := bootstrap(cur)
	println("")

	println("[SCENARIO] 2. Admin pauses only the ugnot denom")
	testing.SetRealm(testing.NewUserRealm(adminAddr))
	zkgm.PausableDenom(cross(cur), pausedDenom, true)
	println("[INFO] ugnot paused by admin")
	println("")

	println("[SCENARIO] 3. A different denom (uatom) may still be sent - the pause is denom-scoped")
	sendUatomEscrowOrder(cur, channelId)
	println("")

	println("[SCENARIO] 4. Sending the paused denom (ugnot) is rejected before escrow")
	sendUgnotEscrowOrder(cur, channelId)
}

// sendUatomEscrowOrder sends a native ESCROW order locking 40uatom. uatom is
// not paused, so the send succeeds despite ugnot being paused — proof that
// PausableDenom is scoped to the one denom, not a global switch.
func sendUatomEscrowOrder(cur realm, channelId types.ChannelId) {
	order := z.TokenOrderV2{
		Sender:      []byte(senderAddr.String()),
		Receiver:    []byte("remote-receiver"),
		BaseToken:   []byte(unpausedDenom),
		BaseAmount:  u256.NewUint(40),
		QuoteToken:  []byte("remote-uatom"),
		QuoteAmount: u256.NewUint(40),
		Kind:        z.TOKEN_ORDER_KIND_ESCROW,
	}

	proxy := zkgm.ProxyAddress()
	testing.IssueCoins(proxy, chain.NewCoins(chain.NewCoin(unpausedDenom, 40)))

	testing.SetRealm(testing.NewUserRealm(senderAddr))
	testing.SetOriginSend(chain.NewCoins(chain.NewCoin(unpausedDenom, 40)))
	zkgm.Send(cross(cur), channelId, types.Timestamp(1<<62), [32]byte{}, mustOrderInstruction(order))

	bk := banker.NewReadonlyBanker()
	ufmt.Printf("[INFO] proxy uatom escrow balance: %d\n", bk.GetCoin(proxy, unpausedDenom))
	ufmt.Println("[EXPECTED] proxy uatom escrow balance should be 40 (locked)")
}

// sendUgnotEscrowOrder attempts a native ESCROW order locking 40ugnot. ugnot
// is paused, so verifyTokenOrderV2 rejects it before any escrow runs — this
// is the scenario's terminating panic ("denom paused").
func sendUgnotEscrowOrder(cur realm, channelId types.ChannelId) {
	order := z.TokenOrderV2{
		Sender:      []byte(senderAddr.String()),
		Receiver:    []byte("remote-receiver"),
		BaseToken:   []byte(pausedDenom),
		BaseAmount:  u256.NewUint(40),
		QuoteToken:  []byte("remote-ugnot"),
		QuoteAmount: u256.NewUint(40),
		Kind:        z.TOKEN_ORDER_KIND_ESCROW,
	}

	proxy := zkgm.ProxyAddress()
	testing.IssueCoins(proxy, chain.NewCoins(chain.NewCoin(pausedDenom, 40)))

	testing.SetRealm(testing.NewUserRealm(senderAddr))
	testing.SetOriginSend(chain.NewCoins(chain.NewCoin(pausedDenom, 40)))
	zkgm.Send(cross(cur), channelId, types.Timestamp(1<<62), [32]byte{}, mustOrderInstruction(order))
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
// [SCENARIO] 1. Bootstrap IBC host and open a zkgm channel
//
// [SCENARIO] 2. Admin pauses only the ugnot denom
// [INFO] ugnot paused by admin
//
// [SCENARIO] 3. A different denom (uatom) may still be sent - the pause is denom-scoped
// [INFO] proxy uatom escrow balance: 40
// [EXPECTED] proxy uatom escrow balance should be 40 (locked)
//
// [SCENARIO] 4. Sending the paused denom (ugnot) is rejected before escrow

// Error:
// denom paused
