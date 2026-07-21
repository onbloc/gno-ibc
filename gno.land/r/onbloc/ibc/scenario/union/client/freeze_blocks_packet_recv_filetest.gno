// PKGPATH: gno.land/r/onbloc/ibc/scenario/union/client
package client

// freeze_blocks_packet_recv_filetest is the EXCEPTION-path client
// scenario for the packet-recv proof-verification gate. AGENTS.md requires
// that frozen or expired clients cannot be used for membership or
// non-membership proof verification. freeze_blocks_client_ops_filetest already
// proves a frozen client rejects a verified UpdateClient; this file proves the
// same gate on the actual packet path: PacketRecv (core/v1 packet.gno)
// resolves the connection's client and calls getActiveClient, which rejects
// with "client is not active" (client.gno) BEFORE VerifyMembership ever runs
// — even though this file's light client's VerifyMembership always returns
// nil (would happily "prove" anything). A baseline recv succeeds while the
// client is Active (a real mint, proving the whole zkgm path works), then a
// misbehaviour proof freezes the client, and a second recv attempt is
// rejected before any proof is consulted.

import (
	"testing"

	"gno.land/p/nt/ufmt/v0"
	"gno.land/p/onbloc/ibc/union/lightclient"
	types "gno.land/p/onbloc/ibc/union/types"
	z "gno.land/p/onbloc/ibc/union/zkgm"

	u256 "gno.land/p/gnoswap/uint256"

	"gno.land/r/onbloc/ibc/union/access"
	zkgm "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm"
	_ "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/v1"
	core "gno.land/r/onbloc/ibc/union/core"
	_ "gno.land/r/onbloc/ibc/union/core/v1"
)

const (
	coreImplPath = "gno.land/r/onbloc/ibc/union/core/v1"
	zkgmImplPath = "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/v1"

	adminAddr     = address("g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5")
	receiverAddr  = address("g1dyxy88p94acjnm8dmu9tfj2mv2ncvx83cagllu")
	freezableType = types.ClientType("scenario-freezable-lc")
)

// frozen models the safety stop: once a valid misbehaviour is processed the
// client reports Frozen and stays there until an admin rebuilds it.
var frozen bool

func main(cur realm) {
	println("[SCENARIO] 1. Bootstrap IBC host (freezable LC) and open a zkgm channel")
	channelId := bootstrap(cur)
	println("")

	meta := mustTokenMetadata("grc20", z.TokenInitializer{Name: "Gno Token", Symbol: "GNOT", Decimals: 6})
	quoteToken := z.PredictWrappedTokenV2(u256.Zero(), uint32(channelId), []byte("ugnot"), z.MetadataImage(mustDecodeMeta(meta)))

	println("[SCENARIO] 2. Baseline: a recv succeeds while the client is Active")
	receiveInitializeOrder(cur, channelId, quoteToken, meta)
	println("")

	println("[SCENARIO] 3. A relayer submits a valid misbehaviour proof: the client freezes")
	submitMisbehaviour(cur)
	println("")

	println("[SCENARIO] 4. A further recv is rejected before any proof is consulted")
	attemptReceiveEscrowOrder(cur, channelId, quoteToken)
}

func bootstrap(cur realm) types.ChannelId {
	testing.SetRealm(testing.NewUserRealm(adminAddr))
	core.UpdateImpl(cross(cur), coreImplPath)
	zkgm.UpdateImpl(cross(cur), zkgmImplPath)
	zkgm.SetRateLimitDisabled(cross(cur), true)
	zkgm.RegisterCoreApp(cross(cur))
	access.GrantRole(cross(cur), access.RelayerRole, adminAddr)

	core.RegisterClient(cross(cur), freezableType, func(_, _ []byte) (lightclient.Interface, error) {
		return &freezableClient{}, nil
	})
	core.CreateClient(cross(cur), core.NewMsgCreateClient(freezableType, nil, nil))
	clientId := types.ClientId(1)

	core.ConnectionOpenInit(cross(cur), core.NewMsgConnectionOpenInit(clientId, types.ClientId(99)))
	connectionId := types.ConnectionId(1)
	core.ConnectionOpenAck(cross(cur), core.NewMsgConnectionOpenAck(connectionId, types.ConnectionId(77), nil, 1))

	portId := []byte(zkgm.ProxyPkgPath())
	core.ChannelOpenInit(cross(cur), core.NewMsgChannelOpenInit(portId, portId, connectionId, zkgm.Version, "g1relayer"))
	channelId := types.ChannelId(1)
	core.ChannelOpenAck(cross(cur), core.NewMsgChannelOpenAck(channelId, zkgm.Version, types.ChannelId(2), nil, 1, "g1relayer"))
	return channelId
}

