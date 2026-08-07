// PKGPATH: gno.land/r/onbloc/ibc/scenario/union/pause
package pause

// send_then_pause_unpause_timeout_filetest: timeout counterpart to
// send_then_pause_unpause_ack_filetest. Pausing doesn't cancel an in-flight
// send, so once unpaused the elapsed timeout still settles normally: escrow
// releases and the sender is refunded. Counterpart to
// send_then_pause_blocks_timeout_filetest (same timeout, still paused).
//
// Uses a block-time light client (not the other pause/ files' fixed-timestamp
// mock) so the timeout can actually be skipped past.

import (
	"chain"
	"chain/banker"
	"testing"
	"time"

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
	coreImplPath   = "gno.land/r/onbloc/ibc/union/core/v1"
	zkgmImplPath   = "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/v1"
	blockClockType = types.ClientType("scenario-block-clock-lc")

	adminAddr  = address("g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5")
	senderAddr = address("g1wymu47drhr0kuq2098m792lytgtj2nyx77yrsm")
)

func main(cur realm) {
	println("[SCENARIO] 1. Bootstrap IBC host and open a zkgm channel")
	channelId := bootstrap(cur)
	println("")

	println("[SCENARIO] 2. Send native ESCROW order locking 40ugnot, timeout in 10s")
	sendPacket := sendNativeEscrowOrder(cur, channelId)
	println("")

	println("[SCENARIO] 3. Skip past the timeout, then admin pauses and unpauses the app")
	testing.SkipHeights(3) // 3 blocks * 5s = 15s, past the 10s timeout
	pauseUnpause(cur)
	println("")

	println("[SCENARIO] 4. After unpause, the timeout settles normally: escrow refunded")
	timeoutRefund(cur, channelId, sendPacket)
}

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
	return channelId
}

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

	ufmt.Printf("[INFO] channel balance ledger before send: %s\n", channelBalanceOrZero(channelId, order.BaseToken, order.QuoteToken).ToString())

	testing.SetRealm(testing.NewUserRealm(senderAddr))
	testing.SetOriginSend(chain.NewCoins(chain.NewCoin("ugnot", 40)))
	sendPacket := zkgm.Send(cross(cur), channelId, timeoutIn(10), [32]byte{}, mustOrderInstruction(order))

	bk := banker.NewReadonlyBanker()
	ufmt.Printf("[INFO] proxy native escrow balance: %d\n", bk.GetCoins(proxy).AmountOf("ugnot"))
	ufmt.Printf("[INFO] channel balance ledger after send: %s\n", channelBalanceOrZero(channelId, order.BaseToken, order.QuoteToken).ToString())
	ufmt.Println("[EXPECTED] proxy native escrow balance should be 40 (locked)")
	ufmt.Println("[EXPECTED] channel balance ledger should be 40 (matches the escrowed order amount)")

	return sendPacket
}

// pauseUnpause flips the global pause switch on and back off. Pausable is admin-gated
// (the admin holds AdminRole), so SetRealm(admin) and the cross(cur) calls share this
// frame.
func pauseUnpause(cur realm) {
	testing.SetRealm(testing.NewUserRealm(adminAddr))
	zkgm.Pausable(cross(cur), true)
	ufmt.Println("[INFO] app paused by admin")
	zkgm.Pausable(cross(cur), false)
	ufmt.Println("[INFO] app unpaused by admin")
	ufmt.Println("[EXPECTED] both pause and unpause should succeed for the admin")
}

// timeoutRefund submits the packet's timeout after unpause: the escrowed
// native asset is released back to the original sender.
func timeoutRefund(cur realm, channelId types.ChannelId, sendPacket types.Packet) {
	bk := banker.NewReadonlyBanker()
	proxy := zkgm.ProxyAddress()

	testing.SetRealm(testing.NewUserRealm(adminAddr))
	core.PacketTimeout(cross(cur), types.NewMsgPacketTimeout(sendPacket, nil, 1))

	ufmt.Printf("[INFO] proxy native escrow balance: %d\n", bk.GetCoins(proxy).AmountOf("ugnot"))
	ufmt.Printf("[INFO] sender native balance: %d\n", bk.GetCoins(senderAddr).AmountOf("ugnot"))
	ufmt.Printf("[INFO] channel balance ledger after timeout: %s\n", channelBalanceOrZero(channelId, []byte("ugnot"), []byte("remote-ugnot")).ToString())
	ufmt.Println("[EXPECTED] proxy native escrow balance should be 0 (refunded)")
	ufmt.Println("[EXPECTED] sender native balance should be 40 (escrow refunded back)")
	ufmt.Println("[EXPECTED] channel balance ledger should be 0 (decreased back by the refunded 40; ledger and bank balance agree)")
}

// channelBalanceOrZero: GetChannelBalanceV2 returns "not found" (never
// escrowed) as an error rather than a stored zero; resolve it to u256.Zero().
func channelBalanceOrZero(channelId types.ChannelId, baseToken, quoteToken []byte) *u256.Uint {
	balance, err := zkgm.GetChannelBalanceV2(channelId, u256.Zero(), string(baseToken), quoteToken)
	if err != nil {
		return u256.Zero()
	}
	return balance
}

// --- timeout helper (nanoseconds, relative to the current block time) ---

func timeoutIn(seconds int64) types.Timestamp {
	return types.Timestamp(uint64(time.Now().UnixNano()) + uint64(seconds)*1_000_000_000)
}

// --- encoding helpers ---

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

func (m *blockClockLightClient) VerifyNonMembership(uint64, []byte, []byte) error { return nil }

func (m *blockClockLightClient) GetTimestamp() types.Timestamp { return nowTs() }

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
// [SCENARIO] 1. Bootstrap IBC host and open a zkgm channel
//
// [SCENARIO] 2. Send native ESCROW order locking 40ugnot, timeout in 10s
// [INFO] channel balance ledger before send: 0
// [INFO] proxy native escrow balance: 40
// [INFO] channel balance ledger after send: 40
// [EXPECTED] proxy native escrow balance should be 40 (locked)
// [EXPECTED] channel balance ledger should be 40 (matches the escrowed order amount)
//
// [SCENARIO] 3. Skip past the timeout, then admin pauses and unpauses the app
// [INFO] app paused by admin
// [INFO] app unpaused by admin
// [EXPECTED] both pause and unpause should succeed for the admin
//
// [SCENARIO] 4. After unpause, the timeout settles normally: escrow refunded
// [INFO] proxy native escrow balance: 0
// [INFO] sender native balance: 40
// [INFO] channel balance ledger after timeout: 0
// [EXPECTED] proxy native escrow balance should be 0 (refunded)
// [EXPECTED] sender native balance should be 40 (escrow refunded back)
// [EXPECTED] channel balance ledger should be 0 (decreased back by the refunded 40; ledger and bank balance agree)
