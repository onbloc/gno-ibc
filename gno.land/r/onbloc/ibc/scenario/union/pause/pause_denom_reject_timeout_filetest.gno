// PKGPATH: gno.land/r/onbloc/ibc/scenario/union/pause
package pause

// reject_timeout_while_denom_paused_filetest is the EXCEPTION-path pause
// scenario for in-flight settlement via timeout, scoped to a single denom
// (mirrors send/token_send_native_escrow_timeout_refund_filetest, but pauses
// the denom before the timeout is proven instead of letting it refund). A
// sender has a native ESCROW send locked at the proxy with a short future
// timeout. The admin then pauses just that denom; once the chain advances
// past the timeout, submitting the proof (which would normally refund the
// escrow) is rejected before any funds move — refundV2 guards the paused
// denom the same way it does on the ack-failure path, since timeoutInternal
// calls it directly. The escrow stays locked. The rejection is the
// terminating panic ("denom paused"), matched by the // Error: directive.

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
	coreImplPath = "gno.land/r/onbloc/ibc/union/core/v1"
	zkgmImplPath = "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/v1"

	adminAddr      = address("g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5")
	senderAddr     = address("g1wymu47drhr0kuq2098m792lytgtj2nyx77yrsm")
	blockClockType = types.ClientType("scenario-block-clock-lc")

	pausedDenom = "ugnot"
)

func main(cur realm) {
	println("[SCENARIO] 1. Bootstrap IBC host (block-time LC) and open a zkgm channel")
	channelId := bootstrap(cur)
	println("")

	println("[SCENARIO] 2. Send native ESCROW order locking 40ugnot with a future timeout")
	sendPacket := sendNativeEscrowOrder(cur, channelId)
	println("")

	println("[SCENARIO] 3. Admin pauses only the ugnot denom")
	testing.SetRealm(testing.NewUserRealm(adminAddr))
	zkgm.PausableDenom(cross(cur), pausedDenom, true)
	println("[INFO] ugnot paused by admin")
	println("")

	println("[SCENARIO] 4. Advancing past the timeout and proving it while ugnot is paused is rejected")
	attemptTimeout(cur, sendPacket)
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
		BaseToken:   []byte(pausedDenom),
		BaseAmount:  u256.NewUint(40),
		QuoteToken:  []byte("remote-ugnot"),
		QuoteAmount: u256.NewUint(40),
		Kind:        z.TOKEN_ORDER_KIND_ESCROW,
	}

	proxy := zkgm.ProxyAddress()
	testing.IssueCoins(proxy, chain.NewCoins(chain.NewCoin(pausedDenom, 40)))

	testing.SetRealm(testing.NewUserRealm(senderAddr))
	testing.SetOriginSend(chain.NewCoins(chain.NewCoin(pausedDenom, 40)))
	// timeout 10s in the (current) future; SkipHeights below advances past it.
	sendPacket := zkgm.Send(cross(cur), channelId, timeoutIn(10), [32]byte{}, mustOrderInstruction(order))

	bk := banker.NewReadonlyBanker()
	ufmt.Printf("[INFO] proxy native escrow balance: %d\n", bk.GetCoin(proxy, pausedDenom))
	ufmt.Println("[EXPECTED] proxy native escrow balance should be 40 (locked)")

	return sendPacket
}

// attemptTimeout advances the chain past the packet's timeout and submits the
// proof while ugnot is paused; refundV2 rejects it with "denom paused" before
// the escrow can be refunded.
func attemptTimeout(cur realm, sendPacket types.Packet) {
	testing.SkipHeights(3) // 3 blocks * 5s = 15s, past the 10s timeout

	testing.SetRealm(testing.NewUserRealm(adminAddr))
	core.PacketTimeout(cross(cur), types.NewMsgPacketTimeout(sendPacket, nil, 1))
}

// --- timeout helpers (nanoseconds, relative to the current block time) ---

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
// [SCENARIO] 1. Bootstrap IBC host (block-time LC) and open a zkgm channel
//
// [SCENARIO] 2. Send native ESCROW order locking 40ugnot with a future timeout
// [INFO] proxy native escrow balance: 40
// [EXPECTED] proxy native escrow balance should be 40 (locked)
//
// [SCENARIO] 3. Admin pauses only the ugnot denom
// [INFO] ugnot paused by admin
//
// [SCENARIO] 4. Advancing past the timeout and proving it while ugnot is paused is rejected

// Error:
// denom paused
