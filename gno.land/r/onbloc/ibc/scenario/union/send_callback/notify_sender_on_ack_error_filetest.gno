// PKGPATH: gno.land/r/onbloc/ibc/scenario/union/send_callback
package send_callback

// notify_sender_on_ack_error_filetest is the failure counterpart of
// notify_sender_on_ack_filetest.gno: when a SendWithCallback-sent ESCROW
// order acks failure, ZKGM refunds the escrow to order.Sender first, then
// notifies the caller via OnZkgmSendResult(success=false). In production
// this is what tells transfer's zkgmSendResult to burn the refunded voucher
// and ack-error the original AtomOne packet (see zkgm_callback.gno) - this
// scenario only proves the ZKGM-side half: refund + notification.

import (
	"testing"

	"gno.land/p/demo/tokens/grc20"
	"gno.land/p/nt/ufmt/v0"
	"gno.land/p/onbloc/ibc/union/lightclient"
	types "gno.land/p/onbloc/ibc/union/types"
	z "gno.land/p/onbloc/ibc/union/zkgm"

	u256 "gno.land/p/gnoswap/uint256"

	"gno.land/r/demo/defi/grc20reg"
	"gno.land/r/onbloc/ibc/union/access"
	zkgm "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm"
	_ "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/v1"
	core "gno.land/r/onbloc/ibc/union/core"
	_ "gno.land/r/onbloc/ibc/union/core/v1"
)

const (
	scenarioPkgPath = "gno.land/r/onbloc/ibc/scenario/union/send_callback"

	coreImplPath = "gno.land/r/onbloc/ibc/union/core/v1"
	zkgmImplPath = "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/v1"

	adminAddr      = address("g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5")
	mockClientType = types.ClientType("scenario-mock-lc")

	grc20Slug = "grc20-notify-fail"
	corrID    = "transfer-corr-id-fail"
)

// mockSendCallback stands in for transfer's zkgmSendResult (zkgm_callback.gno).
type mockSendCallback struct {
	calls   int
	corrID  string
	success bool
}

var callback = &mockSendCallback{}

func (m *mockSendCallback) OnZkgmSendResult(cur realm, corrID string, success bool, ack []byte) error {
	m.calls++
	m.corrID = corrID
	m.success = success
	return nil
}

func main(cur realm) {
	println("[SCENARIO] 1. Register a local grc20 token and mint 40 units to this realm")
	token, ledger, denom := setupGRC20(cur)
	println("")

	println("[SCENARIO] 2. Bootstrap IBC host and open client/connection/channel")
	channelId := bootstrap(cur)
	println("")

	// Undo bootstrap's SetRealm(adminAddr): it patches the whole frame, so
	// cur.Address() would keep resolving to adminAddr without this reset.
	testing.SetRealm(testing.NewCodeRealm(scenarioPkgPath))

	println("[SCENARIO] 3. Register as ZKGM's SendCallback target, approve the proxy, and send a real ESCROW order via SendWithCallback")
	sendPacket := sendEscrowOrder(cur, channelId, token, ledger, denom)
	println("")

	println("[SCENARIO] 4. Acknowledge with a failure ack from the counterparty")
	acknowledgeFailure(cur, sendPacket, token)
}

func setupGRC20(cur realm) (*grc20.Token, *grc20.PrivateLedger, string) {
	token, ledger := grc20.NewToken("Scenario GRC20", "SCN", 6, 0, cur)
	denom := grc20reg.Register(cross(cur), token, grc20Slug)

	if err := ledger.Mint(cur.Address(), 40); err != nil {
		panic(err)
	}

	ufmt.Printf("[INFO] registered grc20 denom: %s\n", denom)
	ufmt.Printf("[INFO] this realm's grc20 balance: %d\n", token.BalanceOf(cur.Address()))
	ufmt.Println("[EXPECTED] should be 40 (freshly minted)")

	return token, ledger, denom
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

	println("[INFO] handshake opened: client=1 connection=1 channel=1")

	return channelId
}

func sendEscrowOrder(cur realm, channelId types.ChannelId, token *grc20.Token, ledger *grc20.PrivateLedger, denom string) types.Packet {
	zkgm.RegisterSendCallback(cross(cur), callback)

	proxy := zkgm.ProxyAddress()
	if err := ledger.Approve(cur.Address(), proxy, 40); err != nil {
		panic(err)
	}

	order := z.TokenOrderV2{
		Sender:      []byte(cur.Address().String()),
		Receiver:    []byte("remote-receiver"),
		BaseToken:   []byte(denom),
		BaseAmount:  u256.NewUint(40),
		QuoteToken:  []byte("remote-grc20"),
		QuoteAmount: u256.NewUint(40),
		Kind:        z.TOKEN_ORDER_KIND_ESCROW,
	}
	sendPacket := zkgm.SendWithCallback(cross(cur), channelId, types.Timestamp(1<<62), [32]byte{}, mustOrderInstruction(order), corrID)

	ufmt.Printf("[INFO] this realm's grc20 balance: %d\n", token.BalanceOf(cur.Address()))
	ufmt.Printf("[INFO] proxy grc20 escrow balance: %d\n", token.BalanceOf(proxy))
	ufmt.Println("[EXPECTED] this realm's balance should be 0 (40 pulled into escrow), proxy balance should be 40")

	return sendPacket
}

