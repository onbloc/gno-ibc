// PKGPATH: gno.land/r/onbloc/ibc/bridge/ics20zkgmadapter/scenario
package scenario

// recv_reverse_forward_pending_filetest covers the reverse leg's happy path:
// EVM->Union->Gno->AtomOne. A ZKGM ESCROW TokenOrderV2 addressed to the
// adapter mints the wrapped voucher to it, forwardIcs20Handler.Execute
// approves and sends it onward via ICS20 TransferWithCallback, and the
// original ZKGM packet's ack is left deferred (PacketStatusAsync).
//
// Scope: recv -> forward send only, mirroring
// transfer/scenario/recv_forward_ack_pending_filetest.gno's scope note. The
// ICS20 leg's ack coming back (OnTransferSendResult -> CompleteTokenForwardAck)
// isn't exercised here: aib core has no pluggable mock light client (unlike
// Union core), so resolving a real ack needs a real generated proof.

import (
	"encoding/hex"
	"testing"
	"time"

	tmtesting "gno.land/p/aib/ibc/lightclient/tendermint/testing"
	aibtypes "gno.land/p/aib/ibc/types"
	"gno.land/p/nt/ufmt/v0"
	"gno.land/p/onbloc/access/manager"
	"gno.land/p/onbloc/ibc/union/lightclient"
	types "gno.land/p/onbloc/ibc/union/types"
	z "gno.land/p/onbloc/ibc/union/zkgm"

	u256 "gno.land/p/onbloc/math/uint256"

	aibcore "gno.land/r/aib/ibc/core"
	adapter "gno.land/r/onbloc/ibc/bridge/ics20zkgmadapter"
	"gno.land/r/onbloc/ibc/union/access"
	zkgm "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm"
	_ "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/v1"
	core "gno.land/r/onbloc/ibc/union/core"
	_ "gno.land/r/onbloc/ibc/union/core/v1"

	"chain"
)

const (
	coreImplPath = "gno.land/r/onbloc/ibc/union/core/v1"
	zkgmImplPath = "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/v1"
	transferPath = "gno.land/r/aib/ibc/apps/transfer"
	adapterPath  = "gno.land/r/onbloc/ibc/bridge/ics20zkgmadapter"

	adminAddr      = address("g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5")
	bootstrapAddr  = address("g1dyxy88p94acjnm8dmu9tfj2mv2ncvx83cagllu")
	mockClientType = types.ClientType("scenario-mock-lc")
)

func main(cur realm) {
	println("[SCENARIO] 1. Bootstrap Union IBC host and open client/connection/channel")
	channelId := bootstrap(cur)
	println("")

	meta := mustTokenMetadata("af739f34ddf951cbc24fdbba4f76213688e13627", z.TokenInitializer{Name: "EVM Asset", Symbol: "EVMA", Decimals: 6})
	wrapped := z.PredictWrappedTokenV2(u256.Zero(), uint32(channelId), []byte("remote-evm-asset"), z.MetadataImage(mustDecodeMeta(meta)))

	println("[SCENARIO] 2. Bootstrap the wrapped voucher via an ordinary INITIALIZE recv")
	bootstrapVoucher(cur, channelId, wrapped, meta)
	println("")

	println("[SCENARIO] 3. Grant the adapter's realm address zkgm's admin role and register the reverse handler")
	adapterAddr := chain.PackageAddress(adapterPath)
	testing.SetRealm(testing.NewUserRealm(adminAddr))
	access.GrantRole(cross(cur), manager.AdminRole, adapterAddr)
	adapter.RegisterReverseHandler(cross(cur))
	println("")

	println("[SCENARIO] 4. Bootstrap an AtomOne (aib) client for the onward ICS20 send")
	clientID := bootstrapAibClient(cur)
	println("")

	println("[SCENARIO] 5. Receive an ESCROW order addressed to the adapter: mints, escrows, and forwards onward")
	recvReverseForward(cur, channelId, wrapped, adapterAddr, clientID)
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
// adapter) so the wrapped voucher exists before the ESCROW order below: ESCROW
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
	ufmt.Println("[EXPECTED] deploy succeeds so the following ESCROW order can target it")
}

