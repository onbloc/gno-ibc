// PKGPATH: gno.land/r/onbloc/ibc/scenario/union/forward
package forward

// send_forward_escrow_marketmaker_fill_ack_filetest walks a user-initiated
// top-level OP_FORWARD send (wrapping a native ESCROW TokenOrder) through the
// union IBC host, then acknowledges it with a market-maker-fill ack.

import (
	"chain"
	"chain/banker"
	"testing"

	"gno.land/p/nt/ufmt/v0"
	"gno.land/p/onbloc/ibc/union/lightclient"
	types "gno.land/p/onbloc/ibc/union/types"
	z "gno.land/p/onbloc/ibc/union/zkgm"

	u256 "gno.land/p/onbloc/math/uint256"

	"gno.land/r/onbloc/ibc/union/access"
	zkgm "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm"
	_ "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/v1"
	core "gno.land/r/onbloc/ibc/union/core"
	_ "gno.land/r/onbloc/ibc/union/core/v1"
)

const (
	coreImplPathAck = "gno.land/r/onbloc/ibc/union/core/v1"
	zkgmImplPathAck = "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/v1"

	adminAddrAck   = address("g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5")
	senderAddrAck  = address("g1wymu47drhr0kuq2098m792lytgtj2nyx77yrsm")
	makerAddrAck   = address("g1dyxy88p94acjnm8dmu9tfj2mv2ncvx83cagllu")
	mockClientAck  = types.ClientType("scenario-fwd-ack-mock-lc")
	fwdAckPrevDest = uint32(9)
	fwdAckNextSrc  = uint32(10)
)

func main(cur realm) {
	println("[SCENARIO] 1. Bootstrap IBC host and open client/connection/channel")
	channelId := bootstrapAck(cur)
	println("")

	println("[SCENARIO] 2. Send a top-level OP_FORWARD wrapping a native ESCROW order, locking 40ugnot")
	sendPacket := sendTopLevelForwardOrder(cur, channelId)
	println("")

	println("[SCENARIO] 3. A market-maker-fill ack on the top-level forward settles the escrow to the maker")
	acknowledgeMarketMakerFill(cur, sendPacket)
}

