// PKGPATH: gno.land/r/onbloc/ibc/scenario/union/receive
package receive

// token_receive_voucher_unescrow_marketmaker_fill_filetest: UNESCROW with
// BaseAmount < QuoteAmount can't protocol-fill (baseCovers false), so it
// falls back to marketMakerFillV2. Quote is an already-registered voucher, so
// HasVoucher passes and the maker fronts it — the only UNESCROW path that
// reaches a market-maker success (unregistered quote fails closed instead,
// see token_receive_native_unescrow_marketmaker_reject). This path never
// touches the channel-balance escrow ledger (no outbound ESCROW ever ran for
// this pair), unlike protocolFillUnescrowV2.

import (
	"encoding/hex"
	"testing"

	"gno.land/p/nt/ufmt/v0"
	"gno.land/p/onbloc/ibc/union/lightclient"
	types "gno.land/p/onbloc/ibc/union/types"
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

	adminAddr      = address("g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5")
	makerAddr      = address("g1dyxy88p94acjnm8dmu9tfj2mv2ncvx83cagllu")
	receiverAddr   = address("g1wymu47drhr0kuq2098m792lytgtj2nyx77yrsm")
	mockClientType = types.ClientType("scenario-mock-lc")
)

func main(cur realm) {
	println("[SCENARIO] 1. Bootstrap IBC host and open client/connection/channel")
	channelId := bootstrap(cur)
	println("")

	meta := mustTokenMetadata("af739f34ddf951cbc24fdbba4f76213688e13627", z.TokenInitializer{Name: "Gno Token", Symbol: "GNOT", Decimals: 6})
	quoteToken := z.PredictWrappedTokenV2(u256.Zero(), uint32(channelId), []byte("ugnot"), z.MetadataImage(mustDecodeMeta(meta)))

	println("[SCENARIO] 2. Fund the maker with 100 of the voucher via an INITIALIZE recv (also registers the voucher)")
	fundMaker(cur, channelId, quoteToken, meta)
	println("")

	println("[SCENARIO] 3. Receive an under-quoted UNESCROW order: the maker fronts the quote to the receiver")
	receiveUnderQuotedUnescrow(cur, channelId, quoteToken)
}

// bootstrap installs the core/zkgm impls, grants the admin AND the maker the
// relayer role (the maker submits the recv in step 3, so it must be
// relayer-authorized too), and opens a client/connection/channel backed by the
// permissive mock light client.
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

// fundMaker mints 100 voucher to the maker and registers it, so
// marketMakerFillV2's HasVoucher gate passes below.
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

	token := grc20reg.MustGet(zkgm.ProxyPkgPath() + ".GNOT")
	ufmt.Printf("[INFO] deployed token name/symbol/decimals: %s/%s/%d\n", token.GetName(), token.GetSymbol(), token.GetDecimals())
	ufmt.Printf("[INFO] maker voucher balance: %d\n", zkgm.VoucherBalanceOf(quoteToken, makerAddr))
	ufmt.Println("[EXPECTED] deployed token should be Gno Token/GNOT/6 (voucher registered)")
	ufmt.Println("[EXPECTED] maker voucher balance should be 100")
}

