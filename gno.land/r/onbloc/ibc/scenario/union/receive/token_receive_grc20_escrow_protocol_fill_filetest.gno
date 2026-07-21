// PKGPATH: gno.land/r/onbloc/ibc/scenario/union/receive
package receive

// token_receive_grc20_escrow_protocol_fill_filetest is the grc20-origin
// counterpart to token_receive_native_escrow_protocol_fill_filetest. ESCROW
// can only protocol-fill an already-deployed voucher (an ESCROW matching a
// not-yet-deployed wrapped denom is rejected as an orphan), so this file
// first deploys it via a protocol-fill INITIALIZE recv before exercising the
// ESCROW mint itself. executeTokenOrderV2's mint path never branches on
// whether BaseToken is native or grc20, so this is expected to behave
// identically to the native ESCROW file, just with a grc20-shaped BaseToken.

import (
	"testing"

	"gno.land/p/nt/ufmt/v0"
	"gno.land/p/onbloc/ibc/union/lightclient"
	types "gno.land/p/onbloc/ibc/union/types"
	z "gno.land/p/onbloc/ibc/union/zkgm"

	u256 "gno.land/p/gnoswap/uint256"

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
	receiverAAddr  = address("g1dyxy88p94acjnm8dmu9tfj2mv2ncvx83cagllu")
	receiverBAddr  = address("g1wymu47drhr0kuq2098m792lytgtj2nyx77yrsm")
	mockClientType = types.ClientType("scenario-mock-lc")

	// remoteGRC20Denom stands in for a grc20 token registered on the remote
	// (origin) chain — this chain never registers it locally; it is only used
	// as the BaseToken string for the wrapped-address prediction.
	remoteGRC20Denom = "gno.land/r/remote/defi/tokens.usdc"
)

func main(cur realm) {
	println("[SCENARIO] 1. Bootstrap IBC host and open client/connection/channel")
	channelId := bootstrap(cur)
	println("")

	meta := mustTokenMetadata("grc20", z.TokenInitializer{Name: "USD Coin", Symbol: "USDC", Decimals: 6})
	quoteToken := z.PredictWrappedTokenV2(u256.Zero(), uint32(channelId), []byte(remoteGRC20Denom), z.MetadataImage(mustDecodeMeta(meta)))

	println("[SCENARIO] 2. Deploy the wrapped token via a protocol-fill INITIALIZE recv (mint 100 to receiver A)")
	receiveInitializeOrder(cur, channelId, quoteToken, meta)
	println("")

	println("[SCENARIO] 3. Receive ESCROW order: mint 50 more of the same wrapped token to receiver B")
	receiveEscrowOrder(cur, channelId, quoteToken)
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

// receiveInitializeOrder receives an INITIALIZE TokenOrder that deploys the wrapped
// voucher and mints its full amount to receiver A. This is setup for step 3: an
// ESCROW recv would be rejected as an orphan if no voucher exists yet.
func receiveInitializeOrder(cur realm, channelId types.ChannelId, quoteToken string, meta []byte) {
	order := z.TokenOrderV2{
		Sender:      []byte("remote-sender"),
		Receiver:    []byte(receiverAAddr.String()),
		BaseToken:   []byte(remoteGRC20Denom),
		BaseAmount:  u256.NewUint(100),
		QuoteToken:  []byte(quoteToken),
		QuoteAmount: u256.NewUint(100),
		Kind:        z.TOKEN_ORDER_KIND_INITIALIZE,
		Metadata:    meta,
	}
	packet := core.NewPacket(types.ChannelId(2), channelId, mustPacketData(mustOrderInstruction(order)), types.Timestamp(1<<62))

	testing.SetRealm(testing.NewUserRealm(adminAddr))
	core.PacketRecv(cross(cur), core.NewMsgPacketRecv([]types.Packet{packet}, [][]byte{nil}, nil, 1))

	ufmt.Printf("[INFO] receiver A balance: %d\n", zkgm.VoucherBalanceOf(quoteToken, receiverAAddr))
	ufmt.Println("[EXPECTED] receiver A balance should be 100 (full INITIALIZE amount minted)")
}

// receiveEscrowOrder receives an ESCROW TokenOrder for the same asset and mints to
// receiver B, leaving receiver A's balance untouched.
func receiveEscrowOrder(cur realm, channelId types.ChannelId, quoteToken string) {
	order := z.TokenOrderV2{
		Sender:      []byte("remote-sender"),
		Receiver:    []byte(receiverBAddr.String()),
		BaseToken:   []byte(remoteGRC20Denom),
		BaseAmount:  u256.NewUint(50),
		QuoteToken:  []byte(quoteToken),
		QuoteAmount: u256.NewUint(50),
		Kind:        z.TOKEN_ORDER_KIND_ESCROW,
	}
	packet := core.NewPacket(types.ChannelId(2), channelId, mustPacketData(mustOrderInstruction(order)), types.Timestamp(1<<62))

	testing.SetRealm(testing.NewUserRealm(adminAddr))
	core.PacketRecv(cross(cur), core.NewMsgPacketRecv([]types.Packet{packet}, [][]byte{nil}, nil, 1))

	ufmt.Printf("[INFO] minted token (same wrapped voucher): %s\n", quoteToken)
	ufmt.Printf("[INFO] receiver B balance: %d\n", zkgm.VoucherBalanceOf(quoteToken, receiverBAddr))
	ufmt.Printf("[INFO] receiver A balance (unchanged): %d\n", zkgm.VoucherBalanceOf(quoteToken, receiverAAddr))
	ufmt.Println("[INFO] ESCROW recv only mints the wrapped voucher; it never locks anything on this chain")
	ufmt.Println("[INFO] the actual lock happens on the sending chain's send-side verifyTokenOrderV2, not here")
	ufmt.Println("[EXPECTED] minted token should be the same ibc/ voucher as the INITIALIZE deploy")
	ufmt.Println("[EXPECTED] receiver B balance should be 50 (ESCROW amount minted)")
	ufmt.Println("[EXPECTED] receiver A balance should be 100 (unchanged by the ESCROW recv)")
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

func mustDecodeMeta(bz []byte) z.TokenMetadata {
	meta, err := z.DecodeTokenMetadata(bz)
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
// [SCENARIO] 1. Bootstrap IBC host and open client/connection/channel
// [INFO] handshake opened: client=1 connection=1 channel=1
// [EXPECTED] client should be 1
// [EXPECTED] connection should be 1
// [EXPECTED] channel should be 1
//
// [SCENARIO] 2. Deploy the wrapped token via a protocol-fill INITIALIZE recv (mint 100 to receiver A)
// [INFO] receiver A balance: 100
// [EXPECTED] receiver A balance should be 100 (full INITIALIZE amount minted)
//
// [SCENARIO] 3. Receive ESCROW order: mint 50 more of the same wrapped token to receiver B
// [INFO] minted token (same wrapped voucher): ibc/4a81a4323d82364ff986ffbf8d8322795a93fbfb
// [INFO] receiver B balance: 50
// [INFO] receiver A balance (unchanged): 100
// [INFO] ESCROW recv only mints the wrapped voucher; it never locks anything on this chain
// [INFO] the actual lock happens on the sending chain's send-side verifyTokenOrderV2, not here
// [EXPECTED] minted token should be the same ibc/ voucher as the INITIALIZE deploy
// [EXPECTED] receiver B balance should be 50 (ESCROW amount minted)
// [EXPECTED] receiver A balance should be 100 (unchanged by the ESCROW recv)
