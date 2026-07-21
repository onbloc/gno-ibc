// PKGPATH: gno.land/r/onbloc/ibc/scenario/union/send
package send

// lock_grc20_token_by_ucs03_zkgm_filetest walks a locally-registered grc20 token
// through a ucs03-zkgm ESCROW send. Unlike native (funded via attached -send
// coins), a grc20 base token moves via TransferFrom: the sender must approve the
// proxy address before Send, or the escrow order aborts with an allowance error.

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
	_ "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/v1" // install zkgm v1 impl (init registers the constructor)
	core "gno.land/r/onbloc/ibc/union/core"
	_ "gno.land/r/onbloc/ibc/union/core/v1"
)

const (
	coreImplPath = "gno.land/r/onbloc/ibc/union/core/v1"
	zkgmImplPath = "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/v1"

	adminAddr      = address("g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5")
	senderAddr     = address("g1wymu47drhr0kuq2098m792lytgtj2nyx77yrsm")
	mockClientType = types.ClientType("scenario-mock-lc")

	grc20Slug = "grc20-happy"
)

func main(cur realm) {
	// grc20.NewToken is a non-crossing (..., rlm realm) call: it needs cur
	// to still be this scenario's own ambient frame, so it must run before any
	// testing.SetRealm below reassigns that ambient context to an EOA.
	println("[SCENARIO] 1. Register a local grc20 token and mint 40 units to the sender")
	token, ledger, denom := setupGRC20(cur)
	println("")

	println("[SCENARIO] 2. Bootstrap IBC host and open client/connection/channel")
	channelId := bootstrap(cur)
	println("")

	println("[SCENARIO] 3. Send grc20 ESCROW order locking 40 units (sender pre-approves the proxy; pulled via TransferFrom)")
	sendPacket := sendGRC20EscrowOrder(cur, channelId, token, ledger, denom)
	println("")

	println("[SCENARIO] 4. Acknowledge with protocol-fill success (no-op for escrow)")
	acknowledgeGRC20Escrow(cur, sendPacket, token)
}

// setupGRC20 registers a local grc20 token — this scenario realm becomes its
// issuer — and mints 40 units to the sender. Kept separate from bootstrap/send
// because grc20.NewToken must run before any testing.SetRealm call.
func setupGRC20(cur realm) (*grc20.Token, *grc20.PrivateLedger, string) {
	token, ledger := grc20.NewToken("Scenario GRC20", "SCN", 6, 0, cur)
	denom := grc20reg.Register(cross(cur), token, grc20Slug)

	if err := ledger.Mint(senderAddr, 40); err != nil {
		panic(err)
	}

	ufmt.Printf("[INFO] registered grc20 denom: %s\n", denom)
	ufmt.Printf("[INFO] sender grc20 balance: %d\n", token.BalanceOf(senderAddr))
	ufmt.Println("[EXPECTED] sender grc20 balance should be 40 (freshly minted)")

	return token, ledger, denom
}

// bootstrap installs the core/zkgm impls, grants the admin the relayer role, and
// opens a client/connection/channel backed by the permissive mock light client.
//
// It is kept inline (not split further): every admin/relayer core entrypoint
// authorizes the caller via cur.Previous(), so testing.SetRealm and the cross(cur)
// call must run in the same frame for the admin user to be seen as the caller.
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

	ufmt.Printf("[INFO] handshake opened: client=%s connection=%s channel=%s\n", clientId.String(), connectionId.String(), channelId.String())
	ufmt.Println("[EXPECTED] client should be 1")
	ufmt.Println("[EXPECTED] connection should be 1")
	ufmt.Println("[EXPECTED] channel should be 1")

	return channelId
}

