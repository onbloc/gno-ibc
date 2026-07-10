// PKGPATH: gno.land/r/onbloc/ibc/scenario/union/send
package send

// token_send_grc20_initialize_failure_ack_refund_filetest walks a locally-registered
// grc20 token through a ucs03-zkgm INITIALIZE send (with valid TokenMetadata so
// verifyMetadataDecimals passes), then acknowledges it with a FAILURE ack.
// Unlike a protocol-fill or market-maker-fill success ack, a failure ack refunds
// the escrowed grc20 back to the original sender via a plain Transfer (no
// allowance needed for that leg).

import (
	"testing"

	"gno.land/p/demo/tokens/grc20"
	"gno.land/p/nt/ufmt/v0"
	types "gno.land/p/onbloc/ibc/union/types"
	z "gno.land/p/onbloc/ibc/union/zkgm"

	u256 "gno.land/p/gnoswap/uint256"

	"gno.land/p/onbloc/ibc/union/lightclient"
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

	grc20Slug = "grc20-initialize-failure"
)

func main(cur realm) {
	// grc20.NewToken is a non-crossing (_ int, rlm realm, ...) call: it needs cur
	// to still be this scenario's own ambient frame, so it must run before any
	// testing.SetRealm below reassigns that ambient context to an EOA.
	println("[SCENARIO] 1. Register a local grc20 token (6 decimals) and mint 40 units to the sender")
	token, ledger, denom := setupGRC20(cur)
	println("")

	println("[SCENARIO] 2. Bootstrap IBC host and open client/connection/channel")
	channelId := bootstrap(cur)
	println("")

	println("[SCENARIO] 3. Send grc20 INITIALIZE order locking 40 units (sender pre-approves the proxy; pulled via TransferFrom)")
	sendPacket := sendGRC20InitializeOrder(cur, channelId, token, ledger, denom)
	println("")

	println("[SCENARIO] 4. A FAILURE acknowledgement refunds the escrow to the sender")
	acknowledgeFailureRefund(cur, sendPacket, token)
}

func setupGRC20(cur realm) (*grc20.Token, *grc20.PrivateLedger, string) {
	token, ledger := grc20.NewToken(0, cur, "Scenario GRC20", "SCN", 6)
	grc20reg.Register(cross(cur), token, grc20Slug)
	denom := cur.PkgPath() + "." + grc20Slug

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

// sendGRC20InitializeOrder has the sender approve the proxy address before
// sending, then sends the INITIALIZE order with TokenMetadata whose declared
// decimals (6) match the registered grc20's real decimals, so
// verifyMetadataDecimals passes and the order proceeds to pull the approved
// amount via TransferFrom exactly like ESCROW.
func sendGRC20InitializeOrder(cur realm, channelId types.ChannelId, token *grc20.Token, ledger *grc20.PrivateLedger, denom string) types.Packet {
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
		Kind:        z.TOKEN_ORDER_KIND_INITIALIZE,
		Metadata:    mustTokenMetadata("grc20", z.TokenInitializer{Name: "Scenario GRC20", Symbol: "SCN", Decimals: 6}),
	}

	testing.SetRealm(testing.NewUserRealm(senderAddr))
	sendPacket := zkgm.Send(cross(cur), channelId, types.Timestamp(1<<62), [32]byte{}, mustOrderInstruction(order))

	ufmt.Printf("[INFO] send produced packet on channel: %s\n", sendPacket.SourceChannelId.String())
	ufmt.Printf("[INFO] proxy grc20 escrow balance: %d\n", token.BalanceOf(proxy))
	ufmt.Printf("[INFO] sender grc20 balance: %d\n", token.BalanceOf(senderAddr))
	ufmt.Println("[EXPECTED] send should succeed: metadata decimals (6) match the grc20's real decimals")
	ufmt.Println("[EXPECTED] proxy grc20 escrow balance should be 40 (locked)")
	ufmt.Println("[EXPECTED] sender grc20 balance should be 0 (pulled into escrow)")

	return sendPacket
}

// acknowledgeFailureRefund acknowledges the sent packet with a FAILURE ack: the
// escrowed grc20 is released back to the original sender via a plain Transfer
// (no allowance needed for that leg).
func acknowledgeFailureRefund(cur realm, sendPacket types.Packet, token *grc20.Token) {
	proxy := zkgm.ProxyAddress()

	testing.SetRealm(testing.NewUserRealm(adminAddr))
	core.PacketAcknowledgement(cross(cur), core.NewMsgPacketAcknowledgement([]types.Packet{sendPacket}, [][]byte{failureAck()}, nil, 1))

	ufmt.Printf("[INFO] proxy grc20 escrow balance: %d\n", token.BalanceOf(proxy))
	ufmt.Printf("[INFO] sender grc20 balance: %d\n", token.BalanceOf(senderAddr))
	ufmt.Println("[EXPECTED] proxy grc20 escrow balance should be 0 (refunded)")
	ufmt.Println("[EXPECTED] sender grc20 balance should be 40 (escrow refunded back)")
}

// --- encoding helpers (pure z calls, mirroring the e2e harness) ---

func mustOrderInstruction(order z.TokenOrderV2) z.Instruction {
	operand, err := z.EncodeTokenOrderV2(order)
	if err != nil {
		panic(err)
	}
	return z.Instruction{Version: z.INSTR_VERSION_2, Opcode: z.OP_TOKEN_ORDER, Operand: operand}
}

func failureAck() []byte {
	ack, err := z.EncodeAck(z.Ack{Tag: new(u256.Uint).SetBytes(z.TAG_ACK_FAILURE[:])})
	if err != nil {
		panic(err)
	}
	return ack
}

func mustTokenMetadata(implementation string, ti z.TokenInitializer) []byte {
	initBytes, err := z.EncodeTokenInitializer(ti)
	if err != nil {
		panic(err)
	}
	meta, err := z.EncodeTokenMetadata(z.TokenMetadata{Implementation: []byte(implementation), Initializer: initBytes})
	if err != nil {
		panic(err)
	}
	return meta
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
// [SCENARIO] 1. Register a local grc20 token (6 decimals) and mint 40 units to the sender
// [INFO] registered grc20 denom: gno.land/r/onbloc/ibc/scenario/union/send.grc20-initialize-failure
// [INFO] sender grc20 balance: 40
// [EXPECTED] sender grc20 balance should be 40 (freshly minted)
//
// [SCENARIO] 2. Bootstrap IBC host and open client/connection/channel
// [INFO] handshake opened: client=1 connection=1 channel=1
// [EXPECTED] client should be 1
// [EXPECTED] connection should be 1
// [EXPECTED] channel should be 1
//
// [SCENARIO] 3. Send grc20 INITIALIZE order locking 40 units (sender pre-approves the proxy; pulled via TransferFrom)
// [INFO] send produced packet on channel: 1
// [INFO] proxy grc20 escrow balance: 40
// [INFO] sender grc20 balance: 0
// [EXPECTED] send should succeed: metadata decimals (6) match the grc20's real decimals
// [EXPECTED] proxy grc20 escrow balance should be 40 (locked)
// [EXPECTED] sender grc20 balance should be 0 (pulled into escrow)
//
// [SCENARIO] 4. A FAILURE acknowledgement refunds the escrow to the sender
// [INFO] proxy grc20 escrow balance: 0
// [INFO] sender grc20 balance: 40
// [EXPECTED] proxy grc20 escrow balance should be 0 (refunded)
// [EXPECTED] sender grc20 balance should be 40 (escrow refunded back)
