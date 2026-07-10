// PKGPATH: gno.land/r/onbloc/ibc/scenario/union/receive
package receive

// token_receive_grc20_unescrow_protocol_fill_partial_filetest exercises the grc20-token
// release path on receive when only part of the escrow is released. It first locks
// 40 grc20 units in the proxy escrow (a user ESCROW send, funded via a pre-approved
// TransferFrom pull), then receives an UNESCROW packet that releases 25 of those
// units to the receiver via a plain Transfer. The channel balance decreases by the
// released amount and the receiver's on-chain grc20 balance increases by 25, while
// 15 units remain locked in escrow.

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
	userAddr       = address("g1wymu47drhr0kuq2098m792lytgtj2nyx77yrsm")
	receiverAddr   = address("g1dyxy88p94acjnm8dmu9tfj2mv2ncvx83cagllu")
	mockClientType = types.ClientType("scenario-mock-lc")

	grc20Slug = "grc20-partial"

	// quoteWrapped stands in for the counterparty's wrapped denom. It only keys
	// the channel balance (lock increases it, unescrow decreases it); the recv
	// unescrow path does not re-derive it, so a stable placeholder is enough.
	quoteWrapped = "remote-wrapped-grc20"
)

func main(cur realm) {
	// grc20.NewToken is a non-crossing (_ int, rlm realm, ...) call: it needs cur
	// to still be this scenario's own ambient frame, so it must run before any
	// testing.SetRealm below reassigns that ambient context to an EOA.
	println("[SCENARIO] 1. Register a local grc20 token and mint 40 units to the user")
	token, ledger, denom := setupGRC20(cur)
	println("")

	println("[SCENARIO] 2. Bootstrap IBC host and open client/connection/channel")
	channelId := bootstrap(cur)
	println("")

	println("[SCENARIO] 3. Lock 40 grc20 units into proxy escrow (user ESCROW send, pulled via TransferFrom)")
	lockGRC20Escrow(cur, channelId, token, ledger, denom)
	println("")

	println("[SCENARIO] 4. Receive UNESCROW order: release 25 grc20 units from escrow to the receiver")
	receiveUnescrowOrder(cur, channelId, token, denom)
}

