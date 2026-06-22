// PKGPATH: gno.land/r/onbloc/ibc/scenario/union
package union

// STATUS: work-in-progress scaffold (disabled via the .gnoa extension, matching
// token_receive_by_ucs03_zkgm_filetest.gnoa). It already drives the full path up
// to the channel handshake; the remaining blocker is a SYSTEMIC cross-realm
// borrow-rule issue: across the proxy/impl realm boundary, core reads v1-built
// structs (every Emit*, store, and app dispatch) and gno rejects the conversion
// of those externally-stored byte fields ("illegal conversion of readonly or
// externally stored value"). The store + cloneBytes layers are already laundered
// (see core/store.gno cloneChannel and the cloneBytes string round-trips); the
// event-emission and app-dispatch layers along the send/recv/ack path still need
// the same laundering before this can run green. Re-enable by renaming to .gno
// once that boundary work lands.
//
// token_send_by_ucs03_zkgm_filetest walks a full ucs03-zkgm token send through
// the upgradeable union IBC host and asserts the escrowed token stays LOCKED in
// the proxy after the acknowledgement.
//
// Flow:
//  1. bootstrap   — install the core + zkgm impls, register a permissive mock
//                   light client, open a client/connection/channel, register the
//                   zkgm app at its port.
//  2. fund        — recv an INITIALIZE order so the sender holds a wrapped (ibc/)
//                   voucher to send.
//  3. send (lock) — the sender calls zkgm.Send with an ESCROW token order; the
//                   impl moves the voucher from the sender into the proxy escrow.
//  4. ack         — the relayer acknowledges with a protocol-fill success ack;
//                   for an escrow this is a no-op, so the lock must persist.
//
// The lock is read back through grc20reg (vouchers are registered there), which
// is the public surface — the proxy escrow balance is the locked amount.

import (
	"strings"
	"testing"

	"gno.land/p/onbloc/ibc/union/lightclient"
	types "gno.land/p/onbloc/ibc/union/types"
	z "gno.land/p/onbloc/ibc/union/zkgm"

	u256 "gno.land/p/gnoswap/uint256"
	"gno.land/r/demo/defi/grc20reg"

	zkgm "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm"
	impl "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/v1"
	core "gno.land/r/onbloc/ibc/union/core"
	_ "gno.land/r/onbloc/ibc/union/core/v1"
)

const (
	coreImplPath = "gno.land/r/onbloc/ibc/union/core/v1"
	zkgmImplPath = "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/v1"

	adminAddr      = address("g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5")
	senderAddr     = address("g1wymu47drhr0kuq2098m792lytgtj2nyx77yrsm")
	mockClientType = types.ClientType("scenario-mock-lc")
)

