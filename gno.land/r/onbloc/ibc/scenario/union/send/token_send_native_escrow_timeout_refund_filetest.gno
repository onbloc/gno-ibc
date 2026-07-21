// PKGPATH: gno.land/r/onbloc/ibc/scenario/union/send
package send

// token_send_native_escrow_timeout_refund_filetest walks a native-coin ucs03-zkgm
// ESCROW send with a future timeout; the counterparty never receives the
// packet, the chain advances past the timeout (testing.SkipHeights, 5s per
// block), and a proven timeout refunds the escrowed native asset back to the
// sender. The packet timeout is checked against the light client's reported
// timestamp, so this file uses a block-time light client whose timestamp follows
// the (skipped) chain time, instead of the fixed-timestamp permissive mock used
// by the other send/ scenarios.

import (
	"chain"
	"chain/banker"
	"testing"
	"time"

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
	blockClockType = types.ClientType("scenario-block-clock-lc")
)

func main(cur realm) {
	println("[SCENARIO] 1. Bootstrap IBC host (block-time LC) and open client/connection/channel")
	channelId := bootstrap(cur)
	println("")

	println("[SCENARIO] 2. Send native ESCROW order locking 40ugnot with a future timeout")
	sendPacket := sendNativeEscrowOrder(cur, channelId)
	println("")

	println("[SCENARIO] 3. Advance the chain past the timeout and prove it: escrow refunded")
	timeoutRefund(cur, sendPacket)
}

// bootstrap installs the core/zkgm impls, grants the admin the relayer role, and
// opens a client/connection/channel backed by a block-time light client (its
// timestamp follows the chain's, so a skipped-past timeout is provable).
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

	ufmt.Printf("[INFO] handshake opened: client=%s connection=%s channel=%s\n", clientId.String(), connectionId.String(), channelId.String())
	ufmt.Println("[EXPECTED] client should be 1")
	ufmt.Println("[EXPECTED] connection should be 1")
	ufmt.Println("[EXPECTED] channel should be 1")

	return channelId
}

// sendNativeEscrowOrder sends a native ESCROW order funded by attached
// coins, with a timeout 10s in the (current) future. Native ugnot needs no
// TokenMetadata: verifyMetadataDecimals only checks a registered grc20 or a held
// voucher's origin decimals, and ugnot is neither, so Metadata is left empty.
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
	// timeout 10s in the (current) future; SkipHeights below advances past it.
	sendPacket := zkgm.Send(cross(cur), channelId, timeoutIn(10), [32]byte{}, mustOrderInstruction(order))

	bk := banker.NewReadonlyBanker()
	ufmt.Printf("[INFO] send produced packet on channel: %s\n", sendPacket.SourceChannelId.String())
	ufmt.Printf("[INFO] proxy native escrow balance: %d\n", bk.GetCoins(proxy).AmountOf("ugnot"))
	ufmt.Println("[EXPECTED] send should succeed: attached 40ugnot covers the escrow order")
	ufmt.Println("[EXPECTED] proxy native escrow balance should be 40 (locked)")

	return sendPacket
}

// timeoutRefund advances the chain past the packet's timeout and proves it: the
// escrowed native asset is released back to the original sender.
func timeoutRefund(cur realm, sendPacket types.Packet) {
	bk := banker.NewReadonlyBanker()
	proxy := zkgm.ProxyAddress()

	testing.SkipHeights(3) // 3 blocks * 5s = 15s, past the 10s timeout

	testing.SetRealm(testing.NewUserRealm(adminAddr))
	core.PacketTimeout(cross(cur), types.NewMsgPacketTimeout(sendPacket, nil, 1))

	ufmt.Printf("[INFO] proxy native escrow balance: %d\n", bk.GetCoins(proxy).AmountOf("ugnot"))
	ufmt.Printf("[INFO] sender native balance: %d\n", bk.GetCoins(senderAddr).AmountOf("ugnot"))
	ufmt.Println("[EXPECTED] proxy native escrow balance should be 0 (refunded)")
	ufmt.Println("[EXPECTED] sender native balance should be 40 (escrow refunded back)")
}

// --- timeout helpers (nanoseconds, relative to the current block time) ---

func timeoutIn(seconds int64) types.Timestamp {
	return types.Timestamp(uint64(time.Now().UnixNano()) + uint64(seconds)*1_000_000_000)
}

// --- encoding helpers (pure z calls, mirroring the e2e harness) ---

func mustOrderInstruction(order z.TokenOrderV2) z.Instruction {
	operand, err := z.EncodeTokenOrderV2(order)
	if err != nil {
		panic(err)
	}
	return z.Instruction{Version: z.INSTR_VERSION_2, Opcode: z.OP_TOKEN_ORDER, Operand: operand}
}

// --- block-time light client: its timestamp follows the (skipped) chain time, so a
// packet whose timeout has passed in chain time is provably timed out ---

type blockClockLightClient struct{}

func (m *blockClockLightClient) VerifyMembership(uint64, []byte, []byte, []byte) error { return nil }
func (m *blockClockLightClient) VerifyNonMembership(uint64, []byte, []byte) error      { return nil }
func (m *blockClockLightClient) GetTimestamp() types.Timestamp                         { return nowTs() }
func (m *blockClockLightClient) GetTimestampAtHeight(uint64) (types.Timestamp, error) {
	return nowTs(), nil
}
func (m *blockClockLightClient) GetLatestHeight() uint64        { return 1 }
func (m *blockClockLightClient) GetCounterpartyChainID() string { return "block-clock-chain" }
func (m *blockClockLightClient) Status() lightclient.Status     { return lightclient.Active }

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
// [SCENARIO] 1. Bootstrap IBC host (block-time LC) and open client/connection/channel
// [INFO] handshake opened: client=1 connection=1 channel=1
// [EXPECTED] client should be 1
// [EXPECTED] connection should be 1
// [EXPECTED] channel should be 1
//
// [SCENARIO] 2. Send native ESCROW order locking 40ugnot with a future timeout
// [INFO] send produced packet on channel: 1
// [INFO] proxy native escrow balance: 40
// [EXPECTED] send should succeed: attached 40ugnot covers the escrow order
// [EXPECTED] proxy native escrow balance should be 40 (locked)
//
// [SCENARIO] 3. Advance the chain past the timeout and prove it: escrow refunded
// [INFO] proxy native escrow balance: 0
// [INFO] sender native balance: 40
// [EXPECTED] proxy native escrow balance should be 0 (refunded)
// [EXPECTED] sender native balance should be 40 (escrow refunded back)
