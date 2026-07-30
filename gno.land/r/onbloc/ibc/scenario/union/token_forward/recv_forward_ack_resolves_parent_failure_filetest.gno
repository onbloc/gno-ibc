// PKGPATH: gno.land/r/onbloc/ibc/scenario/union/token_forward
package token_forward

// recv_forward_ack_resolves_parent_failure_filetest is the failure
// counterpart of recv_forward_ack_resolves_parent_filetest.gno: when the
// handler's onward leg fails/times out, ZKGM's own escrow first refunds the
// nested order's Sender (the handler), and CompleteTokenForwardAck then burns
// that refunded wrapped voucher back before writing the parent packet's
// failure ack - so the upstream refund the failure ack triggers is not
// double-counted against a stranded balance on this chain.

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
	failCoreImplPath    = "gno.land/r/onbloc/ibc/union/core/v1"
	failZkgmImplPath    = "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/v1"
	failScenarioPkgPath = "gno.land/r/onbloc/ibc/scenario/union/token_forward"

	failAdminAddr      = address("g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5")
	failBootstrapAddr  = address("g1dyxy88p94acjnm8dmu9tfj2mv2ncvx83cagllu")
	failMockClientType = types.ClientType("scenario-mock-lc-fail")
	failNestedCorrID   = "nested-send-corr-fail"
)

// failMockTokenForwardHandler mirrors mockTokenForwardHandler, forwarding
// onward via a second real zkgm send that this test then acks as a failure.
type failMockTokenForwardHandler struct {
	prepareCalls int
	executeCalls int
}

var failMockFwd = &failMockTokenForwardHandler{}

func (h *failMockTokenForwardHandler) Prepare(cur realm, req z.TokenForwardRequest, corrID string) error {
	h.prepareCalls++
	return nil
}

func (h *failMockTokenForwardHandler) Execute(cur realm, req z.TokenForwardRequest, corrID string) {
	h.executeCalls++
	failSendCB.parentCorrID = corrID
	failForwardOnward(cur, req)
}

type failForwardSendCallback struct {
	parentCorrID string
	calls        int
	success      bool
}

var failSendCB = &failForwardSendCallback{}

var failNestedSendPacket types.Packet

func (cb *failForwardSendCallback) OnZkgmSendResult(cur realm, corrID string, success bool, ack []byte) error {
	cb.calls++
	cb.success = success
	zkgm.CompleteTokenForwardAck(cross(cur), cb.parentCorrID, success, ack)
	return nil
}

func main(cur realm) {
	println("[SCENARIO] 1. Bootstrap IBC host and open client/connection/channel")
	channelId := failBootstrap(cur)
	println("")

	meta := failMustTokenMetadata("af739f34ddf951cbc24fdbba4f76213688e13627", z.TokenInitializer{Name: "EVM Asset", Symbol: "EVMAF", Decimals: 6})
	wrapped := z.PredictWrappedTokenV2(u256.Zero(), uint32(channelId), []byte("remote-evm-asset"), z.MetadataImage(failMustDecodeMeta(meta)))

	println("[SCENARIO] 2. Bootstrap the wrapped voucher via an ordinary INITIALIZE recv")
	failBootstrapVoucher(cur, channelId, wrapped, meta)
	println("")

	println("[SCENARIO] 3. Grant this realm zkgm's admin role and register the mock forward handler")
	handlerAddr := chain.PackageAddress(failScenarioPkgPath)
	testing.SetRealm(testing.NewUserRealm(failAdminAddr))
	access.GrantRole(cross(cur), manager.AdminRole, handlerAddr)
	testing.SetRealm(testing.NewCodeRealm(failScenarioPkgPath))
	zkgm.RegisterTokenForwardHandler(cross(cur), failMockFwd)
	println("")

	println("[SCENARIO] 4. Receive an ESCROW order addressed to the handler: mints, then forwards via a second zkgm send")
	failRecvForward(cur, channelId, wrapped, handlerAddr)
	println("")

	println("[SCENARIO] 5. Acknowledge the nested send with a FAILURE ack: ZKGM refunds the handler, then CompleteTokenForwardAck burns it back")
	failAcknowledgeNestedSend(cur, wrapped, handlerAddr)
}

