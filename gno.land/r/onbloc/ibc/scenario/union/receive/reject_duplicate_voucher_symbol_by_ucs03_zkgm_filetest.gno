// PKGPATH: gno.land/r/onbloc/ibc/scenario/union/receive
package receive

// reject_duplicate_voucher_symbol_by_ucs03_zkgm_filetest is the REJECTION-path
// scenario for the grc20reg registry-symbol collision guard. grc20reg keys its
// registry by (registering realm, token symbol); ucs03_zkgm/v1 always registers
// from the same realm, so two different origin denoms that happen to declare
// the same symbol (e.g. USDC bridged from two different chains) collide at the
// registry even though their predicted wrapped-token addresses differ. The
// first INITIALIZE deploys and mints normally; a second INITIALIZE for a
// different base token but the same declared symbol is rejected with a
// controlled failure ack instead of panicking through grc20reg.Register.

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
	receiverAddr   = address("g1dyxy88p94acjnm8dmu9tfj2mv2ncvx83cagllu")
	mockClientType = types.ClientType("scenario-mock-lc")
)

func main(cur realm) {
	println("[SCENARIO] 1. Bootstrap IBC host and open a zkgm channel")
	channelId := bootstrap(cur)
	println("")

	// Two different origin chains' USDC: different base token bytes (so their
	// predicted wrapped-token addresses differ), same declared symbol.
	metaA := mustTokenMetadata("grc20", z.TokenInitializer{Name: "Chain A USDC", Symbol: "USDC", Decimals: 6})
	quoteTokenA := z.PredictWrappedTokenV2(u256.Zero(), uint32(channelId), []byte("usdc-chain-a"), z.MetadataImage(mustDecodeMeta(metaA)))

	println("[SCENARIO] 2. Receive INITIALIZE order from chain A: deploy wrapped USDC and mint 100")
	receiveInitializeOrder(cur, channelId, []byte("usdc-chain-a"), quoteTokenA, metaA, 100)
	ufmt.Printf("[INFO] chain A wrapped balance: %d\n", zkgm.VoucherBalanceOf(quoteTokenA, receiverAddr))
	ufmt.Println("[EXPECTED] chain A balance should be 100 (full INITIALIZE amount minted)")
	println("")

	metaB := mustTokenMetadata("grc20", z.TokenInitializer{Name: "Chain B USDC", Symbol: "USDC", Decimals: 6})
	quoteTokenB := z.PredictWrappedTokenV2(u256.Zero(), uint32(channelId), []byte("usdc-chain-b"), z.MetadataImage(mustDecodeMeta(metaB)))

	println("[SCENARIO] 3. Receive INITIALIZE order from chain B with the same declared symbol: rejected, no mint")
	receiveInitializeOrder(cur, channelId, []byte("usdc-chain-b"), quoteTokenB, metaB, 50)
	ufmt.Printf("[INFO] chain B wrapped balance: %d\n", zkgm.VoucherBalanceOf(quoteTokenB, receiverAddr))
	ufmt.Printf("[INFO] chain A wrapped balance (unaffected): %d\n", zkgm.VoucherBalanceOf(quoteTokenA, receiverAddr))
	ufmt.Println("[EXPECTED] chain B balance should be 0 (mint rejected: duplicate registry symbol)")
	ufmt.Println("[EXPECTED] chain A balance should be 100 (unaffected by the rejected chain B receive)")
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
	return channelId
}

// receiveInitializeOrder receives an INITIALIZE TokenOrder for baseToken. On the
// registry-symbol collision path this returns a failure ack (no mint, no
// panic) rather than aborting the packet recv tx.
func receiveInitializeOrder(cur realm, channelId types.ChannelId, baseToken []byte, quoteToken string, meta []byte, amount uint64) {
	order := z.TokenOrderV2{
		Sender:      []byte("remote-sender"),
		Receiver:    []byte(receiverAddr.String()),
		BaseToken:   baseToken,
		BaseAmount:  u256.NewUint(amount),
		QuoteToken:  []byte(quoteToken),
		QuoteAmount: u256.NewUint(amount),
		Kind:        z.TOKEN_ORDER_KIND_INITIALIZE,
		Metadata:    meta,
	}
	packet := core.NewPacket(types.ChannelId(2), channelId, mustPacketData(mustOrderInstruction(order)), types.Timestamp(1<<62))

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
// [SCENARIO] 1. Bootstrap IBC host and open a zkgm channel
//
// [SCENARIO] 2. Receive INITIALIZE order from chain A: deploy wrapped USDC and mint 100
// [INFO] chain A wrapped balance: 100
// [EXPECTED] chain A balance should be 100 (full INITIALIZE amount minted)
//
// [SCENARIO] 3. Receive INITIALIZE order from chain B with the same declared symbol: rejected, no mint
// [INFO] chain B wrapped balance: 0
// [INFO] chain A wrapped balance (unaffected): 100
// [EXPECTED] chain B balance should be 0 (mint rejected: duplicate registry symbol)
// [EXPECTED] chain A balance should be 100 (unaffected by the rejected chain B receive)