// receiveUnderQuotedUnescrow: BaseAmount(5) < QuoteAmount(20), so it falls
// back to marketMakerFillV2 and the maker (submitting this recv) fronts the
// quote from its own balance. Proxy stays untouched throughout.
func receiveUnderQuotedUnescrow(cur realm, channelId types.ChannelId, quoteToken string) {
	proxy := zkgm.ProxyAddress()
	ufmt.Printf("[INFO] proxy voucher balance before recv: %d\n", zkgm.VoucherBalanceOf(quoteToken, proxy))
	ufmt.Printf("[INFO] channel balance before recv: %s\n", channelBalanceOrZero(channelId, quoteToken).ToString())

	order := z.TokenOrderV2{
		Sender:      []byte("remote-sender"),
		Receiver:    []byte(receiverAddr.String()),
		BaseToken:   []byte("remote-wrapped-ugnot"),
		BaseAmount:  u256.NewUint(5),
		QuoteToken:  []byte(quoteToken),
		QuoteAmount: u256.NewUint(20),
		Kind:        z.TOKEN_ORDER_KIND_UNESCROW,
	}
	packet := core.NewPacket(types.ChannelId(2), channelId, mustPacketData(mustOrderInstruction(order)), types.Timestamp(1<<62))

	ufmt.Printf("[INFO] order BaseAmount=%d, QuoteAmount=%d (under-quoted: base < quote)\n", 5, 20)

	testing.SetRealm(testing.NewUserRealm(makerAddr))
	core.PacketRecv(cross(cur), core.NewMsgPacketRecv([]types.Packet{packet}, [][]byte{nil}, nil, 1))

	ufmt.Printf("[INFO] maker voucher balance: %d\n", zkgm.VoucherBalanceOf(quoteToken, makerAddr))
	ufmt.Printf("[INFO] receiver voucher balance: %d\n", zkgm.VoucherBalanceOf(quoteToken, receiverAddr))
	ufmt.Printf("[INFO] proxy voucher balance after recv: %d\n", zkgm.VoucherBalanceOf(quoteToken, proxy))
	ufmt.Printf("[INFO] channel balance after recv: %s\n", channelBalanceOrZero(channelId, quoteToken).ToString())
	ufmt.Println("[EXPECTED] maker voucher balance should be 80 (100 - 20 fronted to the receiver)")
	ufmt.Println("[EXPECTED] receiver voucher balance should be 20 (fronted by the maker, not unescrowed from the proxy)")
	ufmt.Println("[EXPECTED] proxy voucher balance should stay 0 (market-maker fill never touches proxy escrow)")
	ufmt.Println("[EXPECTED] channel balance should stay 0 (marketMakerFillV2 never calls increase/decreaseChannelBalanceV2)")
}

// channelBalanceOrZero: GetChannelBalanceV2 returns "not found" (never
// escrowed) as an error rather than a stored zero; resolve it to u256.Zero().
func channelBalanceOrZero(channelId types.ChannelId, quoteToken string) *u256.Uint {
	balance, err := zkgm.GetChannelBalanceV2(channelId, u256.Zero(), quoteToken, []byte("remote-wrapped-ugnot"))
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

func mustPacketData(instr z.Instruction) []byte {
	data, err := z.EncodeZkgmPacket(z.ZkgmPacket{Path: u256.Zero(), Instruction: instr})
	if err != nil {
		panic(err)
	}
	return data
}

func mustTokenMetadata(implementationHex string, ti z.TokenInitializer) []byte {
	implementation, err := hex.DecodeString(implementationHex)
	if err != nil {
		panic(err)
	}
	initBytes, err := z.EncodeTokenInitializer(ti)
	if err != nil {
		panic(err)
	}
	meta, err := z.EncodeTokenMetadata(z.TokenMetadata{Implementation: implementation, Initializer: initBytes})
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
// [SCENARIO] 2. Fund the maker with 100 of the voucher via an INITIALIZE recv (also registers the voucher)
// [INFO] deployed token name/symbol/decimals: Gno Token/GNOT/6
// [INFO] maker voucher balance: 100
// [EXPECTED] deployed token should be Gno Token/GNOT/6 (voucher registered)
// [EXPECTED] maker voucher balance should be 100
//
// [SCENARIO] 3. Receive an under-quoted UNESCROW order: the maker fronts the quote to the receiver
// [INFO] proxy voucher balance before recv: 0
// [INFO] channel balance before recv: 0
// [INFO] order BaseAmount=5, QuoteAmount=20 (under-quoted: base < quote)
// [INFO] maker voucher balance: 80
// [INFO] receiver voucher balance: 20
// [INFO] proxy voucher balance after recv: 0
// [INFO] channel balance after recv: 0
// [EXPECTED] maker voucher balance should be 80 (100 - 20 fronted to the receiver)
// [EXPECTED] receiver voucher balance should be 20 (fronted by the maker, not unescrowed from the proxy)
// [EXPECTED] proxy voucher balance should stay 0 (market-maker fill never touches proxy escrow)
// [EXPECTED] channel balance should stay 0 (marketMakerFillV2 never calls increase/decreaseChannelBalanceV2)
