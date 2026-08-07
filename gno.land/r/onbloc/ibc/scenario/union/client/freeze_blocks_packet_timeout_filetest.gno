// PKGPATH: gno.land/r/onbloc/ibc/scenario/union/client
package client

// freeze_blocks_packet_timeout_filetest is the PacketTimeout sibling of
// freeze_blocks_packet_recv_filetest / freeze_blocks_packet_ack_filetest.
// PacketTimeout's proof check (verifyNonMembership) calls the same
// getActiveClient gate, rejecting a timeout before its non-membership proof
// is consulted. A baseline ESCROW send + timeout (elapsed while Active)
// succeeds, then a second send's timeout is rejected once the client is
// Frozen — even though its own timeout condition is also already met, so the
// rejection can only be the frozen-client gate, not the timeout-elapsed
// check.
//
// Cross-realm panics can't be recovered mid-file (see
// freeze_blocks_client_ops_filetest), so PacketRecv/PacketAcknowledgement/
// PacketTimeout each need their own file — this covers only PacketTimeout,
// ending on its rejection.
//
// PacketTimeout resolves proofTimestamp via getClient (not getActiveClient)
// before ever reaching the gate (core/v1 packet.gno:229-244), so the
// freezableClient's fixed GetTimestampAtHeight (unaffected by Frozen) lets
// packets with TimeoutTimestamp=1 register as elapsed in both the Active and
// Frozen steps.

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
	coreImplPath = "gno.land/r/onbloc/ibc/union/core/v1"
	zkgmImplPath = "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/v1"

	adminAddr     = address("g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5")
	senderAddr    = address("g1wymu47drhr0kuq2098m792lytgtj2nyx77yrsm")
	freezableType = types.ClientType("scenario-freezable-lc")
)

// frozen models the safety stop: once a valid misbehaviour is processed the
// client reports Frozen and stays there until an admin rebuilds it.
var frozen bool

