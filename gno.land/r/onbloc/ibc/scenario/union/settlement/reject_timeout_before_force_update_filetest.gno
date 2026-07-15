// PKGPATH: gno.land/r/onbloc/ibc/scenario/union/settlement
package settlement

// reject_timeout_before_force_update_filetest proves the negative half of
// force_update_unblocks_timeout_filetest: while the manual-clock client is stalled
// before the packet expiry, PacketTimeout is rejected. The success-path file then
// proves the same timeout succeeds after ForceUpdateClient advances that clock.

import (
	"testing"

	"gno.land/p/nt/ufmt/v0"
	"gno.land/p/onbloc/ibc/union/lightclient"
	"gno.land/p/onbloc/ibc/union/types"
	z "gno.land/p/onbloc/ibc/union/zkgm"

	u256 "gno.land/p/gnoswap/uint256"

	"gno.land/r/onbloc/ibc/union/access"
	zkgm "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm"
	_ "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/v1"
	"gno.land/r/onbloc/ibc/union/core"
	_ "gno.land/r/onbloc/ibc/union/core/v1"
)

const (
	coreImplPath = "gno.land/r/onbloc/ibc/union/core/v1"
	zkgmImplPath = "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/v1"

	adminAddr  = address("g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5")
	senderAddr = address("g1wymu47drhr0kuq2098m792lytgtj2nyx77yrsm")
	manualType = types.ClientType("scenario-manual-clock-lc")

	stalledClock = uint64(1_000_000_000)
	packetExpiry = uint64(2_000_000_000)
)

var clientTime = stalledClock

func main(cur realm) {
	println("[SCENARIO] 1. Bootstrap IBC host (manual-clock LC) and open a zkgm channel")
	channelId := bootstrap(cur)
	println("")

	meta := mustTokenMetadata("\xaf\x73\x9f\x34\xdd\xf9\x51\xcb\xc2\x4f\xdb\xba\x4f\x76\x21\x36\x88\xe1\x36\x27", z.TokenInitializer{Name: "Gno Token", Symbol: "GNOT", Decimals: 6})
	quoteToken := z.PredictWrappedTokenV2(u256.Zero(), uint32(channelId), []byte("ugnot"), z.MetadataImage(mustDecodeMeta(meta)))

	println("[SCENARIO] 2. Fund the sender and ESCROW send 40 with timeout past the stalled clock")
	fundSender(cur, channelId, quoteToken, meta)
	sendPacket := sendEscrow(cur, channelId, quoteToken)
	ufmt.Printf("[INFO] stalled client clock=%d, packet timeout=%d (timeout > clock)\n", clientTime, packetExpiry)
	println("")

	println("[SCENARIO] 3. PacketTimeout before force-update is rejected")
	testing.SetRealm(testing.NewUserRealm(adminAddr))
	core.PacketTimeout(cross(cur), types.NewMsgPacketTimeout(sendPacket, nil, 1))
}

func bootstrap(cur realm) types.ChannelId {
	testing.SetRealm(testing.NewUserRealm(adminAddr))
	core.UpdateImpl(cross(cur), coreImplPath)
	zkgm.UpdateImpl(cross(cur), zkgmImplPath)
	zkgm.SetRateLimitDisabled(cross(cur), true)
	zkgm.RegisterCoreApp(cross(cur))
	access.GrantRole(cross(cur), access.RelayerRole, adminAddr)

	core.RegisterClient(cross(cur), manualType, func(_, _ []byte) (lightclient.Interface, error) {
		return &manualClockLightClient{}, nil
	})
	core.CreateClient(cross(cur), core.NewMsgCreateClient(manualType, nil, nil))
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

func fundSender(cur realm, channelId types.ChannelId, quoteToken string, meta []byte) {
	order := z.TokenOrderV2{
		Sender:      []byte("remote-sender"),
		Receiver:    []byte(senderAddr.String()),
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
	ufmt.Printf("[INFO] sender voucher balance: %d\n", zkgm.VoucherBalanceOf(quoteToken, senderAddr))
}

func sendEscrow(cur realm, channelId types.ChannelId, quoteToken string) types.Packet {
	order := z.TokenOrderV2{
		Sender:      []byte(senderAddr.String()),
		Receiver:    []byte("remote-receiver"),
		BaseToken:   []byte(quoteToken),
		BaseAmount:  u256.NewUint(40),
		QuoteToken:  []byte("ugnot"),
		QuoteAmount: u256.NewUint(40),
		Kind:        z.TOKEN_ORDER_KIND_ESCROW,
	}

	testing.SetRealm(testing.NewUserRealm(senderAddr))
	sendPacket := zkgm.Send(cross(cur), channelId, types.Timestamp(packetExpiry), [32]byte{}, mustOrderInstruction(order))
	ufmt.Printf("[INFO] sender voucher balance: %d, proxy escrow: %d\n", zkgm.VoucherBalanceOf(quoteToken, senderAddr), zkgm.VoucherBalanceOf(quoteToken, zkgm.ProxyAddress()))
	return sendPacket
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

// --- manual-clock light client ---

type manualClockLightClient struct{}

func (m *manualClockLightClient) VerifyMembership(uint64, []byte, []byte, []byte) error { return nil }
func (m *manualClockLightClient) VerifyNonMembership(uint64, []byte, []byte) error      { return nil }
func (m *manualClockLightClient) GetTimestamp() types.Timestamp                         { return types.Timestamp(clientTime) }
func (m *manualClockLightClient) GetTimestampAtHeight(uint64) (types.Timestamp, error) {
	return types.Timestamp(clientTime), nil
}
func (m *manualClockLightClient) GetLatestHeight() uint64        { return 1 }
func (m *manualClockLightClient) GetCounterpartyChainID() string { return "manual-clock-chain" }
func (m *manualClockLightClient) Status() lightclient.Status     { return lightclient.Active }

func (m *manualClockLightClient) VerifyHeader(_ address, header []byte, _ address) (types.StateUpdate, error) {
	return types.StateUpdate{Height: 1, ClientStateBytes: header, ConsensusStateBytes: header}, nil
}

func (m *manualClockLightClient) VerifyCreation(address, address) (types.ClientCreationResult, error) {
	return types.ClientCreationResult{}, nil
}

func (m *manualClockLightClient) Misbehaviour(address, []byte, address) ([]byte, error) {
	return nil, nil
}

// Output:
// [SCENARIO] 1. Bootstrap IBC host (manual-clock LC) and open a zkgm channel
//
// [SCENARIO] 2. Fund the sender and ESCROW send 40 with timeout past the stalled clock
// [INFO] sender voucher balance: 100
// [INFO] sender voucher balance: 60, proxy escrow: 40
// [INFO] stalled client clock=1000000000, packet timeout=2000000000 (timeout > clock)
//
// [SCENARIO] 3. PacketTimeout before force-update is rejected

// Error:
// packet timeout not reached