// setupGRC20 registers a local grc20 token — this scenario realm becomes its
// issuer — and mints 40 units to the user. Kept separate from bootstrap/lock
// because grc20.NewToken must run before any testing.SetRealm call.
func setupGRC20(cur realm) (*grc20.Token, *grc20.PrivateLedger, string) {
	token, ledger := grc20.NewToken(0, cur, "Scenario GRC20", "SCN", 6)
	grc20reg.Register(cross(cur), token, grc20Slug)
	denom := cur.PkgPath() + "." + grc20Slug

	if err := ledger.Mint(userAddr, 40); err != nil {
		panic(err)
	}

	ufmt.Printf("[INFO] registered grc20 denom: %s\n", denom)
	ufmt.Printf("[INFO] user grc20 balance: %d\n", token.BalanceOf(userAddr))
	ufmt.Println("[EXPECTED] user grc20 balance should be 40 (freshly minted)")

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

// lockGRC20Escrow has the user approve the proxy address before sending — in
// production the user submits a separate Approve tx against the token realm;
// Approve here reproduces that pre-authorization — then sends the ESCROW order,
// which pulls the approved amount via TransferFrom.
func lockGRC20Escrow(cur realm, channelId types.ChannelId, token *grc20.Token, ledger *grc20.PrivateLedger, denom string) {
	proxy := zkgm.ProxyAddress()
	if err := ledger.Approve(userAddr, proxy, 40); err != nil {
		panic(err)
	}

	order := z.TokenOrderV2{
		Sender:      []byte(userAddr.String()),
		Receiver:    []byte("remote-receiver"),
		BaseToken:   []byte(denom),
		BaseAmount:  u256.NewUint(40),
		QuoteToken:  []byte(quoteWrapped),
		QuoteAmount: u256.NewUint(40),
		Kind:        z.TOKEN_ORDER_KIND_ESCROW,
	}

	testing.SetRealm(testing.NewUserRealm(userAddr))
	_ = zkgm.Send(cross(cur), channelId, types.Timestamp(1<<62), [32]byte{}, mustOrderInstruction(order))

	ufmt.Printf("[INFO] proxy grc20 escrow balance: %d\n", token.BalanceOf(proxy))
	ufmt.Printf("[INFO] user grc20 balance: %d\n", token.BalanceOf(userAddr))
	ufmt.Println("[EXPECTED] proxy grc20 escrow balance should be 40 (locked)")
	ufmt.Println("[EXPECTED] user grc20 balance should be 0 (still escrowed)")
}

// receiveUnescrowOrder receives an UNESCROW order that releases part (25) of the
// escrowed grc20 units from the proxy to the receiver via a plain Transfer,
// leaving the remaining 15 units locked.
func receiveUnescrowOrder(cur realm, channelId types.ChannelId, token *grc20.Token, denom string) {
	order := z.TokenOrderV2{
		Sender:      []byte("remote-sender"),
		Receiver:    []byte(receiverAddr.String()),
		BaseToken:   []byte(quoteWrapped),
		BaseAmount:  u256.NewUint(25),
		QuoteToken:  []byte(denom),
		QuoteAmount: u256.NewUint(25),
		Kind:        z.TOKEN_ORDER_KIND_UNESCROW,
	}
	packet := core.NewPacket(types.ChannelId(2), channelId, mustPacketData(mustOrderInstruction(order)), types.Timestamp(1<<62))

	testing.SetRealm(testing.NewUserRealm(adminAddr))
	core.PacketRecv(cross(cur), core.NewMsgPacketRecv([]types.Packet{packet}, [][]byte{nil}, nil, 1))

	proxy := zkgm.ProxyAddress()
	ufmt.Printf("[INFO] proxy grc20 escrow balance: %d\n", token.BalanceOf(proxy))
	ufmt.Printf("[INFO] receiver grc20 balance: %d\n", token.BalanceOf(receiverAddr))
	ufmt.Println("[EXPECTED] proxy grc20 escrow balance should be 15 (40 - 25 released)")
	ufmt.Println("[EXPECTED] receiver grc20 balance should be 25 (units returned to the receiver)")
}

// --- encoding helpers (pure z calls, mirroring the e2e harness) ---

func mustOrderInstruction(order z.TokenOrderV2) z.Instruction {
	operand, err := z.EncodeTokenOrderV2(order)
	if err != nil {
		panic(err)
	}
	return z.Instruction{Version: z.INSTR_VERSION_2, Opcode: z.OP_TOKEN_ORDER, Operand: operand}
}

func mustPacketData(instr z.Instruction) []byte {
	data, err := z.EncodeZkgmPacket(z.ZkgmPacket{Path: u256.Zero(), Instruction: instr})
	if err != nil {
		panic(err)
	}
	return data
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
// [SCENARIO] 1. Register a local grc20 token and mint 40 units to the user
// [INFO] registered grc20 denom: gno.land/r/onbloc/ibc/scenario/union/receive.grc20-partial
// [INFO] user grc20 balance: 40
// [EXPECTED] user grc20 balance should be 40 (freshly minted)
//
// [SCENARIO] 2. Bootstrap IBC host and open client/connection/channel
// [INFO] handshake opened: client=1 connection=1 channel=1
// [EXPECTED] client should be 1
// [EXPECTED] connection should be 1
// [EXPECTED] channel should be 1
//
// [SCENARIO] 3. Lock 40 grc20 units into proxy escrow (user ESCROW send, pulled via TransferFrom)
// [INFO] proxy grc20 escrow balance: 40
// [INFO] user grc20 balance: 0
// [EXPECTED] proxy grc20 escrow balance should be 40 (locked)
// [EXPECTED] user grc20 balance should be 0 (still escrowed)
//
// [SCENARIO] 4. Receive UNESCROW order: release 25 grc20 units from escrow to the receiver
// [INFO] proxy grc20 escrow balance: 15
// [INFO] receiver grc20 balance: 25
// [EXPECTED] proxy grc20 escrow balance should be 15 (40 - 25 released)
// [EXPECTED] receiver grc20 balance should be 25 (units returned to the receiver)