// bootstrapAck installs the core/zkgm impls, grants the admin the relayer
// role, and opens a client/connection/channel backed by the permissive mock
// light client.
func bootstrapAck(cur realm) types.ChannelId {
	testing.SetRealm(testing.NewUserRealm(adminAddrAck))
	core.UpdateImpl(cross(cur), coreImplPathAck)
	zkgm.UpdateImpl(cross(cur), zkgmImplPathAck)
	zkgm.SetRateLimitDisabled(cross(cur), true)
	zkgm.RegisterCoreApp(cross(cur))
	access.GrantRole(cross(cur), access.RelayerRole, adminAddrAck)

	core.RegisterClient(cross(cur), mockClientAck, func(_, _ []byte) (lightclient.Interface, error) {
		return &fwdAckMockLightClient{}, nil
	})
	core.CreateClient(cross(cur), core.NewMsgCreateClient(mockClientAck, []byte{1}, []byte{1}))
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

// sendTopLevelForwardOrder sends a top-level OP_FORWARD instruction that
// wraps a native ESCROW TokenOrder, funded by attached coins. The escrow is
// recorded under (channelId, forward.Path, ...) by verifyForward, not under
// the top-level zp.Path (which is always zero for a user Send).
func sendTopLevelForwardOrder(cur realm, channelId types.ChannelId) types.Packet {
	order := z.TokenOrderV2{
		Sender:      []byte(senderAddrAck.String()),
		Receiver:    []byte("remote-receiver"),
		BaseToken:   []byte("ugnot"),
		BaseAmount:  u256.NewUint(40),
		QuoteToken:  []byte("remote-ugnot"),
		QuoteAmount: u256.NewUint(40),
		Kind:        z.TOKEN_ORDER_KIND_ESCROW,
	}
	forward := z.Forward{
		Path:             forwardPathAck(fwdAckPrevDest, fwdAckNextSrc),
		TimeoutTimestamp: 1 << 62,
		Instruction:      mustOrderInstructionAck(order),
	}

	proxy := zkgm.ProxyAddress()
	testing.IssueCoins(proxy, chain.NewCoins(chain.NewCoin("ugnot", 40)))

	testing.SetRealm(testing.NewUserRealm(senderAddrAck))
	testing.SetOriginSend(chain.NewCoins(chain.NewCoin("ugnot", 40)))
	sendPacket := zkgm.Send(cross(cur), channelId, types.Timestamp(1<<62), [32]byte{}, mustForwardInstructionAck(forward))

	bk := banker.NewReadonlyBanker()
	ufmt.Printf("[INFO] send produced packet on channel: %s\n", sendPacket.SourceChannelId.String())
	ufmt.Printf("[INFO] proxy native escrow balance: %d\n", bk.GetCoin(proxy, "ugnot"))
	ufmt.Println("[EXPECTED] send should succeed: attached 40ugnot covers the escrow order")
	ufmt.Println("[EXPECTED] proxy native escrow balance should be 40 (locked)")

	return sendPacket
}

// acknowledgeMarketMakerFill acknowledges the top-level forward packet with a
// market-maker-fill ack. Before the High-1 fix this would panic with
// errUnsupportedOpcode and abort the transaction, permanently locking the
// escrow.
func acknowledgeMarketMakerFill(cur realm, sendPacket types.Packet) {
	bk := banker.NewReadonlyBanker()
	proxy := zkgm.ProxyAddress()

	testing.SetRealm(testing.NewUserRealm(adminAddrAck))
	core.PacketAcknowledgement(cross(cur), core.NewMsgPacketAcknowledgement([]types.Packet{sendPacket}, [][]byte{mustMakerFillAckAck(makerAddrAck)}, nil, 1))

	ufmt.Printf("[INFO] proxy native escrow balance: %d\n", bk.GetCoin(proxy, "ugnot"))
	ufmt.Printf("[INFO] sender native balance: %d\n", bk.GetCoin(senderAddrAck, "ugnot"))
	ufmt.Printf("[INFO] maker native balance: %d\n", bk.GetCoin(makerAddrAck, "ugnot"))
	ufmt.Println("[EXPECTED] proxy native escrow balance should be 0 (released to the maker)")
	ufmt.Println("[EXPECTED] sender native balance should be 0 (unchanged: not refunded)")
	ufmt.Println("[EXPECTED] maker native balance should be 40 (settled from the escrow)")
}

// mustMakerFillAckAck builds a success ack whose inner TokenOrderAck is a
// market-maker fill designating maker as the settlement recipient.
func mustMakerFillAckAck(maker address) []byte {
	innerAck, err := z.EncodeTokenOrderAck(z.TokenOrderAck{
		FillType:    new(u256.Uint).SetBytes(z.FILL_TYPE_MARKETMAKER[:]),
		MarketMaker: []byte(maker.String()),
	})
	if err != nil {
		panic(err)
	}
	return mustSuccessAckAck(innerAck)
}

// --- encoding helpers (pure z calls, mirroring the e2e harness) ---

func forwardPathAck(prevDest, nextSource uint32) *u256.Uint {
	p, err := z.UpdateChannelPath(u256.Zero(), prevDest)
	if err != nil {
		panic(err)
	}
	p, err = z.UpdateChannelPath(p, nextSource)
	if err != nil {
		panic(err)
	}
	return p
}

func mustOrderInstructionAck(order z.TokenOrderV2) z.Instruction {
	operand, err := z.EncodeTokenOrderV2(order)
	if err != nil {
		panic(err)
	}
	return z.Instruction{Version: z.INSTR_VERSION_2, Opcode: z.OP_TOKEN_ORDER, Operand: operand}
}

func mustForwardInstructionAck(forward z.Forward) z.Instruction {
	operand, err := z.EncodeForward(forward)
	if err != nil {
		panic(err)
	}
	return z.Instruction{Version: z.INSTR_VERSION_0, Opcode: z.OP_FORWARD, Operand: operand}
}

func mustSuccessAckAck(inner []byte) []byte {
	ack, err := z.EncodeAck(z.Ack{Tag: new(u256.Uint).SetBytes(z.TAG_ACK_SUCCESS[:]), InnerAck: inner})
	if err != nil {
		panic(err)
	}
	return ack
}

// --- permissive mock light client (accepts any proof) ---

type fwdAckMockLightClient struct{}

func (m *fwdAckMockLightClient) VerifyMembership(uint64, []byte, []byte, []byte) error { return nil }
func (m *fwdAckMockLightClient) VerifyNonMembership(uint64, []byte, []byte) error      { return nil }
func (m *fwdAckMockLightClient) GetTimestamp() types.Timestamp                         { return types.Timestamp(1) }

func (m *fwdAckMockLightClient) GetTimestampAtHeight(uint64) (types.Timestamp, error) {
	return types.Timestamp(1), nil
}
func (m *fwdAckMockLightClient) GetLatestHeight() uint64        { return 1 }
func (m *fwdAckMockLightClient) GetCounterpartyChainID() string { return "mock-chain" }
func (m *fwdAckMockLightClient) Status() lightclient.Status     { return lightclient.Active }

func (m *fwdAckMockLightClient) VerifyHeader(_ address, header []byte, _ address) (types.StateUpdate, error) {
	return types.StateUpdate{Height: 1, ClientStateBytes: header, ConsensusStateBytes: header}, nil
}

func (m *fwdAckMockLightClient) VerifyCreation(address, address) (types.ClientCreationResult, error) {
	return types.ClientCreationResult{}, nil
}

func (m *fwdAckMockLightClient) Misbehaviour(address, []byte, address) ([]byte, error) {
	return nil, fwdAckMockError("mock: misbehaviour unsupported")
}

type fwdAckMockError string

func (e fwdAckMockError) Error() string { return string(e) }

// Output:
// [SCENARIO] 1. Bootstrap IBC host and open client/connection/channel
// [INFO] handshake opened: client=1 connection=1 channel=1
// [EXPECTED] client should be 1
// [EXPECTED] connection should be 1
// [EXPECTED] channel should be 1
//
// [SCENARIO] 2. Send a top-level OP_FORWARD wrapping a native ESCROW order, locking 40ugnot
// [INFO] send produced packet on channel: 1
// [INFO] proxy native escrow balance: 40
// [EXPECTED] send should succeed: attached 40ugnot covers the escrow order
// [EXPECTED] proxy native escrow balance should be 40 (locked)
//
// [SCENARIO] 3. A market-maker-fill ack on the top-level forward settles the escrow to the maker
// [INFO] proxy native escrow balance: 0
// [INFO] sender native balance: 0
// [INFO] maker native balance: 40
// [EXPECTED] proxy native escrow balance should be 0 (released to the maker)
// [EXPECTED] sender native balance should be 0 (unchanged: not refunded)
// [EXPECTED] maker native balance should be 40 (settled from the escrow)
