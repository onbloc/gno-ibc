// PKGPATH: gno.land/r/onbloc/ibc/scenario/union/forward
package forward

// send_forward_escrow_protocol_fill_ack_filetest sends a top-level OP_FORWARD
// wrapping a native ESCROW order, then acks it with a protocol fill:
// acknowledgeTokenOrderV2 treats this as a no-op (escrow stays locked backing
// the destination voucher), unlike a market-maker fill which releases it.
// reference (_acknowledgeForward): https://github.com/unionlabs/union/blob/d91c5e94354e15801bd5f82dc658eae3b79f2dad/evm/contracts/apps/ucs/03-zkgm/Zkgm.sol#L688-L707

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
	coreImplPathProto = "gno.land/r/onbloc/ibc/union/core/v1"
	zkgmImplPathProto = "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/v1"

	adminAddrProto   = address("g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5")
	senderAddrProto  = address("g1wymu47drhr0kuq2098m792lytgtj2nyx77yrsm")
	mockClientProto  = types.ClientType("scenario-fwd-proto-mock-lc")
	fwdProtoPrevDest = uint32(9)
	fwdProtoNextSrc  = uint32(10)
)

func main(cur realm) {
	println("[SCENARIO] 1. Bootstrap IBC host and open client/connection/channel")
	channelId := bootstrapProto(cur)
	println("")

	println("[SCENARIO] 2. Send a top-level OP_FORWARD wrapping a native ESCROW order, locking 40ugnot")
	sendPacket := sendTopLevelForwardOrderProto(cur, channelId)
	println("")

	println("[SCENARIO] 3. A protocol-fill ack on the top-level forward is a no-op: escrow stays locked")
	acknowledgeProtocolFill(cur, sendPacket)
}

