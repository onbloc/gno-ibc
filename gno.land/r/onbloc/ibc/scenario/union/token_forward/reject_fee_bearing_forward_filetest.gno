// PKGPATH: gno.land/r/onbloc/ibc/scenario/union/token_forward
package token_forward

// reject_fee_bearing_forward_filetest proves the relayer-fee guard added to
// executeTokenOrderForward: a forward-addressed ESCROW order whose BaseAmount
// exceeds QuoteAmount (i.e. carries a relayer fee) is rejected before any
// custody is taken. Without this guard, protocolFillMint would mint the fee
// straight to the relayer in addition to the quote it mints to the handler;
// CompleteTokenForwardAck's failure-path burn only unwinds the handler's own
// mint, so that separate relayer mint would be left uncollateralized once
// the failure ack tells upstream to refund the full BaseAmount.

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
	feeCoreImplPath    = "gno.land/r/onbloc/ibc/union/core/v1"
	feeZkgmImplPath    = "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/v1"
	feeScenarioPkgPath = "gno.land/r/onbloc/ibc/scenario/union/token_forward"

	feeAdminAddr      = address("g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5")
	feeBootstrapAddr  = address("g1dyxy88p94acjnm8dmu9tfj2mv2ncvx83cagllu")
	feeMockClientType = types.ClientType("scenario-mock-lc-fee")
)

// feeMockTokenForwardHandler records whether it was ever invoked, so the test
// can assert the fee-bearing order never reaches it.
type feeMockTokenForwardHandler struct {
	prepareCalls int
	executeCalls int
}

var feeMockFwd = &feeMockTokenForwardHandler{}

func (h *feeMockTokenForwardHandler) Prepare(cur realm, req z.TokenForwardRequest, corrID string) error {
	h.prepareCalls++
	return nil
}

func (h *feeMockTokenForwardHandler) Execute(cur realm, req z.TokenForwardRequest, corrID string) {
	h.executeCalls++
}

func main(cur realm) {
	println("[SCENARIO] 1. Bootstrap IBC host and open client/connection/channel")
	channelId := feeBootstrap(cur)
	println("")

	meta := feeMustTokenMetadata("af739f34ddf951cbc24fdbba4f76213688e13627", z.TokenInitializer{Name: "EVM Asset", Symbol: "EVMAX", Decimals: 6})
	wrapped := z.PredictWrappedTokenV2(u256.Zero(), uint32(channelId), []byte("remote-evm-asset"), z.MetadataImage(feeMustDecodeMeta(meta)))

	println("[SCENARIO] 2. Bootstrap the wrapped voucher via an ordinary INITIALIZE recv")
	feeBootstrapVoucher(cur, channelId, wrapped, meta)
	println("")

	println("[SCENARIO] 3. Grant this realm zkgm's admin role and register the mock forward handler")
	handlerAddr := chain.PackageAddress(feeScenarioPkgPath)
	testing.SetRealm(testing.NewUserRealm(feeAdminAddr))
	access.GrantRole(cross(cur), manager.AdminRole, handlerAddr)
	testing.SetRealm(testing.NewCodeRealm(feeScenarioPkgPath))
	zkgm.RegisterTokenForwardHandler(cross(cur), feeMockFwd)
	println("")

	println("[SCENARIO] 4. Receive a fee-bearing ESCROW order (BaseAmount > QuoteAmount) addressed to the handler")
	feeRecvForward(cur, channelId, wrapped, handlerAddr)
}

