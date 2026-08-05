// PKGPATH: gno.land/r/onbloc/ibc/scenario/union/token_forward
package token_forward

// recv_forward_ack_resolves_parent_filetest exercises the TokenForwardHandler
// mechanism through the real core+zkgm dispatch (not mockStore, unlike
// v1/token_forward_test.gno): an ESCROW TokenOrderV2 addressed to the
// registered handler mints the wrapped voucher to it and defers the parent
// packet's ack (PacketStatusAsync). The handler forwards it onward via a
// second real ZKGM send; once that send's ack comes back,
// CompleteTokenForwardAck resolves the parent packet's deferred ack.
//
// This is the zkgm-side twin of
// ics20zkgmadapter/scenario/recv_reverse_forward_pending_filetest.gno, which
// stops at the pending stage because its onward leg is real ICS20 (needing a
// real aib light client proof - unavailable). Here the onward leg is
// zkgm-to-zkgm, so both legs share the same permissive mock light client and
// the full round trip - including the ack - is testable.

import (
	"encoding/hex"
	"testing"

	"gno.land/p/nt/ufmt/v0"
	"gno.land/p/onbloc/access/manager"
	"gno.land/p/onbloc/ibc/union/lightclient"
	types "gno.land/p/onbloc/ibc/union/types"
	z "gno.land/p/onbloc/ibc/union/zkgm"

	u256 "gno.land/p/onbloc/math/uint256"

	"chain"
	"gno.land/r/demo/defi/grc20reg"
	"gno.land/r/onbloc/ibc/union/access"
	zkgm "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm"
	_ "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/v1"
	core "gno.land/r/onbloc/ibc/union/core"
	_ "gno.land/r/onbloc/ibc/union/core/v1"
)

const (
	coreImplPath    = "gno.land/r/onbloc/ibc/union/core/v1"
	zkgmImplPath    = "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/v1"
	scenarioPkgPath = "gno.land/r/onbloc/ibc/scenario/union/token_forward"

	adminAddr      = address("g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5")
	bootstrapAddr  = address("g1dyxy88p94acjnm8dmu9tfj2mv2ncvx83cagllu")
	mockClientType = types.ClientType("scenario-mock-lc")
	nestedCorrID   = "nested-send-corr"
)

// mockTokenForwardHandler forwards onward via a second real zkgm send
// instead of ICS20, so the whole round trip stays on the mock-light-client
// side. sendCB.parentCorrID is set here so the nested send's ack can resolve
// the right parent packet.
type mockTokenForwardHandler struct {
	prepareCalls int
	executeCalls int
}

var mockFwd = &mockTokenForwardHandler{}

func (h *mockTokenForwardHandler) Prepare(cur realm, req z.TokenForwardRequest, corrID string) error {
	h.prepareCalls++
	return nil
}

func (h *mockTokenForwardHandler) Execute(cur realm, req z.TokenForwardRequest, corrID string) {
	h.executeCalls++
	sendCB.parentCorrID = corrID
	forwardOnward(cur, req)
}

// forwardSendCallback resolves the parent packet's ack once the nested send settles.
type forwardSendCallback struct {
	parentCorrID string
	calls        int
	success      bool
}

var sendCB = &forwardSendCallback{}

// nestedSendPacket is the packet forwardOnward actually sent (with its real
// assigned sequence), so acknowledgeNestedSend can ack the exact packet
// instead of reconstructing a guess that might not hash-match.
var nestedSendPacket types.Packet

func (cb *forwardSendCallback) OnZkgmSendResult(cur realm, corrID string, success bool, ack []byte) error {
	cb.calls++
	cb.success = success
	zkgm.CompleteTokenForwardAck(cross(cur), cb.parentCorrID, success, ack)
	return nil
}