func main(cur realm) {
	println("[SCENARIO] 1. Bootstrap IBC host (freezable LC) and open a zkgm channel")
	channelId := bootstrap(cur)
	println("")

	println("[SCENARIO] 2. Baseline: send + timeout (already elapsed) succeeds while the client is Active")
	baselineSendAndTimeout(cur, channelId)
	println("")

	println("[SCENARIO] 3. A relayer submits a valid misbehaviour proof: the client freezes")
	submitMisbehaviour(cur)
	println("")

	println("[SCENARIO] 4. A further timeout is rejected before any proof is consulted")
	attemptTimeoutWhileFrozen(cur, channelId)
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

// baselineSendAndTimeout locks 40ugnot with TimeoutTimestamp=1 (already
// "elapsed" against the freezableClient's fixed timestamp of 1), then times
// it out while the client is Active: the non-membership proof is verified and
// the escrow refunds normally.
func baselineSendAndTimeout(cur realm, channelId types.ChannelId) {
	bk := banker.NewReadonlyBanker()
	proxy := zkgm.ProxyAddress()

	ufmt.Printf("[INFO] channel balance ledger before send: %s\n", channelBalanceOrZero(channelId).ToString())

	sendPacket := sendEscrowOrder(cur, channelId, 40)
	ufmt.Printf("[INFO] proxy native escrow balance after send: %d\n", bk.GetCoins(proxy).AmountOf("ugnot"))
	ufmt.Printf("[INFO] channel balance ledger after send: %s\n", channelBalanceOrZero(channelId).ToString())
	ufmt.Println("[EXPECTED] proxy native escrow balance should be 40 (locked)")
	ufmt.Println("[EXPECTED] channel balance ledger should be 40 (matches the escrowed order amount)")

	testing.SetRealm(testing.NewUserRealm(adminAddr))
	core.PacketTimeout(cross(cur), types.NewMsgPacketTimeout(sendPacket, nil, 1))

	ufmt.Printf("[INFO] proxy native escrow balance after timeout: %d\n", bk.GetCoins(proxy).AmountOf("ugnot"))
	ufmt.Printf("[INFO] channel balance ledger after timeout: %s\n", channelBalanceOrZero(channelId).ToString())
	ufmt.Println("[EXPECTED] proxy native escrow balance should be 0 (client Active: proof accepted, refund succeeds)")
	ufmt.Println("[EXPECTED] channel balance ledger should be 0 (decreased back by the refunded 40; ledger and bank balance agree)")
}

func submitMisbehaviour(cur realm) {
	testing.SetRealm(testing.NewUserRealm(adminAddr))
	core.Misbehaviour(cross(cur), types.NewMsgMisbehaviour(types.ClientId(1), []byte("double-sign"), ""))

	status, _ := core.GetStatus(types.ClientId(1))
	ufmt.Printf("[INFO] client status: %s\n", statusLabel(status))
	ufmt.Println("[EXPECTED] status should be Frozen")
}

// attemptTimeoutWhileFrozen sends a second, differently-sized escrow (so its
// commitment can't be confused with the baseline's) and times it out while the
// client is frozen; core's getActiveClient rejects it with "client is not
// active" before VerifyNonMembership is ever called.
func attemptTimeoutWhileFrozen(cur realm, channelId types.ChannelId) {
	bk := banker.NewReadonlyBanker()
	proxy := zkgm.ProxyAddress()

	sendPacket := sendEscrowOrder(cur, channelId, 25)
	ufmt.Printf("[INFO] proxy native escrow balance after send: %d\n", bk.GetCoins(proxy).AmountOf("ugnot"))
	ufmt.Printf("[INFO] channel balance ledger after send: %s\n", channelBalanceOrZero(channelId).ToString())
	ufmt.Println("[EXPECTED] proxy native escrow balance should be 25 (locked)")
	ufmt.Println("[EXPECTED] channel balance ledger should be 25 (matches the escrowed order amount)")

	testing.SetRealm(testing.NewUserRealm(adminAddr))
	core.PacketTimeout(cross(cur), types.NewMsgPacketTimeout(sendPacket, nil, 1))
}

func sendEscrowOrder(cur realm, channelId types.ChannelId, amount int64) types.Packet {
	order := z.TokenOrderV2{
		Sender:      []byte(senderAddr.String()),
		Receiver:    []byte("remote-receiver"),
		BaseToken:   []byte("ugnot"),
		BaseAmount:  u256.NewUint(uint64(amount)),
		QuoteToken:  []byte("remote-ugnot"),
		QuoteAmount: u256.NewUint(uint64(amount)),
		Kind:        z.TOKEN_ORDER_KIND_ESCROW,
	}

	proxy := zkgm.ProxyAddress()
	testing.IssueCoins(proxy, chain.NewCoins(chain.NewCoin("ugnot", amount)))

	testing.SetRealm(testing.NewUserRealm(senderAddr))
	testing.SetOriginSend(chain.NewCoins(chain.NewCoin("ugnot", amount)))
	// TimeoutTimestamp=1 matches the freezableClient's fixed GetTimestampAtHeight,
	// so the packet reads as already elapsed the moment it's sent.
	return zkgm.Send(cross(cur), channelId, types.Timestamp(1), [32]byte{}, mustOrderInstruction(order))
}

// channelBalanceOrZero: GetChannelBalanceV2 returns "not found" (never
// escrowed) as an error rather than a stored zero; resolve it to u256.Zero().
// Both sends share the same (channelId, "ugnot", "remote-ugnot") key.
func channelBalanceOrZero(channelId types.ChannelId) *u256.Uint {
	balance, err := zkgm.GetChannelBalanceV2(channelId, u256.Zero(), "ugnot", []byte("remote-ugnot"))
	if err != nil {
		return u256.Zero()
	}
	return balance
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

// --- freezable mock light client (Frozen while the package `frozen` flag is set) ---

type freezableClient struct{}

func (m *freezableClient) VerifyMembership(uint64, []byte, []byte, []byte) error { return nil }

// VerifyNonMembership panics with a distinct message when frozen, so this
// scenario's expected "client is not active" error can only come from
// getActiveClient rejecting the call before VerifyNonMembership ever runs —
// not from a coincidentally-successful proof check masking a wiring bug that
// checks the proof first.
func (m *freezableClient) VerifyNonMembership(uint64, []byte, []byte) error {
	if frozen {
		panic("proof verification called while frozen")
	}
	return nil
}
func (m *freezableClient) GetTimestamp() types.Timestamp { return types.Timestamp(1) }

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
// [SCENARIO] 2. Baseline: send + timeout (already elapsed) succeeds while the client is Active
// [INFO] channel balance ledger before send: 0
// [INFO] proxy native escrow balance after send: 40
// [INFO] channel balance ledger after send: 40
// [EXPECTED] proxy native escrow balance should be 40 (locked)
// [EXPECTED] channel balance ledger should be 40 (matches the escrowed order amount)
// [INFO] proxy native escrow balance after timeout: 0
// [INFO] channel balance ledger after timeout: 0
// [EXPECTED] proxy native escrow balance should be 0 (client Active: proof accepted, refund succeeds)
// [EXPECTED] channel balance ledger should be 0 (decreased back by the refunded 40; ledger and bank balance agree)
//
// [SCENARIO] 3. A relayer submits a valid misbehaviour proof: the client freezes
// [INFO] client status: Frozen
// [EXPECTED] status should be Frozen
//
// [SCENARIO] 4. A further timeout is rejected before any proof is consulted
// [INFO] proxy native escrow balance after send: 25
// [INFO] channel balance ledger after send: 25
// [EXPECTED] proxy native escrow balance should be 25 (locked)
// [EXPECTED] channel balance ledger should be 25 (matches the escrowed order amount)

// Error:
// client is not active