func feeBootstrap(cur realm) types.ChannelId {
	testing.SetRealm(testing.NewUserRealm(feeAdminAddr))
	core.UpdateImpl(cross(cur), feeCoreImplPath)
	zkgm.UpdateImpl(cross(cur), feeZkgmImplPath)
	zkgm.SetRateLimitDisabled(cross(cur), true)
	zkgm.RegisterCoreApp(cross(cur))
	access.GrantRole(cross(cur), access.RelayerRole, feeAdminAddr)

	core.RegisterClient(cross(cur), feeMockClientType, func(_, _ []byte) (lightclient.Interface, error) {
		return &feeMockLightClient{}, nil
	})
	core.CreateClient(cross(cur), core.NewMsgCreateClient(feeMockClientType, nil, nil))
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

func feeBootstrapVoucher(cur realm, channelId types.ChannelId, wrapped string, meta []byte) {
	order := z.TokenOrderV2{
		Sender:      []byte("remote-sender"),
		Receiver:    []byte(feeBootstrapAddr.String()),
		BaseToken:   []byte("remote-evm-asset"),
		BaseAmount:  u256.NewUint(1),
		QuoteToken:  []byte(wrapped),
		QuoteAmount: u256.NewUint(1),
		Kind:        z.TOKEN_ORDER_KIND_INITIALIZE,
		Metadata:    meta,
	}
	packet := core.NewPacket(types.ChannelId(2), channelId, feeMustPacketData(feeMustOrderInstruction(order)), types.Timestamp(1<<62))

	testing.SetRealm(testing.NewUserRealm(feeAdminAddr))
	core.PacketRecv(cross(cur), core.NewMsgPacketRecv([]types.Packet{packet}, [][]byte{nil}, nil, 1))

	ufmt.Printf("[INFO] wrapped voucher deployed: %s\n", wrapped)
}

// feeRecvForward receives an ESCROW order with BaseAmount(50) > QuoteAmount(40)
// - a 10-unit relayer fee - addressed to the handler. The fee guard must
// reject it before Prepare/Execute or any mint, leaving both the handler's
// and the relayer's wrapped-voucher balances at 0.
func feeRecvForward(cur realm, channelId types.ChannelId, wrapped string, handlerAddr address) {
	order := z.TokenOrderV2{
		Sender:      []byte("remote-sender"),
		Receiver:    []byte(handlerAddr.String()),
		BaseToken:   []byte("remote-evm-asset"),
		BaseAmount:  u256.NewUint(50),
		QuoteToken:  []byte(wrapped),
		QuoteAmount: u256.NewUint(40),
		Kind:        z.TOKEN_ORDER_KIND_ESCROW,
		Metadata:    []byte("opaque routing memo, ignored by this mock handler"),
	}
	packet := core.NewPacket(types.ChannelId(2), channelId, feeMustPacketData(feeMustOrderInstruction(order)), types.Timestamp(1<<62))

	testing.SetRealm(testing.NewUserRealm(feeAdminAddr))
	core.PacketRecv(cross(cur), core.NewMsgPacketRecv([]types.Packet{packet}, [][]byte{nil}, nil, 1))

	ufmt.Printf("[INFO] handler Prepare/Execute calls: %d/%d\n", feeMockFwd.prepareCalls, feeMockFwd.executeCalls)
	ufmt.Printf("[INFO] handler wrapped-voucher balance after recv: %d\n", zkgm.VoucherBalanceOf(wrapped, handlerAddr))
	ufmt.Printf("[INFO] relayer wrapped-voucher balance after recv: %d\n", zkgm.VoucherBalanceOf(wrapped, feeAdminAddr))
	ufmt.Println("[EXPECTED] Prepare/Execute never called (rejected before custody); handler and relayer balances both 0 - no fee minted")
}

// --- encoding helpers (mirror the reference e2e harness) ---

func feeMustOrderInstruction(order z.TokenOrderV2) z.Instruction {
	operand, err := z.EncodeTokenOrderV2(order)
	if err != nil {
		panic(err)
	}
	return z.Instruction{Version: z.INSTR_VERSION_2, Opcode: z.OP_TOKEN_ORDER, Operand: operand}
}

func feeMustPacketData(instr z.Instruction) []byte {
	data, err := z.EncodeZkgmPacket(z.ZkgmPacket{Path: u256.Zero(), Instruction: instr})
	if err != nil {
		panic(err)
	}
	return data
}

func feeMustTokenMetadata(implementationHex string, ti z.TokenInitializer) []byte {
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

func feeMustDecodeMeta(bz []byte) z.TokenMetadata {
	meta, err := z.DecodeTokenMetadata(bz)
	if err != nil {
		panic(err)
	}
	return meta
}

// --- permissive mock light client (accepts any proof) ---

type feeMockLightClient struct{}

func (m *feeMockLightClient) VerifyMembership(uint64, []byte, []byte, []byte) error { return nil }
func (m *feeMockLightClient) VerifyNonMembership(uint64, []byte, []byte) error      { return nil }
func (m *feeMockLightClient) GetTimestamp() types.Timestamp                         { return types.Timestamp(1) }

func (m *feeMockLightClient) GetTimestampAtHeight(uint64) (types.Timestamp, error) {
	return types.Timestamp(1), nil
}
func (m *feeMockLightClient) GetLatestHeight() uint64        { return 1 }
func (m *feeMockLightClient) GetCounterpartyChainID() string { return "mock-chain" }
func (m *feeMockLightClient) Status() lightclient.Status     { return lightclient.Active }

func (m *feeMockLightClient) VerifyHeader(_ address, header []byte, _ address) (types.StateUpdate, error) {
	return types.StateUpdate{Height: 1, ClientStateBytes: header, ConsensusStateBytes: header}, nil
}

func (m *feeMockLightClient) VerifyCreation(address, address) (types.ClientCreationResult, error) {
	return types.ClientCreationResult{}, nil
}

func (m *feeMockLightClient) Misbehaviour(address, []byte, address) ([]byte, error) {
	return nil, feeErrMisbehaviourUnsupported
}

var feeErrMisbehaviourUnsupported = feeMockError("mock: misbehaviour unsupported")

type feeMockError string

func (e feeMockError) Error() string { return string(e) }

// Output:
// [SCENARIO] 1. Bootstrap IBC host and open client/connection/channel
// [INFO] handshake opened: client=1 connection=1 channel=1
//
// [SCENARIO] 2. Bootstrap the wrapped voucher via an ordinary INITIALIZE recv
// [INFO] wrapped voucher deployed: ibc/1b6daef8f9e1ee869c2f1a3fff716214a1b532af
//
// [SCENARIO] 3. Grant this realm zkgm's admin role and register the mock forward handler
//
// [SCENARIO] 4. Receive a fee-bearing ESCROW order (BaseAmount > QuoteAmount) addressed to the handler
// [INFO] handler Prepare/Execute calls: 0/0
// [INFO] handler wrapped-voucher balance after recv: 0
// [INFO] relayer wrapped-voucher balance after recv: 0
// [EXPECTED] Prepare/Execute never called (rejected before custody); handler and relayer balances both 0 - no fee minted
