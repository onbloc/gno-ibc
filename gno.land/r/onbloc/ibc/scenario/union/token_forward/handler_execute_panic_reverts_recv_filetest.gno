// PKGPATH: gno.land/r/onbloc/ibc/scenario/union/token_forward
package token_forward

// handler_execute_panic_reverts_recv_filetest proves callForwardHandlerExecute's
// execFatal wrapping in token_forward.gno: when the registered forward
// handler's Execute panics with an ordinary (non-execFatal) value, the panic
// must still revert the whole recv - including the mint and the
// pending-forward entry executeTokenOrderForward already committed - rather
// than being silently absorbed by dispatchExecutePacket's own recover into a
// controlled failure ack (see dispatch.gno). The handler here is a separate
// realm, so it cannot construct this package's unexported execFatal itself;
// it panics with a plain string, exactly like any real handler
// implementation would on an unexpected error. The terminating panic is the
// assertion, mirroring hostile_receiver_reverts_atomically_filetest.gno in
// scenario/union/security.

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
	"gno.land/r/onbloc/ibc/union/access"
	zkgm "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm"
	_ "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/v1"
	core "gno.land/r/onbloc/ibc/union/core"
	_ "gno.land/r/onbloc/ibc/union/core/v1"
)

const (
	panicCoreImplPath    = "gno.land/r/onbloc/ibc/union/core/v1"
	panicZkgmImplPath    = "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/v1"
	panicScenarioPkgPath = "gno.land/r/onbloc/ibc/scenario/union/token_forward"

	panicAdminAddr      = address("g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5")
	panicBootstrapAddr  = address("g1dyxy88p94acjnm8dmu9tfj2mv2ncvx83cagllu")
	panicMockClientType = types.ClientType("scenario-mock-lc-panic")
)

// panicTokenForwardHandler.Execute panics with a plain string - it cannot
// construct this package's unexported execFatal itself, matching any real
// handler implementation in a separate realm.
type panicTokenForwardHandler struct{}

var panicMockFwd = &panicTokenForwardHandler{}

func (h *panicTokenForwardHandler) Prepare(cur realm, req z.TokenForwardRequest, corrID string) error {
	return nil
}

func (h *panicTokenForwardHandler) Execute(cur realm, req z.TokenForwardRequest, corrID string) {
	panic("hostile-handler-execute-boom")
}

func main(cur realm) {
	println("[SCENARIO] 1. Bootstrap IBC host and open client/connection/channel")
	channelId := panicBootstrap(cur)
	println("")

	meta := panicMustTokenMetadata("af739f34ddf951cbc24fdbba4f76213688e13627", z.TokenInitializer{Name: "EVM Asset", Symbol: "EVMAP", Decimals: 6})
	wrapped := z.PredictWrappedTokenV2(u256.Zero(), uint32(channelId), []byte("remote-evm-asset"), z.MetadataImage(panicMustDecodeMeta(meta)))

	println("[SCENARIO] 2. Bootstrap the wrapped voucher via an ordinary INITIALIZE recv")
	panicBootstrapVoucher(cur, channelId, wrapped, meta)
	println("")

	println("[SCENARIO] 3. Grant this realm zkgm's admin role and register a forward handler whose Execute panics")
	handlerAddr := chain.PackageAddress(panicScenarioPkgPath)
	testing.SetRealm(testing.NewUserRealm(panicAdminAddr))
	access.GrantRole(cross(cur), manager.AdminRole, handlerAddr)
	testing.SetRealm(testing.NewCodeRealm(panicScenarioPkgPath))
	zkgm.RegisterTokenForwardHandler(cross(cur), panicMockFwd)
	println("")

	println("[SCENARIO] 4. Receive an ESCROW order addressed to the handler: mints, then Execute panics - the whole recv must revert")
	panicRecvForward(cur, channelId, wrapped, handlerAddr)
}