func main(cur realm) {
	println("[SCENARIO] 1. Bootstrap IBC host and open client/connection/channel")
	channelId := bootstrap(cur)
	println("")

	meta := mustTokenMetadata("af739f34ddf951cbc24fdbba4f76213688e13627", z.TokenInitializer{Name: "EVM Asset", Symbol: "EVMA", Decimals: 6})
	wrapped := z.PredictWrappedTokenV2(u256.Zero(), uint32(channelId), []byte("remote-evm-asset"), z.MetadataImage(mustDecodeMeta(meta)))

	println("[SCENARIO] 2. Bootstrap the wrapped voucher via an ordinary INITIALIZE recv")
	bootstrapVoucher(cur, channelId, wrapped, meta)
	println("")

	println("[SCENARIO] 3. Grant this realm zkgm's admin role and register the mock forward handler")
	handlerAddr := chain.PackageAddress(scenarioPkgPath)
	testing.SetRealm(testing.NewUserRealm(adminAddr))
	access.GrantRole(cross(cur), manager.AdminRole, handlerAddr)
	// RegisterTokenForwardHandler's caller must be a realm (see the check in
	// register.gno), so switch back from the impersonated admin EOA to this
	// scenario's own code-realm identity before crossing into zkgm.
	testing.SetRealm(testing.NewCodeRealm(scenarioPkgPath))
	zkgm.RegisterTokenForwardHandler(cross(cur), mockFwd)
	println("")

	println("[SCENARIO] 4. Receive an ESCROW order addressed to the handler: mints, then forwards via a second zkgm send")
	recvForward(cur, channelId, wrapped, handlerAddr)
	println("")

	println("[SCENARIO] 5. Acknowledge the nested send: resolves the parent packet's deferred ack")
	acknowledgeNestedSend(cur)
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

	return channelId
}

// bootstrapVoucher receives an ordinary INITIALIZE order (not addressed to the
// handler) so the wrapped voucher exists before the ESCROW order below: ESCROW
// targets an already-deployed wrapped voucher and is otherwise rejected.
func bootstrapVoucher(cur realm, channelId types.ChannelId, wrapped string, meta []byte) {
	order := z.TokenOrderV2{
		Sender:      []byte("remote-sender"),
		Receiver:    []byte(bootstrapAddr.String()),
		BaseToken:   []byte("remote-evm-asset"),
		BaseAmount:  u256.NewUint(1),
		QuoteToken:  []byte(wrapped),
		QuoteAmount: u256.NewUint(1),
		Kind:        z.TOKEN_ORDER_KIND_INITIALIZE,
		Metadata:    meta,
	}
	packet := core.NewPacket(types.ChannelId(2), channelId, mustPacketData(mustOrderInstruction(order)), types.Timestamp(1<<62))

	testing.SetRealm(testing.NewUserRealm(adminAddr))
	core.PacketRecv(cross(cur), core.NewMsgPacketRecv([]types.Packet{packet}, [][]byte{nil}, nil, 1))

	ufmt.Printf("[INFO] wrapped voucher deployed: %s\n", wrapped)
}

// recvForward receives an ESCROW order addressed to the handler: zkgm mints
// the wrapped voucher to it, then mockTokenForwardHandler.Execute approves
// and re-sends it via a second zkgm SendWithCallback.
func recvForward(cur realm, channelId types.ChannelId, wrapped string, handlerAddr address) {
	order := z.TokenOrderV2{
		Sender:      []byte("remote-sender"),
		Receiver:    []byte(handlerAddr.String()),
		BaseToken:   []byte("remote-evm-asset"),
		BaseAmount:  u256.NewUint(40),
		QuoteToken:  []byte(wrapped),
		QuoteAmount: u256.NewUint(40),
		Kind:        z.TOKEN_ORDER_KIND_ESCROW,
		Metadata:    []byte("opaque routing memo, ignored by this mock handler"),
	}
	packet := core.NewPacket(types.ChannelId(2), channelId, mustPacketData(mustOrderInstruction(order)), types.Timestamp(1<<62))

	testing.SetRealm(testing.NewUserRealm(adminAddr))
	core.PacketRecv(cross(cur), core.NewMsgPacketRecv([]types.Packet{packet}, [][]byte{nil}, nil, 1))

	ufmt.Printf("[INFO] handler Prepare/Execute calls: %d/%d\n", mockFwd.prepareCalls, mockFwd.executeCalls)
	ufmt.Printf("[INFO] handler wrapped-voucher balance after recv: %d\n", zkgm.VoucherBalanceOf(wrapped, handlerAddr))
	ufmt.Println("[EXPECTED] Prepare/Execute called once each; balance 0 (minted 40, then approved+pulled into the nested send's escrow)")
}

