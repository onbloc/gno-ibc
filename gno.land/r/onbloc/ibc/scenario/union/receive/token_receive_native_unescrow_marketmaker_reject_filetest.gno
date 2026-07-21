// PKGPATH: gno.land/r/onbloc/ibc/scenario/union/receive
package receive

// token_receive_native_unescrow_marketmaker_reject_filetest is the
// EXCEPTION-path scenario for an under-quoted native UNESCROW recv. When
// BaseAmount < QuoteAmount, executeTokenOrderV2 cannot protocol-fill the
// unescrow and falls back to marketMakerFillV2 — but that fast path only
// works when the quote denom is itself a known local voucher
// (`HasVoucher(quoteDenom)`). A native UNESCROW's quote is the origin native
// denom ("ugnot"), which is never a voucher, so the maker-fill attempt fails
// closed with ACK_ERR_ONLY_MAKER, and OnRecvPacket turns that into a
// terminating panic (core does not recover recv panics) rather than a
// graceful failure ack. The rejection is matched by the // Error: directive.

import (
	"chain"
	"chain/banker"
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
	userAddr       = address("g1wymu47drhr0kuq2098m792lytgtj2nyx77yrsm")
	mockClientType = types.ClientType("scenario-mock-lc")

	// quoteWrapped stands in for the counterparty's wrapped denom. It only keys
	// the channel balance (lock increases it); the recv unescrow path does not
	// re-derive it, so a stable placeholder is enough.
	quoteWrapped = "remote-wrapped-ugnot"
)

func main(cur realm) {
	println("[SCENARIO] 1. Bootstrap IBC host and open client/connection/channel")
	channelId := bootstrap(cur)
	println("")

	println("[SCENARIO] 2. Lock 40ugnot into proxy escrow (native ESCROW send funded by attached coins)")
	lockNativeEscrow(cur, channelId)
	println("")

	println("[SCENARIO] 3. Receive an under-quoted UNESCROW order -> maker-fill attempt fails closed and panics")
	receiveUnderQuotedUnescrow(cur, channelId)
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

// lockNativeEscrow locks 40 native ugnot into the proxy escrow via a user ESCROW
// send. IssueCoins reproduces the -send deposit landing at the proxy; SetOriginSend
// reproduces the envelope the impl reads to seed the escrow budget.
func lockNativeEscrow(cur realm, channelId types.ChannelId) {
	order := z.TokenOrderV2{
		Sender:      []byte(userAddr.String()),
		Receiver:    []byte("remote-receiver"),
		BaseToken:   []byte("ugnot"),
		BaseAmount:  u256.NewUint(40),
		QuoteToken:  []byte(quoteWrapped),
		QuoteAmount: u256.NewUint(40),
		Kind:        z.TOKEN_ORDER_KIND_ESCROW,
	}

	proxy := zkgm.ProxyAddress()
	testing.IssueCoins(proxy, chain.NewCoins(chain.NewCoin("ugnot", 40)))
	testing.SetRealm(testing.NewUserRealm(userAddr))
	testing.SetOriginSend(chain.NewCoins(chain.NewCoin("ugnot", 40)))
	_ = zkgm.Send(cross(cur), channelId, types.Timestamp(1<<62), [32]byte{}, mustOrderInstruction(order))

	bk := banker.NewReadonlyBanker()
	ufmt.Printf("[INFO] proxy native escrow balance: %d\n", bk.GetCoins(proxy).AmountOf("ugnot"))
	ufmt.Println("[EXPECTED] proxy native escrow balance should be 40 (locked)")
}

// receiveUnderQuotedUnescrow receives an UNESCROW order whose BaseAmount (10) is
// less than its QuoteAmount (40). executeTokenOrderV2 cannot protocol-fill an
// under-quoted order, so it falls back to marketMakerFillV2 — which fails
// closed here because the quote denom ("ugnot") is native, never a registered
// voucher. The resulting ACK_ERR_ONLY_MAKER makes OnRecvPacket panic.
func receiveUnderQuotedUnescrow(cur realm, channelId types.ChannelId) {
	order := z.TokenOrderV2{
		Sender:      []byte("remote-sender"),
		Receiver:    []byte(userAddr.String()),
		BaseToken:   []byte(quoteWrapped),
		BaseAmount:  u256.NewUint(10),
		QuoteToken:  []byte("ugnot"),
		QuoteAmount: u256.NewUint(40),
		Kind:        z.TOKEN_ORDER_KIND_UNESCROW,
	}
	packet := core.NewPacket(types.ChannelId(2), channelId, mustPacketData(mustOrderInstruction(order)), types.Timestamp(1<<62))

	ufmt.Printf("[INFO] order BaseAmount=%d, QuoteAmount=%d (under-quoted: base < quote)\n", 10, 40)
	ufmt.Println("[INFO] quote_token is the native denom itself: ugnot")
	ufmt.Println("[INFO] protocolFillUnescrowV2 needs baseCovers=true, so this falls back to marketMakerFillV2")
	ufmt.Println("[INFO] marketMakerFillV2 requires the quote denom to be a registered voucher (HasVoucher)")
	ufmt.Println("[INFO] native ugnot is never a voucher, so the maker-fill attempt fails closed (ACK_ERR_ONLY_MAKER)")
	ufmt.Println("[EXPECTED] OnRecvPacket should panic on the only-maker ack instead of returning a graceful failure ack")

	testing.SetRealm(testing.NewUserRealm(adminAddr))
	core.PacketRecv(cross(cur), core.NewMsgPacketRecv([]types.Packet{packet}, [][]byte{nil}, nil, 1))
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
// [SCENARIO] 1. Bootstrap IBC host and open client/connection/channel
// [INFO] handshake opened: client=1 connection=1 channel=1
// [EXPECTED] client should be 1
// [EXPECTED] connection should be 1
// [EXPECTED] channel should be 1
//
// [SCENARIO] 2. Lock 40ugnot into proxy escrow (native ESCROW send funded by attached coins)
// [INFO] proxy native escrow balance: 40
// [EXPECTED] proxy native escrow balance should be 40 (locked)
//
// [SCENARIO] 3. Receive an under-quoted UNESCROW order -> maker-fill attempt fails closed and panics
// [INFO] order BaseAmount=10, QuoteAmount=40 (under-quoted: base < quote)
// [INFO] quote_token is the native denom itself: ugnot
// [INFO] protocolFillUnescrowV2 needs baseCovers=true, so this falls back to marketMakerFillV2
// [INFO] marketMakerFillV2 requires the quote denom to be a registered voucher (HasVoucher)
// [INFO] native ugnot is never a voucher, so the maker-fill attempt fails closed (ACK_ERR_ONLY_MAKER)
// [EXPECTED] OnRecvPacket should panic on the only-maker ack instead of returning a graceful failure ack

// Error:
// is only maker ack