func panicBootstrap(cur realm) types.ChannelId {
	testing.SetRealm(testing.NewUserRealm(panicAdminAddr))
	core.UpdateImpl(cross(cur), panicCoreImplPath)
	zkgm.UpdateImpl(cross(cur), panicZkgmImplPath)
	zkgm.SetRateLimitDisabled(cross(cur), true)
	zkgm.RegisterCoreApp(cross(cur))
	access.GrantRole(cross(cur), access.RelayerRole, panicAdminAddr)

	core.RegisterClient(cross(cur), panicMockClientType, func(_, _ []byte) (lightclient.Interface, error) {
		return &panicMockLightClient{}, nil
	})
	core.CreateClient(cross(cur), core.NewMsgCreateClient(panicMockClientType, nil, nil))
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

func panicBootstrapVoucher(cur realm, channelId types.ChannelId, wrapped string, meta []byte) {
	order := z.TokenOrderV2{
		Sender:      []byte("remote-sender"),
		Receiver:    []byte(panicBootstrapAddr.String()),
		BaseToken:   []byte("remote-evm-asset"),
		BaseAmount:  u256.NewUint(1),
		QuoteToken:  []byte(wrapped),
		QuoteAmount: u256.NewUint(1),
		Kind:        z.TOKEN_ORDER_KIND_INITIALIZE,
		Metadata:    meta,
	}
	packet := core.NewPacket(types.ChannelId(2), channelId, panicMustPacketData(panicMustOrderInstruction(order)), types.Timestamp(1<<62))

	testing.SetRealm(testing.NewUserRealm(panicAdminAddr))
	core.PacketRecv(cross(cur), core.NewMsgPacketRecv([]types.Packet{packet}, [][]byte{nil}, nil, 1))

	ufmt.Printf("[INFO] wrapped voucher deployed: %s\n", wrapped)
}

// panicRecvForward receives an ESCROW order addressed to the handler: zkgm
// mints the wrapped voucher to it, then panicTokenForwardHandler.Execute
// panics. That panic must propagate all the way through core.PacketRecv
// uncaught (as execFatal), reverting the mint too - not settle as a
// controlled failure ack.
func panicRecvForward(cur realm, channelId types.ChannelId, wrapped string, handlerAddr address) {
	order := z.TokenOrderV2{
		Sender:      []byte("remote-sender"),
		Receiver:    []byte(handlerAddr.String()),
		BaseToken:   []byte("remote-evm-asset"),
		BaseAmount:  u256.NewUint(40),
		QuoteToken:  []byte(wrapped),
		QuoteAmount: u256.NewUint(40),
		Kind:        z.TOKEN_ORDER_KIND_ESCROW,
		Metadata:    []byte("opaque routing memo, ignored by this panicking handler"),
	}
	packet := core.NewPacket(types.ChannelId(2), channelId, panicMustPacketData(panicMustOrderInstruction(order)), types.Timestamp(1<<62))

	testing.SetRealm(testing.NewUserRealm(panicAdminAddr))
	core.PacketRecv(cross(cur), core.NewMsgPacketRecv([]types.Packet{packet}, [][]byte{nil}, nil, 1))
}

// --- encoding helpers (mirror the reference e2e harness) ---

func panicMustOrderInstruction(order z.TokenOrderV2) z.Instruction {
	operand, err := z.EncodeTokenOrderV2(order)
	if err != nil {
		panic(err)
	}
	return z.Instruction{Version: z.INSTR_VERSION_2, Opcode: z.OP_TOKEN_ORDER, Operand: operand}
}

func panicMustPacketData(instr z.Instruction) []byte {
	data, err := z.EncodeZkgmPacket(z.ZkgmPacket{Path: u256.Zero(), Instruction: instr})
	if err != nil {
		panic(err)
	}
	return data
}

func panicMustTokenMetadata(implementationHex string, ti z.TokenInitializer) []byte {
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

func panicMustDecodeMeta(bz []byte) z.TokenMetadata {
	meta, err := z.DecodeTokenMetadata(bz)
	if err != nil {
		panic(err)
	}
	return meta
}

// --- permissive mock light client (accepts any proof) ---

type panicMockLightClient struct{}

func (m *panicMockLightClient) VerifyMembership(uint64, []byte, []byte, []byte) error { return nil }
func (m *panicMockLightClient) VerifyNonMembership(uint64, []byte, []byte) error      { return nil }
func (m *panicMockLightClient) GetTimestamp() types.Timestamp                         { return types.Timestamp(1) }

func (m *panicMockLightClient) GetTimestampAtHeight(uint64) (types.Timestamp, error) {
	return types.Timestamp(1), nil
}
func (m *panicMockLightClient) GetLatestHeight() uint64        { return 1 }
func (m *panicMockLightClient) GetCounterpartyChainID() string { return "mock-chain" }
func (m *panicMockLightClient) Status() lightclient.Status     { return lightclient.Active }

func (m *panicMockLightClient) VerifyHeader(_ address, header []byte, _ address) (types.StateUpdate, error) {
	return types.StateUpdate{Height: 1, ClientStateBytes: header, ConsensusStateBytes: header}, nil
}

func (m *panicMockLightClient) VerifyCreation(address, address) (types.ClientCreationResult, error) {
	return types.ClientCreationResult{}, nil
}

func (m *panicMockLightClient) Misbehaviour(address, []byte, address) ([]byte, error) {
	return nil, panicErrMisbehaviourUnsupported
}

var panicErrMisbehaviourUnsupported = panicMockError("mock: misbehaviour unsupported")

type panicMockError string

func (e panicMockError) Error() string { return string(e) }

// Output:
// [SCENARIO] 1. Bootstrap IBC host and open client/connection/channel
// [INFO] handshake opened: client=1 connection=1 channel=1
//
// [SCENARIO] 2. Bootstrap the wrapped voucher via an ordinary INITIALIZE recv
// [INFO] wrapped voucher deployed: ibc/2026388ba98752e12c7406d63c975dcb5e03a197
//
// [SCENARIO] 3. Grant this realm zkgm's admin role and register a forward handler whose Execute panics
//
// [SCENARIO] 4. Receive an ESCROW order addressed to the handler: mints, then Execute panics - the whole recv must revert

// Error:
// hostile-handler-execute-boom