func receiveInitializeOrder(cur realm, channelId types.ChannelId, quoteToken string, meta []byte) {
	order := z.TokenOrderV2{
		Sender:      []byte("remote-sender"),
		Receiver:    []byte(receiverAddr.String()),
		BaseToken:   []byte("ugnot"),
		BaseAmount:  u256.NewUint(100),
		QuoteToken:  []byte(quoteToken),
		QuoteAmount: u256.NewUint(100),
		Kind:        z.TOKEN_ORDER_KIND_INITIALIZE,
		Metadata:    meta,
	}
	packet := core.NewPacket(types.ChannelId(2), channelId, mustPacketData(mustOrderInstruction(order)), types.Timestamp(1<<62))

	testing.SetRealm(testing.NewUserRealm(adminAddr))
	core.PacketRecv(cross(cur), core.NewMsgPacketRecv([]types.Packet{packet}, [][]byte{nil}, nil, 1))

	ufmt.Printf("[INFO] receiver voucher balance: %d\n", zkgm.VoucherBalanceOf(quoteToken, receiverAddr))
	ufmt.Println("[EXPECTED] receiver voucher balance should be 100 (client Active: proof accepted, mint succeeds)")
}

func submitMisbehaviour(cur realm) {
	testing.SetRealm(testing.NewUserRealm(adminAddr))
	core.Misbehaviour(cross(cur), types.NewMsgMisbehaviour(types.ClientId(1), []byte("double-sign"), ""))

	status, _ := core.GetStatus(types.ClientId(1))
	ufmt.Printf("[INFO] client status: %s\n", statusLabel(status))
	ufmt.Println("[EXPECTED] status should be Frozen")
}

// attemptReceiveEscrowOrder submits a second recv (a different Kind, so it
// cannot be confused with the baseline's commitment) while the client is
// frozen; core's getActiveClient rejects it with "client is not active"
// before VerifyMembership is ever called.
func attemptReceiveEscrowOrder(cur realm, channelId types.ChannelId, quoteToken string) {
	order := z.TokenOrderV2{
		Sender:      []byte("remote-sender"),
		Receiver:    []byte(receiverAddr.String()),
		BaseToken:   []byte("ugnot"),
		BaseAmount:  u256.NewUint(50),
		QuoteToken:  []byte(quoteToken),
		QuoteAmount: u256.NewUint(50),
		Kind:        z.TOKEN_ORDER_KIND_ESCROW,
	}
	packet := core.NewPacket(types.ChannelId(2), channelId, mustPacketData(mustOrderInstruction(order)), types.Timestamp(1<<62))

	testing.SetRealm(testing.NewUserRealm(adminAddr))
	core.PacketRecv(cross(cur), core.NewMsgPacketRecv([]types.Packet{packet}, [][]byte{nil}, nil, 1))
}

func statusLabel(s types.Status) string {
	switch s {
	case types.StatusActive:
		return "Active"
	case types.StatusExpired:
		return "Expired"
	case types.StatusFrozen:
		return "Frozen"
	default:
		return "Unknown"
	}
}

// --- encoding helpers ---

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

// --- freezable mock light client (Frozen while the package `frozen` flag is set) ---

type freezableClient struct{}

func (m *freezableClient) VerifyMembership(uint64, []byte, []byte, []byte) error { return nil }
func (m *freezableClient) VerifyNonMembership(uint64, []byte, []byte) error      { return nil }
func (m *freezableClient) GetTimestamp() types.Timestamp                         { return types.Timestamp(1) }
func (m *freezableClient) GetTimestampAtHeight(uint64) (types.Timestamp, error) {
	return types.Timestamp(1), nil
}
func (m *freezableClient) GetLatestHeight() uint64        { return 1 }
func (m *freezableClient) GetCounterpartyChainID() string { return "freezable-chain" }

func (m *freezableClient) Status() lightclient.Status {
	if frozen {
		return lightclient.Frozen
	}
	return lightclient.Active
}

func (m *freezableClient) VerifyHeader(_ address, header []byte, _ address) (types.StateUpdate, error) {
	return types.StateUpdate{Height: 1, ClientStateBytes: header, ConsensusStateBytes: header}, nil
}

func (m *freezableClient) VerifyCreation(address, address) (types.ClientCreationResult, error) {
	return types.ClientCreationResult{}, nil
}

// Misbehaviour proof is accepted and freezes the client; returning non-empty
// bytes makes core persist the frozen client-state mirror.
func (m *freezableClient) Misbehaviour(address, []byte, address) ([]byte, error) {
	frozen = true
	return []byte("frozen-client-state"), nil
}

// Output:
// [SCENARIO] 1. Bootstrap IBC host (freezable LC) and open a zkgm channel
//
// [SCENARIO] 2. Baseline: a recv succeeds while the client is Active
// [INFO] receiver voucher balance: 100
// [EXPECTED] receiver voucher balance should be 100 (client Active: proof accepted, mint succeeds)
//
// [SCENARIO] 3. A relayer submits a valid misbehaviour proof: the client freezes
// [INFO] client status: Frozen
// [EXPECTED] status should be Frozen
//
// [SCENARIO] 4. A further recv is rejected before any proof is consulted

// Error:
// client is not active