// acknowledgeFailure submits a failure ack; ZKGM's own opcode handling
// refunds the 40 units back to order.Sender (this realm) before
// handleSendCallback notifies us.
func acknowledgeFailure(cur realm, sendPacket types.Packet, token *grc20.Token) {
	testing.SetRealm(testing.NewUserRealm(adminAddr))
	core.PacketAcknowledgement(cross(cur), core.NewMsgPacketAcknowledgement([]types.Packet{sendPacket}, [][]byte{mustFailureAck()}, nil, 1))

	// Undo the SetRealm above so cur.Address() reports this realm's balance
	// again, not adminAddr's.
	testing.SetRealm(testing.NewCodeRealm(scenarioPkgPath))

	ufmt.Printf("[INFO] this realm's grc20 balance: %d\n", token.BalanceOf(cur.Address()))
	ufmt.Printf("[INFO] proxy grc20 escrow balance: %d\n", token.BalanceOf(zkgm.ProxyAddress()))
	ufmt.Printf("[INFO] callback invocations: %d\n", callback.calls)
	ufmt.Printf("[INFO] callback corrID: %s\n", callback.corrID)
	ufmt.Printf("[INFO] callback success: %t\n", callback.success)
	ufmt.Println("[EXPECTED] this realm's balance should be back to 40 (refunded by ZKGM), proxy balance 0 (released); callback invoked once with success=false")
}

// --- encoding helpers (pure z calls, mirroring the e2e harness) ---

func mustOrderInstruction(order z.TokenOrderV2) z.Instruction {
	operand, err := z.EncodeTokenOrderV2(order)
	if err != nil {
		panic(err)
	}
	return z.Instruction{Version: z.INSTR_VERSION_2, Opcode: z.OP_TOKEN_ORDER, Operand: operand}
}

func mustFailureAck() []byte {
	ack, err := z.EncodeAck(z.Ack{Tag: new(u256.Uint).SetBytes(z.TAG_ACK_FAILURE[:]), InnerAck: nil})
	if err != nil {
		panic(err)
	}
	return ack
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
func (m *mockLightClient) Status() lightclient.Status     { return lightclient.Active }

func (m *mockLightClient) VerifyHeader(_ address, header []byte, _ address) (types.StateUpdate, error) {
	return types.StateUpdate{Height: 1, ClientStateBytes: header, ConsensusStateBytes: header}, nil
}
func (m *mockLightClient) VerifyCreation(address, address) (types.ClientCreationResult, error) {
	return types.ClientCreationResult{}, nil
}
func (m *mockLightClient) Misbehaviour(address, []byte, address) ([]byte, error) {
	return nil, errMisbehaviourUnsupported
}

var errMisbehaviourUnsupported = mockError("mock: misbehaviour unsupported")

type mockError string

func (e mockError) Error() string { return string(e) }

// Output:
// [SCENARIO] 1. Register a local grc20 token and mint 40 units to this realm
// [INFO] registered grc20 denom: gno.land/r/onbloc/ibc/scenario/union/send_callback.SCN
// [INFO] this realm's grc20 balance: 40
// [EXPECTED] should be 40 (freshly minted)
//
// [SCENARIO] 2. Bootstrap IBC host and open client/connection/channel
// [INFO] handshake opened: client=1 connection=1 channel=1
//
// [SCENARIO] 3. Register as ZKGM's SendCallback target, approve the proxy, and send a real ESCROW order via SendWithCallback
// [INFO] this realm's grc20 balance: 0
// [INFO] proxy grc20 escrow balance: 40
// [EXPECTED] this realm's balance should be 0 (40 pulled into escrow), proxy balance should be 40
//
// [SCENARIO] 4. Acknowledge with a failure ack from the counterparty
// [INFO] this realm's grc20 balance: 40
// [INFO] proxy grc20 escrow balance: 0
// [INFO] callback invocations: 1
// [INFO] callback corrID: transfer-corr-id-fail
// [INFO] callback success: false
// [EXPECTED] this realm's balance should be back to 40 (refunded by ZKGM), proxy balance 0 (released); callback invoked once with success=false
