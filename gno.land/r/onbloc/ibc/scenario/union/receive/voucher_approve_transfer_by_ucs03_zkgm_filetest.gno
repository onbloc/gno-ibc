// PKGPATH: gno.land/r/onbloc/ibc/scenario/union/receive
package receive

// voucher_approve_transfer_by_ucs03_zkgm_filetest walks a wrapped voucher from
// mint (INITIALIZE recv) through the new self-service GRC20 surface: the
// receiving holder grants a third party (spender) an allowance through
// zkgm.VoucherApprove, and that spender then pulls the approved amount via the
// standard GRC20 TransferFrom path (grc20reg + Token.CallerTeller), the same
// composability path a DeFi protocol like Gnoswap would use, with no
// zkgm-specific transfer-from wrapper involved.

import (
	"strings"
	"testing"

	"gno.land/p/nt/ufmt/v0"
	"gno.land/p/onbloc/ibc/union/lightclient"
	types "gno.land/p/onbloc/ibc/union/types"
	z "gno.land/p/onbloc/ibc/union/zkgm"

	"gno.land/p/demo/tokens/grc20"
	u256 "gno.land/p/gnoswap/uint256"

	"gno.land/r/demo/defi/grc20reg"
	"gno.land/r/onbloc/ibc/union/access"
	zkgm "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm"
	_ "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/v1" // install zkgm v1 impl (init registers the constructor)
	"gno.land/r/onbloc/ibc/union/core"
	_ "gno.land/r/onbloc/ibc/union/core/v1"
)

const (
	coreImplPath = "gno.land/r/onbloc/ibc/union/core/v1"
	zkgmImplPath = "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/v1"

	adminAddr      = address("g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5")
	holderAddr     = address("g1wymu47drhr0kuq2098m792lytgtj2nyx77yrsm")
	spenderAddr    = address("g1dyxy88p94acjnm8dmu9tfj2mv2ncvx83cagllu")
	mockClientType = types.ClientType("scenario-mock-lc")
)

func main(cur realm) {
	println("[SCENARIO] 1. Bootstrap IBC host and open client/connection/channel")
	channelId := bootstrap(cur)
	println("")

	// The wrapped denom is deterministic for (path=0, channel, base=ugnot, image),
	// so it is derived once here and reused by the recv funding and the
	// approve/transfer steps below.
	meta := mustTokenMetadata("grc20", z.TokenInitializer{Name: "Gno Token", Symbol: "GNOT", Decimals: 6})
	quoteToken := z.PredictWrappedTokenV2(u256.Zero(), uint32(channelId), []byte("ugnot"), z.MetadataImage(mustDecodeMeta(meta)))

	println("[SCENARIO] 2. Receive INITIALIZE order: mint 100 wrapped voucher to holder")
	receiveInitializeOrder(cur, channelId, quoteToken, meta)
	println("")

	println("[SCENARIO] 3. Holder approves a third party (spender) for 40")
	approveSpender(cur, quoteToken)
	println("")

	println("[SCENARIO] 4. Spender pulls the approved 40 via GRC20 TransferFrom")
	spenderPullsApproved(cur, quoteToken)
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
// voucher and mints its full amount to the holder.
func receiveInitializeOrder(cur realm, channelId types.ChannelId, quoteToken string, meta []byte) {
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

	ufmt.Printf("[INFO] minted token (wrapped voucher): %s\n", quoteToken)
	ufmt.Printf("[INFO] holder balance: %d\n", zkgm.VoucherBalanceOf(quoteToken, holderAddr))
	ufmt.Println("[EXPECTED] minted token should be the ibc/ wrapped voucher of base ugnot")
	ufmt.Println("[EXPECTED] holder balance should be 100 (full INITIALIZE amount minted)")
}

// approveSpender lets the holder grant the spender a 40 allowance through the
// new zkgm.VoucherApprove entrypoint.
func approveSpender(cur realm, quoteToken string) {
	testing.SetRealm(testing.NewUserRealm(holderAddr))
	zkgm.VoucherApprove(cross(cur), quoteToken, spenderAddr, 40)

	token := voucherToken(quoteToken)
	ufmt.Printf("[INFO] allowance granted to spender: %d\n", token.Allowance(holderAddr, spenderAddr))
	ufmt.Println("[EXPECTED] allowance should be 40")
}

// spenderPullsApproved lets the spender pull the approved 40 from the holder's
// balance via the voucher token's standard GRC20 CallerTeller, exactly the way
// an external DeFi protocol would consume the allowance.
func spenderPullsApproved(cur realm, quoteToken string) {
	token := voucherToken(quoteToken)

	testing.SetRealm(testing.NewUserRealm(spenderAddr))
	if err := transferFromAsCaller(cross(cur), token, holderAddr, spenderAddr, 40); err != nil {
		panic(err)
	}

	ufmt.Printf("[INFO] holder balance: %d\n", zkgm.VoucherBalanceOf(quoteToken, holderAddr))
	ufmt.Printf("[INFO] spender balance: %d\n", zkgm.VoucherBalanceOf(quoteToken, spenderAddr))
	ufmt.Printf("[INFO] remaining allowance: %d\n", token.Allowance(holderAddr, spenderAddr))
	ufmt.Println("[EXPECTED] holder balance should be 60 (100 - 40 pulled)")
	ufmt.Println("[EXPECTED] spender balance should be 40 (pulled via approved allowance)")
	ufmt.Println("[EXPECTED] remaining allowance should be 0 (fully spent)")
}

// transferFromAsCaller is a crossing shim: fnTeller.TransferFrom resolves the
// spender as rlm.Previous().Address(), which requires a fresh cross(cur) right
// at this call (a stale, many-times-passed cur fails with "cannot seek beyond
// origin caller override"). Callers drive the identity via
// testing.SetRealm(testing.NewUserRealm(spender)) immediately before calling
// this with cross(cur), exactly like zkgm.Send's sender resolution.
func transferFromAsCaller(cur realm, token *grc20.Token, owner, to address, amount int64) error {
	return token.CallerTeller().TransferFrom(0, cur, owner, to, amount)
}

// voucherToken resolves the live *grc20.Token for a wrapped voucher through
// grc20reg, keyed the same way getOrCreateVoucher registers it: proxy pkgpath
// + "." + trimmed ibc denom. Registration runs on the proxy's own cur (not the
// impl's), so this key stays stable across impl upgrades.
func voucherToken(quoteToken string) *grc20.Token {
	key := zkgm.ProxyPkgPath() + "." + strings.TrimPrefix(quoteToken, "ibc/")
	return grc20reg.MustGet(key)
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
// [SCENARIO] 2. Receive INITIALIZE order: mint 100 wrapped voucher to holder
// [INFO] minted token (wrapped voucher): ibc/e03a8753fa7f41c282b15cdc0343f660e6e65845
// [INFO] holder balance: 100
// [EXPECTED] minted token should be the ibc/ wrapped voucher of base ugnot
// [EXPECTED] holder balance should be 100 (full INITIALIZE amount minted)
//
// [SCENARIO] 3. Holder approves a third party (spender) for 40
// [INFO] allowance granted to spender: 40
// [EXPECTED] allowance should be 40
//
// [SCENARIO] 4. Spender pulls the approved 40 via GRC20 TransferFrom
// [INFO] holder balance: 60
// [INFO] spender balance: 40
// [INFO] remaining allowance: 0
// [EXPECTED] holder balance should be 60 (100 - 40 pulled)
// [EXPECTED] spender balance should be 40 (pulled via approved allowance)
// [EXPECTED] remaining allowance should be 0 (fully spent)
