// PKGPATH: gno.land/r/onbloc/ibc/scenario/union/send
package send

// token_send_grc20_escrow_burn_address_ack_filetest: GRC20 ESCROW send, then a
// market-maker-fill ack naming BURN_ADDRESS. burnEscrowedV2's GRC20_TOKEN case
// (token_order.gno:569-572) is identical to NATIVE_COIN, not IBC_TOKEN: no
// burn capability over a foreign/fixed-supply asset, so it just adds to the
// locked-token ledger — the 40 units stay at the proxy forever, TotalSupply
// unaffected (contrast token_send_voucher_escrow_burn_address_ack_filetest,
// where burnVoucher actually destroys supply). Previously unit-test-only.

import (
	"testing"

	"gno.land/p/demo/tokens/grc20"
	"gno.land/p/nt/ufmt/v0"
	"gno.land/p/onbloc/ibc/union/lightclient"
	"gno.land/p/onbloc/ibc/union/types"
	z "gno.land/p/onbloc/ibc/union/zkgm"

	u256 "gno.land/p/onbloc/math/uint256"

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

	adminAddr        = address("g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5")
	senderAddr       = address("g1wymu47drhr0kuq2098m792lytgtj2nyx77yrsm")
	regularMakerAddr = address("g1dyxy88p94acjnm8dmu9tfj2mv2ncvx83cagllu")
	mockClientType   = types.ClientType("scenario-mock-lc")

	grc20Slug = "grc20-burn-address"
)

func main(cur realm) {
	// grc20.NewToken is a non-crossing (_ int, rlm realm, ...) call: it needs cur
	// to still be this scenario's own ambient frame, so it must run before any
	// testing.SetRealm below reassigns that ambient context to an EOA.
	println("[SCENARIO] 1. Register a local grc20 token and mint 100 units to the sender")
	token, ledger, denom := setupGRC20(cur)
	println("")

	println("[SCENARIO] 2. Bootstrap IBC host and open client/connection/channel")
	channelId := bootstrap(cur)
	println("")

	println("[SCENARIO] 3. Send grc20 ESCROW order locking 40 units (sender pre-approves the proxy; pulled via TransferFrom)")
	sendPacket := sendGRC20EscrowOrder(cur, channelId, token, ledger, denom)
	println("")

	println("[SCENARIO] 4. A market-maker-fill ack naming BURN_ADDRESS locks the escrow forever (no burn mechanism for a foreign grc20)")
	acknowledgeBurnAddressFill(cur, channelId, sendPacket, token, denom)
}

func setupGRC20(cur realm) (*grc20.Token, *grc20.PrivateLedger, string) {
	token, ledger := grc20.NewToken("Scenario GRC20", "SCN", 6, 0, cur)
	denom := grc20reg.Register(cross(cur), token, grc20Slug)

	if err := ledger.Mint(senderAddr, 100); err != nil {
		panic(err)
	}

	ufmt.Printf("[INFO] registered grc20 denom: %s\n", denom)
	ufmt.Printf("[INFO] sender grc20 balance: %d\n", token.BalanceOf(senderAddr))
	ufmt.Println("[EXPECTED] sender grc20 balance should be 100 (freshly minted)")

	return token, ledger, denom
}

// bootstrap installs the core/zkgm impls, grants the admin the relayer role, and
// opens a client/connection/channel backed by the permissive mock light client.
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
// in production the sender submits a separate Approve tx against the token realm;
// Approve here reproduces that pre-authorization — then sends the ESCROW order,
// which pulls the approved amount via TransferFrom.
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

	ufmt.Printf("[INFO] channel balance ledger before send: %s\n", channelBalanceOrZero(channelId, order.BaseToken, order.QuoteToken).ToString())

	testing.SetRealm(testing.NewUserRealm(senderAddr))
	sendPacket := zkgm.Send(cross(cur), channelId, types.Timestamp(1<<62), [32]byte{}, mustOrderInstruction(order))

	ufmt.Printf("[INFO] sender grc20 balance: %d\n", token.BalanceOf(senderAddr))
	ufmt.Printf("[INFO] proxy grc20 escrow balance: %d\n", token.BalanceOf(proxy))
	ufmt.Printf("[INFO] channel balance ledger after send: %s\n", channelBalanceOrZero(channelId, order.BaseToken, order.QuoteToken).ToString())
	ufmt.Println("[EXPECTED] sender grc20 balance should be 60 (100 - 40 escrowed)")
	ufmt.Println("[EXPECTED] proxy grc20 escrow balance should be 40 (locked)")
	ufmt.Println("[EXPECTED] channel balance ledger should be 40 (matches the escrowed order amount)")

	return sendPacket
}