// sendGRC20EscrowOrder has the sender approve the proxy address before sending —
// in production the sender submits a separate Approve tx against the token
// realm; Approve here reproduces that pre-authorization — then sends the
// ESCROW order, which pulls the approved amount via TransferFrom.
func sendGRC20EscrowOrder(cur realm, channelId types.ChannelId, token *grc20.Token, ledger *grc20.PrivateLedger, denom string) types.Packet {
	proxy := zkgm.ProxyAddress()
	if err := ledger.Approve(senderAddr, proxy, 40); err != nil {
		panic(err)
	}

	order := z.TokenOrderV2{
		Sender:      []byte(senderAddr.String()),
		Receiver:    []byte("remote-receiver"),
		BaseToken:   []byte(denom),
		BaseAmount:  u256.NewUint(40),
		QuoteToken:  []byte("remote-grc20"),
		QuoteAmount: u256.NewUint(40),
		Kind:        z.TOKEN_ORDER_KIND_ESCROW,
	}

	testing.SetRealm(testing.NewUserRealm(senderAddr))
	sendPacket := zkgm.Send(cross(cur), channelId, types.Timestamp(1<<62), [32]byte{}, mustOrderInstruction(order))

	ufmt.Printf("[INFO] send produced packet on channel: %s\n", sendPacket.SourceChannelId.String())
	ufmt.Printf("[INFO] proxy grc20 escrow balance: %d\n", token.BalanceOf(proxy))
	ufmt.Printf("[INFO] sender grc20 balance: %d\n", token.BalanceOf(senderAddr))
	ufmt.Println("[EXPECTED] send should succeed: approved allowance covers the escrow order")
	ufmt.Println("[EXPECTED] proxy grc20 escrow balance should be 40 (locked)")
	ufmt.Println("[EXPECTED] sender grc20 balance should be 0 (pulled into escrow)")

	return sendPacket
}

// acknowledgeGRC20Escrow acknowledges the sent packet with a protocol-fill success
// ack, which is a no-op for an escrow, so the grc20 units stay locked at the proxy.
func acknowledgeGRC20Escrow(cur realm, sendPacket types.Packet, token *grc20.Token) {
	ack := mustSuccessAck(mustProtocolTokenOrderAck())

	testing.SetRealm(testing.NewUserRealm(adminAddr))
	core.PacketAcknowledgement(cross(cur), core.NewMsgPacketAcknowledgement([]types.Packet{sendPacket}, [][]byte{ack}, nil, 1))

	ufmt.Printf("[INFO] proxy grc20 escrow balance: %d\n", token.BalanceOf(zkgm.ProxyAddress()))
	ufmt.Println("[EXPECTED] proxy grc20 escrow balance should be 40 (unchanged: escrow stays locked)")
}

// --- encoding helpers (pure z calls, mirroring the e2e harness) ---

func mustOrderInstruction(order z.TokenOrderV2) z.Instruction {
	operand, err := z.EncodeTokenOrderV2(order)
	if err != nil {
		panic(err)
	}
	return z.Instruction{Version: z.INSTR_VERSION_2, Opcode: z.OP_TOKEN_ORDER, Operand: operand}
}

func mustProtocolTokenOrderAck() []byte {
	bz, err := z.EncodeTokenOrderAck(z.TokenOrderAck{FillType: new(u256.Uint).SetBytes(z.FILL_TYPE_PROTOCOL[:])})
	if err != nil {
		panic(err)
	}
	return bz
}

func mustSuccessAck(inner []byte) []byte {
	ack, err := z.EncodeAck(z.Ack{Tag: new(u256.Uint).SetBytes(z.TAG_ACK_SUCCESS[:]), InnerAck: inner})
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
// [SCENARIO] 1. Register a local grc20 token and mint 40 units to the sender
// [INFO] registered grc20 denom: gno.land/r/onbloc/ibc/scenario/union/send.SCN
// [INFO] sender grc20 balance: 40
// [EXPECTED] sender grc20 balance should be 40 (freshly minted)
//
// [SCENARIO] 2. Bootstrap IBC host and open client/connection/channel
// [INFO] handshake opened: client=1 connection=1 channel=1
// [EXPECTED] client should be 1
// [EXPECTED] connection should be 1
// [EXPECTED] channel should be 1
//
// [SCENARIO] 3. Send grc20 ESCROW order locking 40 units (sender pre-approves the proxy; pulled via TransferFrom)
// [INFO] send produced packet on channel: 1
// [INFO] proxy grc20 escrow balance: 40
// [INFO] sender grc20 balance: 0
// [EXPECTED] send should succeed: approved allowance covers the escrow order
// [EXPECTED] proxy grc20 escrow balance should be 40 (locked)
// [EXPECTED] sender grc20 balance should be 0 (pulled into escrow)
//
// [SCENARIO] 4. Acknowledge with protocol-fill success (no-op for escrow)
// [INFO] proxy grc20 escrow balance: 40
// [EXPECTED] proxy grc20 escrow balance should be 40 (unchanged: escrow stays locked)