// bootstrapProto installs the core/zkgm impls, grants the admin the relayer
// role, and opens a client/connection/channel backed by the permissive mock
// light client.
func bootstrapProto(cur realm) types.ChannelId {
	testing.SetRealm(testing.NewUserRealm(adminAddrProto))
	core.UpdateImpl(cross(cur), coreImplPathProto)
	zkgm.UpdateImpl(cross(cur), zkgmImplPathProto)
	zkgm.SetRateLimitDisabled(cross(cur), true)
	zkgm.RegisterCoreApp(cross(cur))
	access.GrantRole(cross(cur), access.RelayerRole, adminAddrProto)

	core.RegisterClient(cross(cur), mockClientProto, func(_, _ []byte) (lightclient.Interface, error) {
		return &fwdProtoMockLightClient{}, nil
	})
	core.CreateClient(cross(cur), core.NewMsgCreateClient(mockClientProto, nil, nil))
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

// sendTopLevelForwardOrderProto sends a top-level OP_FORWARD instruction
// that wraps a native ESCROW TokenOrder, funded by attached coins.
func sendTopLevelForwardOrderProto(cur realm, channelId types.ChannelId) types.Packet {
	order := z.TokenOrderV2{
		Sender:      []byte(senderAddrProto.String()),
		Receiver:    []byte("remote-receiver"),
		BaseToken:   []byte("ugnot"),
		BaseAmount:  u256.NewUint(40),
		QuoteToken:  []byte("remote-ugnot"),
		QuoteAmount: u256.NewUint(40),
		Kind:        z.TOKEN_ORDER_KIND_ESCROW,
	}
	forward := z.Forward{
		Path:             forwardPathProto(fwdProtoPrevDest, fwdProtoNextSrc),
		TimeoutTimestamp: 1 << 62,
		Instruction:      mustOrderInstructionProto(order),
	}

	proxy := zkgm.ProxyAddress()
	testing.IssueCoins(proxy, chain.NewCoins(chain.NewCoin("ugnot", 40)))

	testing.SetRealm(testing.NewUserRealm(senderAddrProto))
	testing.SetOriginSend(chain.NewCoins(chain.NewCoin("ugnot", 40)))
	sendPacket := zkgm.Send(cross(cur), channelId, types.Timestamp(1<<62), [32]byte{}, mustForwardInstructionProto(forward))

	bk := banker.NewReadonlyBanker()
	ufmt.Printf("[INFO] send produced packet on channel: %s\n", sendPacket.SourceChannelId.String())
	ufmt.Printf("[INFO] proxy native escrow balance: %d\n", bk.GetCoin(proxy, "ugnot"))
	ufmt.Println("[EXPECTED] send should succeed: attached 40ugnot covers the escrow order")
	ufmt.Println("[EXPECTED] proxy native escrow balance should be 40 (locked)")

	return sendPacket
}

// acknowledgeProtocolFill acknowledges the top-level forward packet with a
// protocol-fill ack.
func acknowledgeProtocolFill(cur realm, sendPacket types.Packet) {
	bk := banker.NewReadonlyBanker()
	proxy := zkgm.ProxyAddress()

	testing.SetRealm(testing.NewUserRealm(adminAddrProto))
	core.PacketAcknowledgement(cross(cur), core.NewMsgPacketAcknowledgement([]types.Packet{sendPacket}, [][]byte{mustProtocolFillAckProto()}, nil, 1))

	ufmt.Printf("[INFO] proxy native escrow balance: %d\n", bk.GetCoin(proxy, "ugnot"))
	ufmt.Printf("[INFO] sender native balance: %d\n", bk.GetCoin(senderAddrProto, "ugnot"))
	ufmt.Println("[EXPECTED] proxy native escrow balance should be 40 (unchanged: protocol fill is a no-op for escrow)")
	ufmt.Println("[EXPECTED] sender native balance should be 0 (unchanged: not refunded)")
}

// mustProtocolFillAckProto builds a success ack whose inner TokenOrderAck is
// a protocol fill (no market maker involved).
func mustProtocolFillAckProto() []byte {
	innerAck, err := z.EncodeTokenOrderAck(z.TokenOrderAck{
		FillType: new(u256.Uint).SetBytes(z.FILL_TYPE_PROTOCOL[:]),
	})
	if err != nil {
		panic(err)
	}
	return mustSuccessAckProto(innerAck)
}

// --- encoding helpers (pure z calls, mirroring the e2e harness) ---

func forwardPathProto(prevDest, nextSource uint32) *u256.Uint {
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

func mustOrderInstructionProto(order z.TokenOrderV2) z.Instruction {
	operand, err := z.EncodeTokenOrderV2(order)
	if err != nil {
		panic(err)
	}
	return z.Instruction{Version: z.INSTR_VERSION_2, Opcode: z.OP_TOKEN_ORDER, Operand: operand}
}

func mustForwardInstructionProto(forward z.Forward) z.Instruction {
	operand, err := z.EncodeForward(forward)
	if err != nil {
		panic(err)
	}
	return z.Instruction{Version: z.INSTR_VERSION_0, Opcode: z.OP_FORWARD, Operand: operand}
}

func mustSuccessAckProto(inner []byte) []byte {
	ack, err := z.EncodeAck(z.Ack{Tag: new(u256.Uint).SetBytes(z.TAG_ACK_SUCCESS[:]), InnerAck: inner})
	if err != nil {
		panic(err)
	}
	return ack
}

// --- permissive mock light client (accepts any proof) ---

type fwdProtoMockLightClient struct{}

func (m *fwdProtoMockLightClient) VerifyMembership(uint64, []byte, []byte, []byte) error { return nil }
func (m *fwdProtoMockLightClient) VerifyNonMembership(uint64, []byte, []byte) error      { return nil }
func (m *fwdProtoMockLightClient) GetTimestamp() types.Timestamp                         { return types.Timestamp(1) }

func (m *fwdProtoMockLightClient) GetTimestampAtHeight(uint64) (types.Timestamp, error) {
	return types.Timestamp(1), nil
}
func (m *fwdProtoMockLightClient) GetLatestHeight() uint64        { return 1 }
func (m *fwdProtoMockLightClient) GetCounterpartyChainID() string { return "mock-chain" }
func (m *fwdProtoMockLightClient) Status() lightclient.Status     { return lightclient.Active }

func (m *fwdProtoMockLightClient) VerifyHeader(_ address, header []byte, _ address) (types.StateUpdate, error) {
	return types.StateUpdate{Height: 1, ClientStateBytes: header, ConsensusStateBytes: header}, nil
}

func (m *fwdProtoMockLightClient) VerifyCreation(address, address) (types.ClientCreationResult, error) {
	return types.ClientCreationResult{}, nil
}

func (m *fwdProtoMockLightClient) Misbehaviour(address, []byte, address) ([]byte, error) {
	return nil, fwdProtoMockError("mock: misbehaviour unsupported")
}

type fwdProtoMockError string

func (e fwdProtoMockError) Error() string { return string(e) }

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
// [SCENARIO] 3. A protocol-fill ack on the top-level forward is a no-op: escrow stays locked
// [INFO] proxy native escrow balance: 40
// [INFO] sender native balance: 0
// [EXPECTED] proxy native escrow balance should be 40 (unchanged: protocol fill is a no-op for escrow)
// [EXPECTED] sender native balance should be 0 (unchanged: not refunded)
