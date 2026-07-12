// PKGPATH: gno.land/r/onbloc/ibc/scenario/union/receive
package receive

// token_receive_solve_marketmaker_fill_filetest receives a Kind=SOLVE
// TokenOrder whose BaseAmount equals its QuoteAmount (fully quoted).
// executeTokenOrderV2 (token_order.gno) special-cases SOLVE before the
// baseCovers/protocol-fill decision is even reached: `if intent ||
// order.Kind == z.TOKEN_ORDER_KIND_SOLVE { return v.marketMakerFillV2(...) }`
// — so unlike ESCROW/INITIALIZE, a SOLVE order is ALWAYS maker-only, even
// when Base == Quote would otherwise let it protocol-fill. The fill still
// requires the quote denom to already be a registered voucher
// (marketMakerFillV2's HasVoucher gate), so this file funds the maker via a
// protocol-fill INITIALIZE first, then receives the SOLVE order as the
// maker itself.

import (
	"testing"

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
	makerAddr      = address("g1dyxy88p94acjnm8dmu9tfj2mv2ncvx83cagllu")
	receiverAddr   = address("g1wymu47drhr0kuq2098m792lytgtj2nyx77yrsm")
	mockClientType = types.ClientType("scenario-mock-lc")
)

func main(cur realm) {
	println("[SCENARIO] 1. Bootstrap IBC host and open client/connection/channel")
	channelId := bootstrap(cur)
	println("")

	meta := mustTokenMetadata("grc20", z.TokenInitializer{Name: "Gno Token", Symbol: "GNOT", Decimals: 6})
	quoteToken := z.PredictWrappedTokenV2(u256.Zero(), uint32(channelId), []byte("ugnot"), z.MetadataImage(mustDecodeMeta(meta)))

	println("[SCENARIO] 2. Fund the maker with 100 of the voucher via a protocol-fill INITIALIZE recv")
	fundMaker(cur, channelId, quoteToken, meta)
	println("")

	println("[SCENARIO] 3. Receive a fully-quoted SOLVE order: still maker-only, never protocol-filled")
	receiveSolveOrder(cur, channelId, quoteToken)
}

