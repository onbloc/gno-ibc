// PKGPATH: gno.land/r/onbloc/ibc/scenario/union/relayer
package relayer

// timeout_by_any_relayer_refunds_sender_filetest is the BY-TYPE relayer scenario for
// timeout liveness and refund attribution (S-5.5). Timeout completion is not bound to
// the relayer that delivered or sent the packet: any authorized relayer can prove a
// timeout, and the refund always returns to the original sender (never to the relayer
// who submits it). This file escrows 40 from the sender, advances the chain past the
// timeout, and has a DIFFERENT relayer (not the sender) prove the timeout — the escrow
// is refunded to the sender, and the submitting relayer gains nothing.
//
// Note on "permissionless": core gates PacketTimeout on the relayer selector
// (RelayerSelectorPacketTimeout), so timeout is permissionless *among authorized
// relayers*, not callable by an arbitrary unauthorized address. This is the liveness
// guarantee (no single relayer can strand a packet) without opening an unauthenticated
// entrypoint.

import (
	"testing"
	"time"

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

	adminAddr        = address("g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5")
	senderAddr       = address("g1wymu47drhr0kuq2098m792lytgtj2nyx77yrsm")
	otherRelayerAddr = address("g1dyxy88p94acjnm8dmu9tfj2mv2ncvx83cagllu")
	blockClockType   = types.ClientType("scenario-block-clock-lc")
)

func main(cur realm) {
	println("[SCENARIO] 1. Bootstrap (block-time LC), open a channel, authorize a second relayer")
	channelId := bootstrap(cur)
	println("")

	meta := mustTokenMetadata("\xaf\x73\x9f\x34\xdd\xf9\x51\xcb\xc2\x4f\xdb\xba\x4f\x76\x21\x36\x88\xe1\x36\x27", z.TokenInitializer{Name: "Gno Token", Symbol: "GNOT", Decimals: 6})
	quoteToken := z.PredictWrappedTokenV2(u256.Zero(), uint32(channelId), []byte("ugnot"), z.MetadataImage(mustDecodeMeta(meta)))

	println("[SCENARIO] 2. Fund the sender with 100 of the voucher")
	fundSender(cur, channelId, quoteToken, meta)
	println("")

	println("[SCENARIO] 3. Sender escrows 40 with a near-future timeout")
	sendPacket := sendEscrow(cur, channelId, quoteToken)
	println("")

	println("[SCENARIO] 4. A different authorized relayer proves the timeout: the sender is refunded")
	timeoutByOtherRelayer(cur, sendPacket, quoteToken)
}

func bootstrap(cur realm) types.ChannelId {
	testing.SetRealm(testing.NewUserRealm(adminAddr))
	core.UpdateImpl(cross(cur), coreImplPath)
	zkgm.UpdateImpl(cross(cur), zkgmImplPath)
	zkgm.SetRateLimitDisabled(cross(cur), true)
	zkgm.RegisterCoreApp(cross(cur))
	access.GrantRole(cross(cur), access.RelayerRole, adminAddr)
	access.GrantRole(cross(cur), access.RelayerRole, otherRelayerAddr)

	core.RegisterClient(cross(cur), blockClockType, func(_, _ []byte) (lightclient.Interface, error) {
		return &blockClockLightClient{}, nil
	})
	core.CreateClient(cross(cur), core.NewMsgCreateClient(blockClockType, nil, nil))
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
	packet := core.NewPacket(types.ChannelId(2), channelId, mustPacketData(mustOrderInstruction(order)), futureTimeout())

	testing.SetRealm(testing.NewUserRealm(adminAddr))
	core.PacketRecv(cross(cur), core.NewMsgPacketRecv([]types.Packet{packet}, [][]byte{nil}, nil, 1))
	ufmt.Printf("[INFO] sender voucher balance: %d\n", zkgm.VoucherBalanceOf(quoteToken, senderAddr))
	ufmt.Println("[EXPECTED] 100")
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
	sendPacket := zkgm.Send(cross(cur), channelId, timeoutIn(10), [32]byte{}, mustOrderInstruction(order))
	ufmt.Printf("[INFO] sender voucher: %d, proxy escrow: %d\n", zkgm.VoucherBalanceOf(quoteToken, senderAddr), zkgm.VoucherBalanceOf(quoteToken, zkgm.ProxyAddress()))
	ufmt.Println("[EXPECTED] sender 100 -> 60, proxy escrow 0 -> 40")
	return sendPacket
}