// forwardOnward approves zkgm's proxy and re-sends the forwarded voucher via
// a second SendWithCallback, as the handler realm.
func forwardOnward(cur realm, req z.TokenForwardRequest) {
	token := grc20reg.Get(req.BaseTokenKey)
	if token == nil {
		panic("token_forward scenario: voucher not found in grc20reg: " + req.BaseTokenKey)
	}
	if err := token.RealmTeller(0, cur).Approve(0, cur, zkgm.ProxyAddress(), req.Amount); err != nil {
		panic(err)
	}

	order := z.TokenOrderV2{
		Sender:      []byte(cur.Address().String()),
		Receiver:    []byte("remote-final-receiver"),
		BaseToken:   []byte(req.BaseTokenKey),
		BaseAmount:  u256.NewUint(uint64(req.Amount)),
		QuoteToken:  []byte("remote-quote"),
		QuoteAmount: u256.NewUint(uint64(req.Amount)),
		Kind:        z.TOKEN_ORDER_KIND_ESCROW,
	}
	nestedSendPacket = zkgm.SendWithCallback(cross(cur), types.ChannelId(1), types.Timestamp(1<<62), [32]byte{}, mustOrderInstruction(order), nestedCorrID, sendCB)
}

// acknowledgeNestedSend sends a protocol-fill success ack for the exact
// packet forwardOnward sent, driving OnZkgmSendResult ->
// CompleteTokenForwardAck -> the parent packet's deferred ack.
func acknowledgeNestedSend(cur realm) {
	ack := mustSuccessAck(mustProtocolTokenOrderAck())

	testing.SetRealm(testing.NewUserRealm(adminAddr))
	core.PacketAcknowledgement(cross(cur), core.NewMsgPacketAcknowledgement([]types.Packet{nestedSendPacket}, [][]byte{ack}, nil, 1))

	ufmt.Printf("[INFO] send callback invocations: %d\n", sendCB.calls)
	ufmt.Printf("[INFO] send callback success: %t\n", sendCB.success)
	ufmt.Println("[EXPECTED] callback invoked once with success=true, resolving the parent packet's deferred ack via CompleteTokenForwardAck")
}

// --- encoding helpers (mirror the reference e2e harness) ---

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

func (m *mockLightClient) Misbehaviour(address, []byte, address) ([]byte, error) {
	return nil, errMisbehaviourUnsupported
}

var errMisbehaviourUnsupported = mockError("mock: misbehaviour unsupported")

type mockError string

func (e mockError) Error() string { return string(e) }

// Output:
// [SCENARIO] 1. Bootstrap IBC host and open client/connection/channel
// [INFO] handshake opened: client=1 connection=1 channel=1
//
// [SCENARIO] 2. Bootstrap the wrapped voucher via an ordinary INITIALIZE recv
// [INFO] wrapped voucher deployed: ibc/4875ad0d50381f02d316d753bae60388bf818165
//
// [SCENARIO] 3. Grant this realm zkgm's admin role and register the mock forward handler
//
// [SCENARIO] 4. Receive an ESCROW order addressed to the handler: mints, then forwards via a second zkgm send
// [INFO] handler Prepare/Execute calls: 1/1
// [INFO] handler wrapped-voucher balance after recv: 0
// [EXPECTED] Prepare/Execute called once each; balance 0 (minted 40, then approved+pulled into the nested send's escrow)
//
// [SCENARIO] 5. Acknowledge the nested send: resolves the parent packet's deferred ack
// [INFO] send callback invocations: 1
// [INFO] send callback success: true
// [EXPECTED] callback invoked once with success=true, resolving the parent packet's deferred ack via CompleteTokenForwardAck