func main(cur realm) {
	// --- bootstrap (admin) — kept inline so each core call is a direct origin
	// call: runtime.AssertOriginCall requires <= 2 call frames. ---
	testing.SetRealm(testing.NewUserRealm(adminAddr))
	core.UpdateImpl(cross(cur), coreImplPath)
	zkgm.UpdateImpl(cross(cur), zkgmImplPath)
	zkgm.SetRateLimitDisabled(cross(cur), true)
	zkgm.RegisterCoreApp(cross(cur))

	core.RegisterClient(cross(cur), mockClientType, &mockLightClient{})
	core.CreateClient(cross(cur), core.NewMsgCreateClient(mockClientType, nil, nil))
	clientId := types.ClientId(1)

	core.ConnectionOpenInit(cross(cur), core.NewMsgConnectionOpenInit(clientId, types.ClientId(99)))
	connectionId := types.ConnectionId(1)
	core.ConnectionOpenAck(cross(cur), core.NewMsgConnectionOpenAck(connectionId, types.ConnectionId(77), nil, 1))

	portId := []byte(zkgm.ProxyPkgPath())
	channelId := core.ChannelOpenInit(cross(cur), core.NewMsgChannelOpenInit(portId, portId, connectionId, zkgm.Version, "g1relayer"))
	core.ChannelOpenAck(cross(cur), core.NewMsgChannelOpenAck(channelId, zkgm.Version, types.ChannelId(2), nil, 1, "g1relayer"))
	println("[SETUP] client", clientId.String(), "connection", connectionId.String(), "channel", channelId.String())

	// --- fund the sender with a wrapped voucher via an INITIALIZE recv ---
	meta := mustTokenMetadata("grc20", z.TokenInitializer{Name: "Gno Token", Symbol: "GNOT", Decimals: 6})
	quoteToken := impl.PredictWrappedTokenV2(u256.Zero(), uint32(channelId), []byte("ugnot"), impl.MetadataImage(mustDecodeMeta(meta)))
	initOrder := z.TokenOrderV2{
		Sender:      []byte("remote-sender"),
		Receiver:    []byte(senderAddr.String()),
		BaseToken:   []byte("ugnot"),
		BaseAmount:  u256.NewUint(100),
		QuoteToken:  []byte(quoteToken),
		QuoteAmount: u256.NewUint(100),
		Kind:        z.TOKEN_ORDER_KIND_INITIALIZE,
		Metadata:    meta,
	}
	initPacket := core.NewPacket(types.ChannelId(2), channelId, mustPacketData(mustOrderInstruction(initOrder)), types.Timestamp(1<<62))

	testing.SetRealm(testing.NewUserRealm(adminAddr))
	core.PacketRecv(cross(cur), core.NewMsgPacketRecv([]types.Packet{initPacket}, nil, nil, 1))

	voucher := grc20reg.MustGet(strings.TrimPrefix(quoteToken, "ibc/"))
	println("")
	println("[FUND] sender voucher minted:", voucher.BalanceOf(senderAddr))

	// --- send: escrow the voucher (this is the lock) ---
	escrowOrder := z.TokenOrderV2{
		Sender:      []byte(senderAddr.String()),
		Receiver:    []byte("remote-receiver"),
		BaseToken:   []byte(quoteToken),
		BaseAmount:  u256.NewUint(40),
		QuoteToken:  []byte("ugnot"),
		QuoteAmount: u256.NewUint(40),
		Kind:        z.TOKEN_ORDER_KIND_ESCROW,
	}

	testing.SetRealm(testing.NewUserRealm(senderAddr))
	sendPacket := zkgm.Send(cross(cur), channelId, types.Timestamp(1<<62), [32]byte{}, mustOrderInstruction(escrowOrder))

	println("")
	println("[SEND] escrow locks the token")
	println("sender_voucher_after_send", voucher.BalanceOf(senderAddr))
	println("proxy_locked_after_send", voucher.BalanceOf(zkgm.ProxyAddress()))

	// --- ack: protocol-fill success is a no-op for an escrow, so the lock holds ---
	ack := mustSuccessAck(mustProtocolTokenOrderAck())

	testing.SetRealm(testing.NewUserRealm(adminAddr))
	core.PacketAcknowledgement(cross(cur), core.NewMsgPacketAcknowledgement([]types.Packet{sendPacket}, [][]byte{ack}, nil, 1))

	println("")
	println("[ACK] success ack does not release the escrow")
	println("sender_voucher_after_ack", voucher.BalanceOf(senderAddr))
	println("proxy_locked_after_ack", voucher.BalanceOf(zkgm.ProxyAddress()))
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

func mustProtocolTokenOrderAck() []byte {
	bz, err := z.EncodeTokenOrderAck(z.TokenOrderAck{FillType: new(u256.Uint).SetBytes(z.FILL_TYPE_PROTOCOL[:])})
	if err != nil {
		panic(err)
	}
	return bz
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

func (m *mockLightClient) Misbehaviour(address, []byte, address) (types.ClientState, error) {
	return nil, errMisbehaviourUnsupported
}

var errMisbehaviourUnsupported = mockError("mock: misbehaviour unsupported")

type mockError string

func (e mockError) Error() string { return string(e) }
