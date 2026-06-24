// PKGPATH: gno.land/r/onbloc/ibc/scenario/union
package union

// token_send_by_ucs03_zkgm_filetest walks a full ucs03-zkgm token send through the
// upgradeable union IBC host (permissive mock light client) and asserts the escrowed
// token stays locked in the proxy after the acknowledgement.

import (
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
	// --- SCENARIO 1: bootstrap (admin) — kept inline so each core call is a
	// direct origin call: runtime.AssertOriginCall requires <= 2 call frames. ---
	ufmt.Println("[SCENARIO] 1. Bootstrap IBC host and open client/connection/channel")
	testing.SetRealm(testing.NewUserRealm(adminAddr))
	core.UpdateImpl(cross(cur), coreImplPath)
	zkgm.UpdateImpl(cross(cur), zkgmImplPath)
	zkgm.SetRateLimitDisabled(cross(cur), true)
	zkgm.RegisterCoreApp(cross(cur))

	// The relayer-gated host entrypoints require RELAYER. Grant it to the admin so
	// this single-actor scenario can drive the full flow.
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

	// --- SCENARIO 2: fund the sender with a wrapped voucher via an INITIALIZE recv ---
	ufmt.Println("")
	ufmt.Println("[SCENARIO] 2. Fund sender with wrapped voucher via INITIALIZE recv (amount 100)")
	meta := mustTokenMetadata("grc20", z.TokenInitializer{Name: "Gno Token", Symbol: "GNOT", Decimals: 6})
	quoteToken := z.PredictWrappedTokenV2(u256.Zero(), uint32(channelId), []byte("ugnot"), z.MetadataImage(mustDecodeMeta(meta)))
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
	core.PacketRecv(cross(cur), core.NewMsgPacketRecv([]types.Packet{initPacket}, [][]byte{nil}, nil, 1))

	// Balances are read back through the proxy's VoucherBalanceOf, the stable public
	// surface for wrapped-voucher balances (proxy-owned escrow amount).
	ufmt.Printf("[INFO] minted token (wrapped voucher): %s\n", quoteToken)
	ufmt.Println("[INFO] minted token wraps base token: ugnot")
	ufmt.Printf("[INFO] minted to sender %s, balance: %d\n", senderAddr.String(), zkgm.VoucherBalanceOf(quoteToken, senderAddr))
	ufmt.Println("[EXPECTED] minted token should be the ibc/ wrapped voucher of base ugnot")
	ufmt.Println("[EXPECTED] sender voucher balance should be 100 (full INITIALIZE amount minted)")

	// --- SCENARIO 3: send the ESCROW order that locks 40 of the voucher ---
	ufmt.Println("")
	ufmt.Println("[SCENARIO] 3. Send ESCROW order locking 40 of the voucher")
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

	ufmt.Printf("[INFO] locked token (escrowed into proxy): %s\n", quoteToken)
	ufmt.Printf("[INFO] locked into proxy escrow %s\n", zkgm.ProxyAddress().String())
	ufmt.Printf("[INFO] sender voucher balance: %d\n", zkgm.VoucherBalanceOf(quoteToken, senderAddr))
	ufmt.Printf("[INFO] proxy escrow balance: %d\n", zkgm.VoucherBalanceOf(quoteToken, zkgm.ProxyAddress()))
	ufmt.Println("[EXPECTED] locked token should be the same ibc/ voucher (moved from sender to proxy)")
	ufmt.Println("[EXPECTED] sender voucher balance should be 60 (100 - 40 escrowed)")
	ufmt.Println("[EXPECTED] proxy escrow balance should be 40 (locked)")

	// --- SCENARIO 4: ack — protocol-fill success is a no-op for an escrow, so the lock holds ---
	ufmt.Println("")
	ufmt.Println("[SCENARIO] 4. Acknowledge with protocol-fill success (no-op for escrow)")
	ack := mustSuccessAck(mustProtocolTokenOrderAck())

	testing.SetRealm(testing.NewUserRealm(adminAddr))
	core.PacketAcknowledgement(cross(cur), core.NewMsgPacketAcknowledgement([]types.Packet{sendPacket}, [][]byte{ack}, nil, 1))

	ufmt.Printf("[INFO] locked token still held by proxy: %s\n", quoteToken)
	ufmt.Printf("[INFO] sender voucher balance: %d\n", zkgm.VoucherBalanceOf(quoteToken, senderAddr))
	ufmt.Printf("[INFO] proxy escrow balance: %d\n", zkgm.VoucherBalanceOf(quoteToken, zkgm.ProxyAddress()))
	ufmt.Println("[EXPECTED] sender voucher balance should be 60 (unchanged: escrow stays locked)")
	ufmt.Println("[EXPECTED] proxy escrow balance should be 40 (unchanged: escrow stays locked)")
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
// [SCENARIO] 2. Fund sender with wrapped voucher via INITIALIZE recv (amount 100)
// [INFO] minted token (wrapped voucher): ibc/e03a8753fa7f41c282b15cdc0343f660e6e65845
// [INFO] minted token wraps base token: ugnot
// [INFO] minted to sender g1wymu47drhr0kuq2098m792lytgtj2nyx77yrsm, balance: 100
// [EXPECTED] minted token should be the ibc/ wrapped voucher of base ugnot
// [EXPECTED] sender voucher balance should be 100 (full INITIALIZE amount minted)
//
// [SCENARIO] 3. Send ESCROW order locking 40 of the voucher
// [INFO] locked token (escrowed into proxy): ibc/e03a8753fa7f41c282b15cdc0343f660e6e65845
// [INFO] locked into proxy escrow g182p37d0cyvsvqpv49lqtphpj3jswwqtuyl4qyy
// [INFO] sender voucher balance: 60
// [INFO] proxy escrow balance: 40
// [EXPECTED] locked token should be the same ibc/ voucher (moved from sender to proxy)
// [EXPECTED] sender voucher balance should be 60 (100 - 40 escrowed)
// [EXPECTED] proxy escrow balance should be 40 (locked)
//
// [SCENARIO] 4. Acknowledge with protocol-fill success (no-op for escrow)
// [INFO] locked token still held by proxy: ibc/e03a8753fa7f41c282b15cdc0343f660e6e65845
// [INFO] sender voucher balance: 60
// [INFO] proxy escrow balance: 40
// [EXPECTED] sender voucher balance should be 60 (unchanged: escrow stays locked)
// [EXPECTED] proxy escrow balance should be 40 (unchanged: escrow stays locked)