// bootstrap installs the core/zkgm impls, grants the admin AND the maker the
// relayer role (the maker submits the recv in step 3, so it must be
// relayer-authorized too), and opens a client/connection/channel backed by the
// permissive mock light client.
func bootstrap(cur realm) types.ChannelId {
	testing.SetRealm(testing.NewUserRealm(adminAddr))
	core.UpdateImpl(cross(cur), coreImplPath)
	zkgm.UpdateImpl(cross(cur), zkgmImplPath)
	zkgm.SetRateLimitDisabled(cross(cur), true)
	zkgm.RegisterCoreApp(cross(cur))
	access.GrantRole(cross(cur), access.RelayerRole, adminAddr)
	access.GrantRole(cross(cur), access.RelayerRole, makerAddr)

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

// fundMaker mints 100 of the wrapped voucher to the maker via a normal
// protocol-fill INITIALIZE recv (deploying the wrapped token), so the maker
// has a real balance to front from in step 3, and the voucher is registered
// for marketMakerFillV2's HasVoucher gate to pass on the SOLVE order.
func fundMaker(cur realm, channelId types.ChannelId, quoteToken string, meta []byte) {
	order := z.TokenOrderV2{
		Sender:      []byte("remote-sender"),
		Receiver:    []byte(makerAddr.String()),
		BaseToken:   []byte("ugnot"),
		BaseAmount:  u256.NewUint(100),
		QuoteToken:  []byte(quoteToken),
		QuoteAmount: u256.NewUint(100),
		Kind:        z.TOKEN_ORDER_KIND_INITIALIZE,
		Metadata:    meta,
	}
	packet := core.NewPacket(types.ChannelId(2), channelId, mustPacketData(mustOrderInstruction(order)), types.Timestamp(1<<62))

	testing.SetRealm(testing.NewUserRealm(adminAddr))
	core.PacketRecv(cross(cur), core.NewMsgPacketRecv([]types.Packet{packet}, [][]byte{nil}, nil, 1))

	token := grc20reg.MustGet(zkgm.ProxyPkgPath() + "." + quoteToken[len("ibc/"):])
	ufmt.Printf("[INFO] deployed token name/symbol/decimals: %s/%s/%d\n", token.GetName(), token.GetSymbol(), token.GetDecimals())
	ufmt.Printf("[INFO] maker voucher balance: %d\n", zkgm.VoucherBalanceOf(quoteToken, makerAddr))
	ufmt.Println("[EXPECTED] deployed token should be Gno Token/GNOT/6 (matches the INITIALIZE metadata)")
	ufmt.Println("[EXPECTED] maker voucher balance should be 100")
}

// receiveSolveOrder receives a Kind=SOLVE order with BaseAmount == QuoteAmount
// (30 == 30). If this were ESCROW or INITIALIZE, baseCovers would be true and
// executeTokenOrderV2 would protocol-fill it (a fresh mint). Because the Kind
// is SOLVE, executeTokenOrderV2 routes straight to marketMakerFillV2 before
// that decision is ever reached, so it is still the maker's own voucher
// balance that funds the receiver, not a new mint.
func receiveSolveOrder(cur realm, channelId types.ChannelId, quoteToken string) {
	order := z.TokenOrderV2{
		Sender:      []byte("remote-sender"),
		Receiver:    []byte(receiverAddr.String()),
		BaseToken:   []byte("ugnot"),
		BaseAmount:  u256.NewUint(30),
		QuoteToken:  []byte(quoteToken),
		QuoteAmount: u256.NewUint(30),
		Kind:        z.TOKEN_ORDER_KIND_SOLVE,
	}
	packet := core.NewPacket(types.ChannelId(2), channelId, mustPacketData(mustOrderInstruction(order)), types.Timestamp(1<<62))

	ufmt.Println("[INFO] order BaseAmount=30, QuoteAmount=30 (fully quoted: base == quote)")
	ufmt.Println("[INFO] SOLVE is forced to marketMakerFillV2 regardless of baseCovers, unlike ESCROW/INITIALIZE")

	testing.SetRealm(testing.NewUserRealm(makerAddr))
	core.PacketRecv(cross(cur), core.NewMsgPacketRecv([]types.Packet{packet}, [][]byte{nil}, nil, 1))

	ufmt.Printf("[INFO] maker voucher balance: %d\n", zkgm.VoucherBalanceOf(quoteToken, makerAddr))
	ufmt.Printf("[INFO] receiver voucher balance: %d\n", zkgm.VoucherBalanceOf(quoteToken, receiverAddr))
	ufmt.Println("[EXPECTED] maker voucher balance should be 70 (100 - 30 fronted to the receiver)")
	ufmt.Println("[EXPECTED] receiver voucher balance should be 30 (fronted by the maker, not protocol-minted)")
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
// [SCENARIO] 2. Fund the maker with 100 of the voucher via a protocol-fill INITIALIZE recv
// [INFO] deployed token name/symbol/decimals: Gno Token/GNOT/6
// [INFO] maker voucher balance: 100
// [EXPECTED] deployed token should be Gno Token/GNOT/6 (matches the INITIALIZE metadata)
// [EXPECTED] maker voucher balance should be 100
//
// [SCENARIO] 3. Receive a fully-quoted SOLVE order: still maker-only, never protocol-filled
// [INFO] order BaseAmount=30, QuoteAmount=30 (fully quoted: base == quote)
// [INFO] SOLVE is forced to marketMakerFillV2 regardless of baseCovers, unlike ESCROW/INITIALIZE
// [INFO] maker voucher balance: 70
// [INFO] receiver voucher balance: 30
// [EXPECTED] maker voucher balance should be 70 (100 - 30 fronted to the receiver)
// [EXPECTED] receiver voucher balance should be 30 (fronted by the maker, not protocol-minted)