func timeoutByOtherRelayer(cur realm, sendPacket types.Packet, quoteToken string) {
	otherBefore := zkgm.VoucherBalanceOf(quoteToken, otherRelayerAddr)
	senderBefore := zkgm.VoucherBalanceOf(quoteToken, senderAddr)

	testing.SkipHeights(3) // 3 * 5s = 15s, past the 10s timeout

	// The relayer that proves the timeout is NOT the sender; the refund still goes to the sender.
	testing.SetRealm(testing.NewUserRealm(otherRelayerAddr))
	core.PacketTimeout(cross(cur), types.NewMsgPacketTimeout(sendPacket, nil, 1))

	ufmt.Printf("[INFO] sender voucher: %d -> %d (delta +%d)\n", senderBefore, zkgm.VoucherBalanceOf(quoteToken, senderAddr), zkgm.VoucherBalanceOf(quoteToken, senderAddr)-senderBefore)
	ufmt.Printf("[INFO] submitting relayer voucher: %d -> %d (delta %d)\n", otherBefore, zkgm.VoucherBalanceOf(quoteToken, otherRelayerAddr), zkgm.VoucherBalanceOf(quoteToken, otherRelayerAddr)-otherBefore)
	ufmt.Println("[EXPECTED] refund returns to the sender (60 -> 100); the submitting relayer gains nothing")
}

// --- timeout helpers ---

func timeoutIn(seconds int64) types.Timestamp {
	return types.Timestamp(uint64(time.Now().UnixNano()) + uint64(seconds)*1_000_000_000)
}

func futureTimeout() types.Timestamp { return timeoutIn(3600) }

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

// --- block-time light client (timestamp follows skipped chain time) ---

type blockClockLightClient struct{}

func (m *blockClockLightClient) VerifyMembership(uint64, []byte, []byte, []byte) error { return nil }
func (m *blockClockLightClient) VerifyNonMembership(uint64, []byte, []byte) error      { return nil }
func (m *blockClockLightClient) GetTimestamp() types.Timestamp                         { return nowTs() }
func (m *blockClockLightClient) GetTimestampAtHeight(uint64) (types.Timestamp, error)  { return nowTs(), nil }
func (m *blockClockLightClient) GetLatestHeight() uint64                               { return 1 }
func (m *blockClockLightClient) GetCounterpartyChainID() string                        { return "block-clock-chain" }
func (m *blockClockLightClient) Status() lightclient.Status                            { return lightclient.Active }

func (m *blockClockLightClient) VerifyHeader(_ address, header []byte, _ address) (types.StateUpdate, error) {
	return types.StateUpdate{Height: 1, ClientStateBytes: header, ConsensusStateBytes: header}, nil
}

func (m *blockClockLightClient) VerifyCreation(address, address) (types.ClientCreationResult, error) {
	return types.ClientCreationResult{}, nil
}

func (m *blockClockLightClient) Misbehaviour(address, []byte, address) ([]byte, error) {
	return nil, mockError("block-clock: misbehaviour unsupported")
}

func nowTs() types.Timestamp { return types.Timestamp(uint64(time.Now().UnixNano())) }

type mockError string

func (e mockError) Error() string { return string(e) }

// Output:
// [SCENARIO] 1. Bootstrap (block-time LC), open a channel, authorize a second relayer
//
// [SCENARIO] 2. Fund the sender with 100 of the voucher
// [INFO] sender voucher balance: 100
// [EXPECTED] 100
//
// [SCENARIO] 3. Sender escrows 40 with a near-future timeout
// [INFO] sender voucher: 60, proxy escrow: 40
// [EXPECTED] sender 100 -> 60, proxy escrow 0 -> 40
//
// [SCENARIO] 4. A different authorized relayer proves the timeout: the sender is refunded
// [INFO] sender voucher: 60 -> 100 (delta +40)
// [INFO] submitting relayer voucher: 0 -> 0 (delta 0)
// [EXPECTED] refund returns to the sender (60 -> 100); the submitting relayer gains nothing