func failBootstrap(cur realm) types.ChannelId {
	testing.SetRealm(testing.NewUserRealm(failAdminAddr))
	core.UpdateImpl(cross(cur), failCoreImplPath)
	zkgm.UpdateImpl(cross(cur), failZkgmImplPath)
	zkgm.SetRateLimitDisabled(cross(cur), true)
	zkgm.RegisterCoreApp(cross(cur))
	access.GrantRole(cross(cur), access.RelayerRole, failAdminAddr)

	core.RegisterClient(cross(cur), failMockClientType, func(_, _ []byte) (lightclient.Interface, error) {
		return &failMockLightClient{}, nil
	})
	core.CreateClient(cross(cur), core.NewMsgCreateClient(failMockClientType, nil, nil))
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

func failBootstrapVoucher(cur realm, channelId types.ChannelId, wrapped string, meta []byte) {
	order := z.TokenOrderV2{
		Sender:      []byte("remote-sender"),
		Receiver:    []byte(failBootstrapAddr.String()),
		BaseToken:   []byte("remote-evm-asset"),
		BaseAmount:  u256.NewUint(1),
		QuoteToken:  []byte(wrapped),
		QuoteAmount: u256.NewUint(1),
		Kind:        z.TOKEN_ORDER_KIND_INITIALIZE,
		Metadata:    meta,
	}
	packet := core.NewPacket(types.ChannelId(2), channelId, failMustPacketData(failMustOrderInstruction(order)), types.Timestamp(1<<62))

	testing.SetRealm(testing.NewUserRealm(failAdminAddr))
	core.PacketRecv(cross(cur), core.NewMsgPacketRecv([]types.Packet{packet}, [][]byte{nil}, nil, 1))

	ufmt.Printf("[INFO] wrapped voucher deployed: %s\n", wrapped)
}

func failRecvForward(cur realm, channelId types.ChannelId, wrapped string, handlerAddr address) {
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
	packet := core.NewPacket(types.ChannelId(2), channelId, failMustPacketData(failMustOrderInstruction(order)), types.Timestamp(1<<62))

	testing.SetRealm(testing.NewUserRealm(failAdminAddr))
	core.PacketRecv(cross(cur), core.NewMsgPacketRecv([]types.Packet{packet}, [][]byte{nil}, nil, 1))

	ufmt.Printf("[INFO] handler Prepare/Execute calls: %d/%d\n", failMockFwd.prepareCalls, failMockFwd.executeCalls)
	ufmt.Printf("[INFO] handler wrapped-voucher balance after recv: %d\n", zkgm.VoucherBalanceOf(wrapped, handlerAddr))
	ufmt.Println("[EXPECTED] Prepare/Execute called once each; balance 0 (minted 40, then approved+pulled into the nested send's escrow)")
}

func failForwardOnward(cur realm, req z.TokenForwardRequest) {
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
	failNestedSendPacket = zkgm.SendWithCallback(cross(cur), types.ChannelId(1), types.Timestamp(1<<62), [32]byte{}, failMustOrderInstruction(order), failNestedCorrID, failSendCB)
}

// failAcknowledgeNestedSend submits a FAILURE ack for the nested send: ZKGM's
// own opcode handling refunds the escrowed wrapped voucher back to the
// handler (order.Sender) before handleSendCallback notifies
// OnZkgmSendResult, which in turn calls CompleteTokenForwardAck(success=
// false) and burns that refunded balance back to 0.
func failAcknowledgeNestedSend(cur realm, wrapped string, handlerAddr address) {
	ack := failMustFailureAck()

	testing.SetRealm(testing.NewUserRealm(failAdminAddr))
	core.PacketAcknowledgement(cross(cur), core.NewMsgPacketAcknowledgement([]types.Packet{failNestedSendPacket}, [][]byte{ack}, nil, 1))

	ufmt.Printf("[INFO] send callback invocations: %d\n", failSendCB.calls)
	ufmt.Printf("[INFO] send callback success: %t\n", failSendCB.success)
	ufmt.Printf("[INFO] handler wrapped-voucher balance after resolve: %d\n", zkgm.VoucherBalanceOf(wrapped, handlerAddr))
	ufmt.Println("[EXPECTED] callback invoked once with success=false; balance back to 0 (ZKGM refunded 40, CompleteTokenForwardAck burned it back)")
}

// --- encoding helpers (mirror the reference e2e harness) ---

func failMustOrderInstruction(order z.TokenOrderV2) z.Instruction {
	operand, err := z.EncodeTokenOrderV2(order)
	if err != nil {
		panic(err)
	}
	return z.Instruction{Version: z.INSTR_VERSION_2, Opcode: z.OP_TOKEN_ORDER, Operand: operand}
}

func failMustPacketData(instr z.Instruction) []byte {
	data, err := z.EncodeZkgmPacket(z.ZkgmPacket{Path: u256.Zero(), Instruction: instr})
	if err != nil {
		panic(err)
	}
	return data
}

func failMustTokenMetadata(implementationHex string, ti z.TokenInitializer) []byte {
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

func failMustDecodeMeta(bz []byte) z.TokenMetadata {
	meta, err := z.DecodeTokenMetadata(bz)
	if err != nil {
		panic(err)
	}
	return meta
}

func failMustFailureAck() []byte {
	ack, err := z.EncodeAck(z.Ack{Tag: new(u256.Uint).SetBytes(z.TAG_ACK_FAILURE[:]), InnerAck: nil})
	if err != nil {
		panic(err)
	}
	return ack
}

// --- permissive mock light client (accepts any proof) ---

type failMockLightClient struct{}

func (m *failMockLightClient) VerifyMembership(uint64, []byte, []byte, []byte) error { return nil }
func (m *failMockLightClient) VerifyNonMembership(uint64, []byte, []byte) error      { return nil }
func (m *failMockLightClient) GetTimestamp() types.Timestamp                         { return types.Timestamp(1) }

func (m *failMockLightClient) GetTimestampAtHeight(uint64) (types.Timestamp, error) {
	return types.Timestamp(1), nil
}
func (m *failMockLightClient) GetLatestHeight() uint64        { return 1 }
func (m *failMockLightClient) GetCounterpartyChainID() string { return "mock-chain" }
func (m *failMockLightClient) Status() lightclient.Status     { return lightclient.Active }

func (m *failMockLightClient) VerifyHeader(_ address, header []byte, _ address) (types.StateUpdate, error) {
	return types.StateUpdate{Height: 1, ClientStateBytes: header, ConsensusStateBytes: header}, nil
}

func (m *failMockLightClient) VerifyCreation(address, address) (types.ClientCreationResult, error) {
	return types.ClientCreationResult{}, nil
}

func (m *failMockLightClient) Misbehaviour(address, []byte, address) ([]byte, error) {
	return nil, failErrMisbehaviourUnsupported
}

var failErrMisbehaviourUnsupported = failMockError("mock: misbehaviour unsupported")

type failMockError string

func (e failMockError) Error() string { return string(e) }

// Output:
// [SCENARIO] 1. Bootstrap IBC host and open client/connection/channel
// [INFO] handshake opened: client=1 connection=1 channel=1
//
// [SCENARIO] 2. Bootstrap the wrapped voucher via an ordinary INITIALIZE recv
// [INFO] wrapped voucher deployed: ibc/5823769aff6be6e4b2168f960cb0bf5aa9253042
//
// [SCENARIO] 3. Grant this realm zkgm's admin role and register the mock forward handler
//
// [SCENARIO] 4. Receive an ESCROW order addressed to the handler: mints, then forwards via a second zkgm send
// [INFO] handler Prepare/Execute calls: 1/1
// [INFO] handler wrapped-voucher balance after recv: 0
// [EXPECTED] Prepare/Execute called once each; balance 0 (minted 40, then approved+pulled into the nested send's escrow)
//
// [SCENARIO] 5. Acknowledge the nested send with a FAILURE ack: ZKGM refunds the handler, then CompleteTokenForwardAck burns it back
// [INFO] send callback invocations: 1
// [INFO] send callback success: false
// [INFO] handler wrapped-voucher balance after resolve: 0
// [EXPECTED] callback invoked once with success=false; balance back to 0 (ZKGM refunded 40, CompleteTokenForwardAck burned it back)
