// PKGPATH: gno.land/r/onbloc/ibc/scenario/union/send
package send

// token_send_voucher_with_decimal_trim_filetest walks a token send for an
// 18-decimal voucher through the upgradeable union IBC host (permissive mock light
// client). The sender is first funded with the voucher via an INITIALIZE recv,
// whose 18-decimal wire amount is trimmed to the canonical 6-decimal ledger. On the
// outbound ESCROW send the order carries the 18-decimal wire amount; the impl
// downscales it to the 6-decimal ledger for escrow while the packet keeps the full
// wire precision.

import (
	"encoding/hex"
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
	senderAddr     = address("g1wymu47drhr0kuq2098m792lytgtj2nyx77yrsm")
	mockClientType = types.ClientType("scenario-mock-lc")

	// wireAmount is the 18-decimal wire value carried on the packet; ledgerAmount is
	// its canonical 6-decimal ledger value (wireAmount / 10^12).
	wireAmount   = uint64(123456000000000000)
	ledgerAmount = uint64(123456)
)

func main(cur realm) {
	println("[SCENARIO] 1. Bootstrap IBC host and open client/connection/channel")
	channelId := bootstrap(cur)
	println("")

	// The wrapped denom is deterministic for (path=0, channel, base=uatom, image),
	// so it is derived once here and reused by the recv funding and the send below.
	meta := mustTokenMetadata("af739f34ddf951cbc24fdbba4f76213688e13627", z.TokenInitializer{Name: "USD Coin", Symbol: "USDC", Decimals: 18})
	quoteToken := z.PredictWrappedTokenV2(u256.Zero(), uint32(channelId), []byte("uatom"), z.MetadataImage(mustDecodeMeta(meta)))

	println("[SCENARIO] 2. Fund sender with an 18-decimal voucher via INITIALIZE recv (wire amount trimmed to ledger)")
	fundSenderViaInitialize(cur, channelId, quoteToken, meta)
	println("")

	println("[SCENARIO] 3. Send ESCROW order carrying the 18-decimal wire amount (downscaled to the ledger for escrow)")
	sendEscrowOrder(cur, channelId, quoteToken)
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

// fundSenderViaInitialize mints the 18-decimal voucher to the sender by receiving
// an INITIALIZE TokenOrder addressed to it. The 18-decimal wire amount is trimmed
// to the canonical 6-decimal ledger value on mint.
func fundSenderViaInitialize(cur realm, channelId types.ChannelId, quoteToken string, meta []byte) {
	order := z.TokenOrderV2{
		Sender:      []byte("remote-sender"),
		Receiver:    []byte(senderAddr.String()),
		BaseToken:   []byte("uatom"),
		BaseAmount:  u256.NewUint(wireAmount),
		QuoteToken:  []byte(quoteToken),
		QuoteAmount: u256.NewUint(wireAmount),
		Kind:        z.TOKEN_ORDER_KIND_INITIALIZE,
		Metadata:    meta,
	}
	packet := core.NewPacket(types.ChannelId(2), channelId, mustPacketData(mustOrderInstruction(order)), types.Timestamp(1<<62))

	testing.SetRealm(testing.NewUserRealm(adminAddr))
	core.PacketRecv(cross(cur), core.NewMsgPacketRecv([]types.Packet{packet}, [][]byte{nil}, nil, 1))

	ufmt.Printf("[INFO] minted 18-decimal voucher: %s\n", quoteToken)
	ufmt.Printf("[INFO] packet BaseAmount (18-decimal wire): %d\n", wireAmount)
	ufmt.Printf("[INFO] sender %s ledger balance: %d\n", senderAddr.String(), zkgm.VoucherBalanceOf(quoteToken, senderAddr))
	ufmt.Println("[EXPECTED] sender ledger balance should be 123456 (wire / 10^12)")
}

// sendEscrowOrder sends an ESCROW order carrying the 18-decimal wire amount. The
// impl downscales the wire amount to the 6-decimal ledger for escrow, moving the
// voucher from the sender to the proxy, while the outgoing packet keeps the full
// wire precision.
func sendEscrowOrder(cur realm, channelId types.ChannelId, quoteToken string) {
	order := z.TokenOrderV2{
		Sender:      []byte(senderAddr.String()),
		Receiver:    []byte("remote-receiver"),
		BaseToken:   []byte(quoteToken),
		BaseAmount:  u256.NewUint(wireAmount),
		QuoteToken:  []byte(quoteToken),
		QuoteAmount: u256.NewUint(wireAmount),
		Kind:        z.TOKEN_ORDER_KIND_ESCROW,
	}

	ufmt.Printf("[INFO] order BaseAmount to send: %d (18-decimal wire)\n", wireAmount)

	testing.SetRealm(testing.NewUserRealm(senderAddr))
	sendPacket := zkgm.Send(cross(cur), channelId, types.Timestamp(1<<62), [32]byte{}, mustOrderInstruction(order))

	ufmt.Printf("[INFO] sender ledger balance after send: %d\n", zkgm.VoucherBalanceOf(quoteToken, senderAddr))
	ufmt.Println("[EXPECTED] sender ledger balance should be 0")
	ufmt.Printf("[INFO] proxy escrow ledger balance after send: %d\n", zkgm.VoucherBalanceOf(quoteToken, zkgm.ProxyAddress()))
	ufmt.Println("[EXPECTED] proxy escrow ledger balance should be 123456 (wire / 10^12)")

	zkgmPacket, err := z.DecodeZkgmPacket(sendPacket.Data)
	if err != nil {
		panic(err)
	}
	decodedOrder, err := z.DecodeTokenOrderV2(zkgmPacket.Instruction.Operand)
	if err != nil {
		panic(err)
	}
	ufmt.Printf("[INFO] packet BaseAmount (decoded): %d\n", decodedOrder.BaseAmount.Uint64())
	ufmt.Println("[EXPECTED] packet BaseAmount should be 123456000000000000 (full wire precision)")
	ufmt.Printf("[INFO] packet QuoteAmount (decoded): %d\n", decodedOrder.QuoteAmount.Uint64())
	ufmt.Println("[EXPECTED] packet QuoteAmount should be 123456000000000000 (full wire precision)")
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
// [SCENARIO] 2. Fund sender with an 18-decimal voucher via INITIALIZE recv (wire amount trimmed to ledger)
// [INFO] minted 18-decimal voucher: ibc/508ef9face982ec6d26a9d7370e1625abd61c747
// [INFO] packet BaseAmount (18-decimal wire): 123456000000000000
// [INFO] sender g1wymu47drhr0kuq2098m792lytgtj2nyx77yrsm ledger balance: 123456
// [EXPECTED] sender ledger balance should be 123456 (wire / 10^12)
//
// [SCENARIO] 3. Send ESCROW order carrying the 18-decimal wire amount (downscaled to the ledger for escrow)
// [INFO] order BaseAmount to send: 123456000000000000 (18-decimal wire)
// [INFO] sender ledger balance after send: 0
// [EXPECTED] sender ledger balance should be 0
// [INFO] proxy escrow ledger balance after send: 123456
// [EXPECTED] proxy escrow ledger balance should be 123456 (wire / 10^12)
// [INFO] packet BaseAmount (decoded): 123456000000000000
// [EXPECTED] packet BaseAmount should be 123456000000000000 (full wire precision)
// [INFO] packet QuoteAmount (decoded): 123456000000000000
// [EXPECTED] packet QuoteAmount should be 123456000000000000 (full wire precision)
