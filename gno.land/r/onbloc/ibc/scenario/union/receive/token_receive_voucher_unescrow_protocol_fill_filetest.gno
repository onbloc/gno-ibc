// PKGPATH: gno.land/r/onbloc/ibc/scenario/union/receive
package receive

// token_receive_voucher_unescrow_protocol_fill_filetest exercises the
// voucher release path on receive — the counterpart to
// release_native_coin/release_grc20_token, but for a voucher BaseToken
// instead of a native or grc20 origin. It first funds a holder with a
// voucher via an INITIALIZE recv, has the holder ESCROW-send it onward
// (locking it in the proxy escrow via transferVoucher, holder -> proxy),
// then receives an UNESCROW packet that releases it back to a receiver.
// getTokenType detects the voucher denom as IBC_TOKEN, so
// localTokenUnescrow routes through transferVoucher (proxy -> receiver)
// rather than the banker (native) or a plain Transfer (grc20).

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
	holderAddr     = address("g1wymu47drhr0kuq2098m792lytgtj2nyx77yrsm")
	receiverAddr   = address("g1dyxy88p94acjnm8dmu9tfj2mv2ncvx83cagllu")
	mockClientType = types.ClientType("scenario-mock-lc")
)

func main(cur realm) {
	println("[SCENARIO] 1. Bootstrap IBC host and open client/connection/channel")
	channelId := bootstrap(cur)
	println("")

	meta := mustTokenMetadata("grc20", z.TokenInitializer{Name: "Gno Token", Symbol: "GNOT", Decimals: 6})
	quoteToken := z.PredictWrappedTokenV2(u256.Zero(), uint32(channelId), []byte("ugnot"), z.MetadataImage(mustDecodeMeta(meta)))

	println("[SCENARIO] 2. Fund the holder with 100 of the voucher via an INITIALIZE recv")
	fundHolder(cur, channelId, quoteToken, meta)
	println("")

	println("[SCENARIO] 3. Holder ESCROW-sends 40 of the voucher onward (locked in proxy escrow via transferVoucher)")
	lockVoucherEscrow(cur, channelId, quoteToken)
	println("")

	println("[SCENARIO] 4. Receive UNESCROW order: release 40 of the voucher from escrow to the receiver")
	receiveUnescrowOrder(cur, channelId, quoteToken)
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

// fundHolder mints 100 of the wrapped voucher to the holder via a normal
// protocol-fill INITIALIZE recv, so the holder has a real voucher balance to
// escrow-send in step 3.
func fundHolder(cur realm, channelId types.ChannelId, quoteToken string, meta []byte) {
	order := z.TokenOrderV2{
		Sender:      []byte("remote-sender"),
		Receiver:    []byte(holderAddr.String()),
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

	ufmt.Printf("[INFO] holder voucher balance: %d\n", zkgm.VoucherBalanceOf(quoteToken, holderAddr))
	ufmt.Println("[EXPECTED] holder voucher balance should be 100")
}

// lockVoucherEscrow has the holder send an ESCROW order for 40 of the voucher
// it already holds. Because getTokenType detects the BaseToken as an IBC
// voucher (not native or grc20), localTokenEscrow locks it via
// transferVoucher (holder -> proxy) rather than the banker or a plain
// Transfer.
func lockVoucherEscrow(cur realm, channelId types.ChannelId, quoteToken string) {
	order := z.TokenOrderV2{
		Sender:      []byte(holderAddr.String()),
		Receiver:    []byte("remote-receiver"),
		BaseToken:   []byte(quoteToken),
		BaseAmount:  u256.NewUint(40),
		QuoteToken:  []byte("remote-wrapped-ugnot"),
		QuoteAmount: u256.NewUint(40),
		Kind:        z.TOKEN_ORDER_KIND_ESCROW,
	}

	testing.SetRealm(testing.NewUserRealm(holderAddr))
	_ = zkgm.Send(cross(cur), channelId, types.Timestamp(1<<62), [32]byte{}, mustOrderInstruction(order))

	proxy := zkgm.ProxyAddress()
	ufmt.Printf("[INFO] proxy voucher escrow balance: %d\n", zkgm.VoucherBalanceOf(quoteToken, proxy))
	ufmt.Printf("[INFO] holder voucher balance: %d\n", zkgm.VoucherBalanceOf(quoteToken, holderAddr))
	ufmt.Println("[EXPECTED] proxy voucher escrow balance should be 40 (locked)")
	ufmt.Println("[EXPECTED] holder voucher balance should be 60 (100 - 40 escrowed)")
}

// receiveUnescrowOrder receives an UNESCROW order that releases the escrowed
// voucher from the proxy back to a receiver via transferVoucher.
func receiveUnescrowOrder(cur realm, channelId types.ChannelId, quoteToken string) {
	order := z.TokenOrderV2{
		Sender:      []byte("remote-sender"),
		Receiver:    []byte(receiverAddr.String()),
		BaseToken:   []byte("remote-wrapped-ugnot"),
		BaseAmount:  u256.NewUint(40),
		QuoteToken:  []byte(quoteToken),
		QuoteAmount: u256.NewUint(40),
		Kind:        z.TOKEN_ORDER_KIND_UNESCROW,
	}
	packet := core.NewPacket(types.ChannelId(2), channelId, mustPacketData(mustOrderInstruction(order)), types.Timestamp(1<<62))

	testing.SetRealm(testing.NewUserRealm(adminAddr))
	core.PacketRecv(cross(cur), core.NewMsgPacketRecv([]types.Packet{packet}, [][]byte{nil}, nil, 1))

	proxy := zkgm.ProxyAddress()
	ufmt.Printf("[INFO] proxy voucher escrow balance: %d\n", zkgm.VoucherBalanceOf(quoteToken, proxy))
	ufmt.Printf("[INFO] receiver voucher balance: %d\n", zkgm.VoucherBalanceOf(quoteToken, receiverAddr))
	ufmt.Println("[EXPECTED] proxy voucher escrow balance should be 0 (released)")
	ufmt.Println("[EXPECTED] receiver voucher balance should be 40 (voucher returned via transferVoucher)")
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
// [SCENARIO] 2. Fund the holder with 100 of the voucher via an INITIALIZE recv
// [INFO] holder voucher balance: 100
// [EXPECTED] holder voucher balance should be 100
//
// [SCENARIO] 3. Holder ESCROW-sends 40 of the voucher onward (locked in proxy escrow via transferVoucher)
// [INFO] proxy voucher escrow balance: 40
// [INFO] holder voucher balance: 60
// [EXPECTED] proxy voucher escrow balance should be 40 (locked)
// [EXPECTED] holder voucher balance should be 60 (100 - 40 escrowed)
//
// [SCENARIO] 4. Receive UNESCROW order: release 40 of the voucher from escrow to the receiver
// [INFO] proxy voucher escrow balance: 0
// [INFO] receiver voucher balance: 40
// [EXPECTED] proxy voucher escrow balance should be 0 (released)
// [EXPECTED] receiver voucher balance should be 40 (voucher returned via transferVoucher)
