// PKGPATH: gno.land/r/onbloc/ibc/scenario/union/send
package send

// lock_native_coin_by_ucs03_zkgm_filetest walks a native-coin ucs03-zkgm token
// send through the upgradeable union IBC host (permissive mock light client). The
// user attaches native ugnot with the call; the impl reads that send envelope via
// OriginSend to seed the escrow budget, locks it in the proxy, and the protocol-
// fill ack leaves it locked. Without the attached coins the send would abort with
// a "sent coin mismatch" since the escrow budget could not cover the order.

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
	senderAddr     = address("g1wymu47drhr0kuq2098m792lytgtj2nyx77yrsm")
	mockClientType = types.ClientType("scenario-mock-lc")
)

func main(cur realm) {
	println("[SCENARIO] 1. Bootstrap IBC host and open client/connection/channel")
	channelId := bootstrap(cur)
	println("")

	println("[SCENARIO] 2. Send native ESCROW order locking 40ugnot (funded via attached send coins)")
	sendPacket := sendNativeEscrowOrder(cur, channelId)
	println("")

	println("[SCENARIO] 3. Acknowledge with protocol-fill success (no-op for escrow)")
	acknowledgeNativeEscrow(cur, sendPacket)
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

// sendNativeEscrowOrder sends a native ESCROW order funded by attached coins. In
// production the user attaches `-send 40ugnot`, which credits the proxy (the escrow
// account) and shows up in the OriginSend envelope. IssueCoins reproduces the
// deposit; SetOriginSend reproduces the envelope the impl reads to seed its escrow
// budget. It returns the produced packet for later acknowledgement.
func sendNativeEscrowOrder(cur realm, channelId types.ChannelId) types.Packet {
	order := z.TokenOrderV2{
		Sender:      []byte(senderAddr.String()),
		Receiver:    []byte("remote-receiver"),
		BaseToken:   []byte("ugnot"),
		BaseAmount:  u256.NewUint(40),
		QuoteToken:  []byte("remote-ugnot"),
		QuoteAmount: u256.NewUint(40),
		Kind:        z.TOKEN_ORDER_KIND_ESCROW,
	}

	proxy := zkgm.ProxyAddress()
	testing.IssueCoins(proxy, chain.NewCoins(chain.NewCoin("ugnot", 40)))

	testing.SetRealm(testing.NewUserRealm(senderAddr))
	testing.SetOriginSend(chain.NewCoins(chain.NewCoin("ugnot", 40)))
	sendPacket := zkgm.Send(cross(cur), channelId, types.Timestamp(1<<62), [32]byte{}, mustOrderInstruction(order))

	bk := banker.NewReadonlyBanker()
	ufmt.Printf("[INFO] send produced packet on channel: %s\n", sendPacket.SourceChannelId.String())
	ufmt.Printf("[INFO] proxy native escrow balance: %d\n", bk.GetCoins(proxy).AmountOf("ugnot"))
	ufmt.Println("[EXPECTED] send should succeed: attached 40ugnot covers the escrow order")
	ufmt.Println("[EXPECTED] proxy native escrow balance should be 40 (locked)")

	return sendPacket
}

// acknowledgeNativeEscrow acknowledges the sent packet with a protocol-fill success
// ack, which is a no-op for an escrow, so the native coins stay locked.
func acknowledgeNativeEscrow(cur realm, sendPacket types.Packet) {
	ack := mustSuccessAck(mustProtocolTokenOrderAck())

	testing.SetRealm(testing.NewUserRealm(adminAddr))
	core.PacketAcknowledgement(cross(cur), core.NewMsgPacketAcknowledgement([]types.Packet{sendPacket}, [][]byte{ack}, nil, 1))

	bk := banker.NewReadonlyBanker()
	ufmt.Printf("[INFO] proxy native escrow balance: %d\n", bk.GetCoins(zkgm.ProxyAddress()).AmountOf("ugnot"))
	ufmt.Println("[EXPECTED] proxy native escrow balance should be 40 (unchanged: escrow stays locked)")
}

// --- encoding helpers (pure z calls, mirroring the e2e harness) ---

func mustOrderInstruction(order z.TokenOrderV2) z.Instruction {
	operand, err := z.EncodeTokenOrderV2(order)
	if err != nil {
		panic(err)
	}
	return z.Instruction{Version: z.INSTR_VERSION_2, Opcode: z.OP_TOKEN_ORDER, Operand: operand}
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
// [EXPECTED] client should be 1
// [EXPECTED] connection should be 1
// [EXPECTED] channel should be 1
//
// [SCENARIO] 2. Send native ESCROW order locking 40ugnot (funded via attached send coins)
// [INFO] send produced packet on channel: 1
// [INFO] proxy native escrow balance: 40
// [EXPECTED] send should succeed: attached 40ugnot covers the escrow order
// [EXPECTED] proxy native escrow balance should be 40 (locked)
//
// [SCENARIO] 3. Acknowledge with protocol-fill success (no-op for escrow)
// [INFO] proxy native escrow balance: 40
// [EXPECTED] proxy native escrow balance should be 40 (unchanged: escrow stays locked)