// bootstrapAibClient opens an aib tendermint client the adapter's onward ICS20
// send targets. No proof is needed here: SendPacket doesn't verify anything,
// only RecvPacket/PacketAcknowledgement do.
func bootstrapAibClient(cur realm) string {
	clientID := aibcore.CreateClient(cross(cur),
		tmtesting.NewClientState("chainA-2", aibtypes.NewHeight(2, 2)),
		tmtesting.GenConsensusState(time.Now(), []byte("apphash"), tmtesting.GenValset().Hash()),
	)
	aibcore.RegisterCounterparty(cross(cur), clientID, [][]byte{[]byte("iavlStoreKey"), []byte("prefix-reverse")}, "07-tendermint-200")

	ufmt.Printf("[INFO] atomone client: %s\n", clientID)
	return clientID
}

// recvReverseForward receives an ESCROW order addressed to the adapter: zkgm
// mints the wrapped voucher to it, then forwardIcs20Handler.Execute approves
// and sends it onward via ICS20.
func recvReverseForward(cur realm, channelId types.ChannelId, wrapped string, adapterAddr address, clientID string) {
	memo := ufmt.Sprintf(`{"forward":{"receiver":"atone1reversereceiver","channel":%q}}`, clientID)

	order := z.TokenOrderV2{
		Sender:      []byte("remote-sender"),
		Receiver:    []byte(adapterAddr.String()),
		BaseToken:   []byte("remote-evm-asset"),
		BaseAmount:  u256.NewUint(40),
		QuoteToken:  []byte(wrapped),
		QuoteAmount: u256.NewUint(40),
		Kind:        z.TOKEN_ORDER_KIND_ESCROW,
		Metadata:    []byte(memo),
	}
	packet := core.NewPacket(types.ChannelId(2), channelId, mustPacketData(mustOrderInstruction(order)), types.Timestamp(1<<62))

	testing.SetRealm(testing.NewUserRealm(adminAddr))
	core.PacketRecv(cross(cur), core.NewMsgPacketRecv([]types.Packet{packet}, [][]byte{nil}, nil, 1))

	ufmt.Printf("[INFO] adapter wrapped-voucher balance after recv: %d\n", zkgm.VoucherBalanceOf(wrapped, adapterAddr))
	ufmt.Println("[EXPECTED] should be 0 (minted 40, then approved+pulled into the ICS20 escrow)")
	ufmt.Printf("[INFO] transfer realm's escrow balance: %d\n", zkgm.VoucherBalanceOf(wrapped, chain.PackageAddress(transferPath)))
	ufmt.Println("[EXPECTED] should be 40 (pulled in by TransferWithCallback's OnSendPacket)")
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
// [SCENARIO] 1. Bootstrap Union IBC host and open client/connection/channel
// [INFO] handshake opened: client=1 connection=1 channel=1
//
// [SCENARIO] 2. Bootstrap the wrapped voucher via an ordinary INITIALIZE recv
// [INFO] wrapped voucher deployed: ibc/4875ad0d50381f02d316d753bae60388bf818165
// [EXPECTED] deploy succeeds so the following ESCROW order can target it
//
// [SCENARIO] 3. Grant the adapter's realm address zkgm's admin role and register the reverse handler
//
// [SCENARIO] 4. Bootstrap an AtomOne (aib) client for the onward ICS20 send
// [INFO] atomone client: 07-tendermint-1
//
// [SCENARIO] 5. Receive an ESCROW order addressed to the adapter: mints, escrows, and forwards onward
// [INFO] adapter wrapped-voucher balance after recv: 0
// [EXPECTED] should be 0 (minted 40, then approved+pulled into the ICS20 escrow)
// [INFO] transfer realm's escrow balance: 40
// [EXPECTED] should be 40 (pulled in by TransferWithCallback's OnSendPacket)