// acknowledgeBurnAddressFill: BURN_ADDRESS market-maker ack. GRC20_TOKEN has
// no burn capability, so the 40 units stay custodied at the proxy forever;
// TotalSupply is unaffected.
func acknowledgeBurnAddressFill(cur realm, channelId types.ChannelId, sendPacket types.Packet, token *grc20.Token, denom string) {
	testing.SetRealm(testing.NewUserRealm(adminAddr))
	core.PacketAcknowledgement(cross(cur), core.NewMsgPacketAcknowledgement([]types.Packet{sendPacket}, [][]byte{mustMakerFillAck(address(z.BURN_ADDRESS))}, nil, 1))

	proxy := zkgm.ProxyAddress()
	locked, lockedErr := zkgm.GetLockedTokenAmount(denom)

	ufmt.Printf("[INFO] proxy grc20 escrow balance: %d\n", token.BalanceOf(proxy))
	ufmt.Printf("[INFO] sender grc20 balance: %d\n", token.BalanceOf(senderAddr))
	ufmt.Printf("[INFO] regular maker grc20 balance: %d\n", token.BalanceOf(regularMakerAddr))
	ufmt.Printf("[INFO] burn address grc20 balance: %d\n", token.BalanceOf(address(z.BURN_ADDRESS)))
	ufmt.Printf("[INFO] deployed token total supply: %d\n", token.TotalSupply())
	ufmt.Printf("[INFO] channel balance ledger after ack: %s\n", channelBalanceOrZero(channelId, []byte(denom), []byte("remote-grc20")).ToString())
	ufmt.Printf("[INFO] locked token ledger amount (err=nil: %t): %s\n", lockedErr == nil, locked.ToString())
	ufmt.Println("[EXPECTED] proxy grc20 escrow balance should still be 40 (permanently locked, not released or burned)")
	ufmt.Println("[EXPECTED] sender grc20 balance should be 60 (unchanged: not refunded)")
	ufmt.Println("[EXPECTED] regular maker grc20 balance should be 0 (never transferred to a maker)")
	ufmt.Println("[EXPECTED] burn address grc20 balance should be 0 (no burn mechanism for a foreign grc20; nothing is ever sent there)")
	ufmt.Println("[EXPECTED] deployed token total supply should be 100 (unchanged: unlike the voucher case, nothing is burned)")
	ufmt.Println("[EXPECTED] channel balance ledger should be 0 (decreased out of channel escrow accounting)")
	ufmt.Println("[EXPECTED] locked token ledger amount should be 40 (moved into the permanently-locked ledger)")
}

// mustMakerFillAck builds a success ack whose inner TokenOrderAck is a
// market-maker fill designating maker as the settlement recipient.
func mustMakerFillAck(maker address) []byte {
	innerAck, err := z.EncodeTokenOrderAck(z.TokenOrderAck{
		FillType:    new(u256.Uint).SetBytes(z.FILL_TYPE_MARKETMAKER[:]),
		MarketMaker: []byte(maker.String()),
	})
	if err != nil {
		panic(err)
	}
	return mustSuccessAck(innerAck)
}

// channelBalanceOrZero: GetChannelBalanceV2 returns "not found" (never
// escrowed) as an error rather than a stored zero; resolve it to u256.Zero().
func channelBalanceOrZero(channelId types.ChannelId, baseToken, quoteToken []byte) *u256.Uint {
	balance, err := zkgm.GetChannelBalanceV2(channelId, u256.Zero(), string(baseToken), quoteToken)
	if err != nil {
		return u256.Zero()
	}
	return balance
}

// --- encoding helpers (pure z calls, mirroring the e2e harness) ---

func mustOrderInstruction(order z.TokenOrderV2) z.Instruction {
	operand, err := z.EncodeTokenOrderV2(order)
	if err != nil {
		panic(err)
	}
	return z.Instruction{Version: z.INSTR_VERSION_2, Opcode: z.OP_TOKEN_ORDER, Operand: operand}
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
// [SCENARIO] 1. Register a local grc20 token and mint 100 units to the sender
// [INFO] registered grc20 denom: gno.land/r/onbloc/ibc/scenario/union/send.SCN
// [INFO] sender grc20 balance: 100
// [EXPECTED] sender grc20 balance should be 100 (freshly minted)
//
// [SCENARIO] 2. Bootstrap IBC host and open client/connection/channel
// [INFO] handshake opened: client=1 connection=1 channel=1
// [EXPECTED] client should be 1
// [EXPECTED] connection should be 1
// [EXPECTED] channel should be 1
//
// [SCENARIO] 3. Send grc20 ESCROW order locking 40 units (sender pre-approves the proxy; pulled via TransferFrom)
// [INFO] channel balance ledger before send: 0
// [INFO] sender grc20 balance: 60
// [INFO] proxy grc20 escrow balance: 40
// [INFO] channel balance ledger after send: 40
// [EXPECTED] sender grc20 balance should be 60 (100 - 40 escrowed)
// [EXPECTED] proxy grc20 escrow balance should be 40 (locked)
// [EXPECTED] channel balance ledger should be 40 (matches the escrowed order amount)
//
// [SCENARIO] 4. A market-maker-fill ack naming BURN_ADDRESS locks the escrow forever (no burn mechanism for a foreign grc20)
// [INFO] proxy grc20 escrow balance: 40
// [INFO] sender grc20 balance: 60
// [INFO] regular maker grc20 balance: 0
// [INFO] burn address grc20 balance: 0
// [INFO] deployed token total supply: 100
// [INFO] channel balance ledger after ack: 0
// [INFO] locked token ledger amount (err=nil: true): 40
// [EXPECTED] proxy grc20 escrow balance should still be 40 (permanently locked, not released or burned)
// [EXPECTED] sender grc20 balance should be 60 (unchanged: not refunded)
// [EXPECTED] regular maker grc20 balance should be 0 (never transferred to a maker)
// [EXPECTED] burn address grc20 balance should be 0 (no burn mechanism for a foreign grc20; nothing is ever sent there)
// [EXPECTED] deployed token total supply should be 100 (unchanged: unlike the voucher case, nothing is burned)
// [EXPECTED] channel balance ledger should be 0 (decreased out of channel escrow accounting)
// [EXPECTED] locked token ledger amount should be 40 (moved into the permanently-locked ledger)
