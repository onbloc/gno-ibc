// PKGPATH: gno.land/r/onbloc/ibc/scenario/union/decimals
package decimals

// recv_unescrow_amount_overflow_rejected_filetest is the release-path counterpart to
// recv_amount_boundary_filetest's mint-path int64 overflow check. A wrapped/
// native banker balance is an int64, so protocolFillUnescrowV2's release amount
// must fit too — it calls ledgerAmountOf (amountInt64 for a native denom) on
// QuoteAmount, on the fee, and on BaseAmount, all BEFORE decreaseChannelBalanceV2
// ever runs. A QuoteAmount of MaxInt64+1 is rejected there: a failure
// acknowledgement, nothing released, and the existing escrow stays exactly as
// locked — proven against a real native ESCROW lock, not a mock store call.

import (
	"chain"
	"chain/banker"
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

	adminAddr      = address("g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5")
	userAddr       = address("g1dyxy88p94acjnm8dmu9tfj2mv2ncvx83cagllu")
	mockClientType = types.ClientType("scenario-mock-lc")

	quoteWrapped = "remote-wrapped-ugnot"
	maxInt64     = uint64(9223372036854775807) // math.MaxInt64
)

func main(cur realm) {
	println("[SCENARIO] 1. Bootstrap IBC host and open client/connection/channel")
	channelId := bootstrap(cur)
	println("")

	println("[SCENARIO] 2. Lock 40ugnot into proxy escrow (native ESCROW send funded by attached coins)")
	lockNativeEscrow(cur, channelId)
	println("")

	println("[SCENARIO] 3. Receive UNESCROW order with amount MaxInt64+1: overflow rejected, escrow untouched")
	attemptOverflowingUnescrow(cur, channelId)
}

func bootstrap(cur realm) types.ChannelId {
	testing.SetRealm(testing.NewUserRealm(adminAddr))
	core.UpdateImpl(cross(cur), coreImplPath)
	zkgm.UpdateImpl(cross(cur), zkgmImplPath)
	zkgm.SetRateLimitDisabled(cross(cur), true)
	zkgm.RegisterCoreApp(cross(cur))
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
	return channelId
}

func lockNativeEscrow(cur realm, channelId types.ChannelId) {
	order := z.TokenOrderV2{
		Sender:      []byte(userAddr.String()),
		Receiver:    []byte("remote-receiver"),
		BaseToken:   []byte("ugnot"),
		BaseAmount:  u256.NewUint(40),
		QuoteToken:  []byte(quoteWrapped),
		QuoteAmount: u256.NewUint(40),
		Kind:        z.TOKEN_ORDER_KIND_ESCROW,
	}

	proxy := zkgm.ProxyAddress()
	testing.IssueCoins(proxy, chain.NewCoins(chain.NewCoin("ugnot", 40)))
	testing.SetRealm(testing.NewUserRealm(userAddr))
	testing.SetOriginSend(chain.NewCoins(chain.NewCoin("ugnot", 40)))
	zkgm.Send(cross(cur), channelId, types.Timestamp(1<<62), [32]byte{}, mustOrderInstruction(order))

	bk := banker.NewReadonlyBanker()
	ufmt.Printf("[INFO] proxy native escrow balance: %d\n", bk.GetCoins(proxy).AmountOf("ugnot"))
	ufmt.Println("[EXPECTED] proxy native escrow balance should be 40 (locked)")
}

// attemptOverflowingUnescrow receives an UNESCROW order whose Base and Quote
// amounts are both MaxInt64+1. protocolFillUnescrowV2's ledgerAmountOf check on
// QuoteAmount rejects it before decreaseChannelBalanceV2 (or any release) ever
// runs, so the 40ugnot locked in step 2 is left exactly as it was.
func attemptOverflowingUnescrow(cur realm, channelId types.ChannelId) {
	overAmt := new(u256.Uint).Add(u256.NewUint(maxInt64), u256.NewUint(1))
	order := z.TokenOrderV2{
		Sender:      []byte("remote-sender"),
		Receiver:    []byte(userAddr.String()),
		BaseToken:   []byte(quoteWrapped),
		BaseAmount:  overAmt,
		QuoteToken:  []byte("ugnot"),
		QuoteAmount: overAmt,
		Kind:        z.TOKEN_ORDER_KIND_UNESCROW,
	}
	packet := core.NewPacket(types.ChannelId(2), channelId, mustPacketData(mustOrderInstruction(order)), types.Timestamp(1<<62))

	testing.SetRealm(testing.NewUserRealm(adminAddr))
	core.PacketRecv(cross(cur), core.NewMsgPacketRecv([]types.Packet{packet}, [][]byte{nil}, nil, 1))

	bk := banker.NewReadonlyBanker()
	proxy := zkgm.ProxyAddress()
	ufmt.Printf("[INFO] proxy native escrow balance: %d\n", bk.GetCoins(proxy).AmountOf("ugnot"))
	ufmt.Printf("[INFO] user native balance: %d\n", bk.GetCoins(userAddr).AmountOf("ugnot"))
	ufmt.Println("[EXPECTED] proxy native escrow balance should still be 40 (overflow rejected before any release)")
	ufmt.Println("[EXPECTED] user native balance should still be 0 (nothing released)")
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
//
// [SCENARIO] 2. Lock 40ugnot into proxy escrow (native ESCROW send funded by attached coins)
// [INFO] proxy native escrow balance: 40
// [EXPECTED] proxy native escrow balance should be 40 (locked)
//
// [SCENARIO] 3. Receive UNESCROW order with amount MaxInt64+1: overflow rejected, escrow untouched
// [INFO] proxy native escrow balance: 40
// [INFO] user native balance: 0
// [EXPECTED] proxy native escrow balance should still be 40 (overflow rejected before any release)
// [EXPECTED] user native balance should still be 0 (nothing released)
