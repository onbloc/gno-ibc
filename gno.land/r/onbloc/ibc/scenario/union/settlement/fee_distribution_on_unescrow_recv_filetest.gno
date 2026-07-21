// PKGPATH: gno.land/r/onbloc/ibc/scenario/union/settlement
package settlement

// fee_distribution_on_unescrow_recv_filetest is the NORMAL-path settlement
// scenario for the relayer fee split on an UNESCROW release (the release-path
// counterpart to fee_distribution_on_recv_filetest's mint-path fee split).
// protocolFillUnescrowV2 (token_order.gno) computes fee = BaseAmount -
// QuoteAmount and releases QuoteAmount to the receiver and the fee to the
// relayer, both from the SAME escrowed native balance — decreasing the
// channel balance by BaseAmount's ledger equivalent. Every existing UNESCROW
// scenario uses BaseAmount == QuoteAmount (fee always 0); this file locks 50
// and releases with QuoteAmount 40, so a real 10-unit fee is paid out
// alongside the receiver's share, verified as real banker balance diffs.

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
	relayerAddr    = address("g1wymu47drhr0kuq2098m792lytgtj2nyx77yrsm")
	userAddr       = address("g1dyxy88p94acjnm8dmu9tfj2mv2ncvx83cagllu")
	mockClientType = types.ClientType("scenario-mock-lc")

	// quoteWrapped stands in for the counterparty's wrapped denom. It only keys
	// the channel balance (lock increases it, unescrow decreases it); the recv
	// unescrow path does not re-derive it, so a stable placeholder is enough.
	quoteWrapped = "remote-wrapped-ugnot"
)

func main(cur realm) {
	println("[SCENARIO] 1. Bootstrap IBC host and open client/connection/channel")
	channelId := bootstrap(cur)
	println("")

	println("[SCENARIO] 2. Lock 50ugnot into proxy escrow (native ESCROW send funded by attached coins)")
	lockNativeEscrow(cur, channelId)
	println("")

	println("[SCENARIO] 3. Receive UNESCROW order (Base=50, Quote=40): user gets 40, relayer gets the 10 fee")
	receiveUnescrowOrderWithFee(cur, channelId)
}

// bootstrap installs the core/zkgm impls, grants the admin AND the relayer the
// relayer role (the relayer submits the recv in step 3, so it must be
// relayer-authorized too), and opens a client/connection/channel backed by the
// permissive mock light client.
func bootstrap(cur realm) types.ChannelId {
	testing.SetRealm(testing.NewUserRealm(adminAddr))
	core.UpdateImpl(cross(cur), coreImplPath)
	zkgm.UpdateImpl(cross(cur), zkgmImplPath)
	zkgm.SetRateLimitDisabled(cross(cur), true)
	zkgm.RegisterCoreApp(cross(cur))
	access.GrantRole(cross(cur), access.RelayerRole, adminAddr)
	access.GrantRole(cross(cur), access.RelayerRole, relayerAddr)

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

// lockNativeEscrow locks 50 native ugnot into the proxy escrow via a user ESCROW
// send. IssueCoins reproduces the -send deposit landing at the proxy; SetOriginSend
// reproduces the envelope the impl reads to seed the escrow budget.
func lockNativeEscrow(cur realm, channelId types.ChannelId) {
	order := z.TokenOrderV2{
		Sender:      []byte(userAddr.String()),
		Receiver:    []byte("remote-receiver"),
		BaseToken:   []byte("ugnot"),
		BaseAmount:  u256.NewUint(50),
		QuoteToken:  []byte(quoteWrapped),
		QuoteAmount: u256.NewUint(50),
		Kind:        z.TOKEN_ORDER_KIND_ESCROW,
	}

	proxy := zkgm.ProxyAddress()
	testing.IssueCoins(proxy, chain.NewCoins(chain.NewCoin("ugnot", 50)))
	testing.SetRealm(testing.NewUserRealm(userAddr))
	testing.SetOriginSend(chain.NewCoins(chain.NewCoin("ugnot", 50)))
	zkgm.Send(cross(cur), channelId, types.Timestamp(1<<62), [32]byte{}, mustOrderInstruction(order))

	bk := banker.NewReadonlyBanker()
	ufmt.Printf("[INFO] proxy native escrow balance: %d\n", bk.GetCoins(proxy).AmountOf("ugnot"))
	ufmt.Println("[EXPECTED] proxy native escrow balance should be 50 (locked)")
}

// receiveUnescrowOrderWithFee receives an UNESCROW order whose BaseAmount (50)
// exceeds its QuoteAmount (40). protocolFillUnescrowV2 releases QuoteAmount to
// the receiver (user) and the 10-unit fee (Base - Quote) to the relayer
// submitting this recv, both from the same escrowed native balance.
func receiveUnescrowOrderWithFee(cur realm, channelId types.ChannelId) {
	order := z.TokenOrderV2{
		Sender:      []byte("remote-sender"),
		Receiver:    []byte(userAddr.String()),
		BaseToken:   []byte(quoteWrapped),
		BaseAmount:  u256.NewUint(50),
		QuoteToken:  []byte("ugnot"),
		QuoteAmount: u256.NewUint(40),
		Kind:        z.TOKEN_ORDER_KIND_UNESCROW,
	}
	packet := core.NewPacket(types.ChannelId(2), channelId, mustPacketData(mustOrderInstruction(order)), types.Timestamp(1<<62))

	testing.SetRealm(testing.NewUserRealm(relayerAddr))
	core.PacketRecv(cross(cur), core.NewMsgPacketRecv([]types.Packet{packet}, [][]byte{nil}, nil, 1))

	bk := banker.NewReadonlyBanker()
	proxy := zkgm.ProxyAddress()
	ufmt.Printf("[INFO] proxy native escrow balance: %d\n", bk.GetCoins(proxy).AmountOf("ugnot"))
	ufmt.Printf("[INFO] user native balance: %d\n", bk.GetCoins(userAddr).AmountOf("ugnot"))
	ufmt.Printf("[INFO] relayer native balance: %d\n", bk.GetCoins(relayerAddr).AmountOf("ugnot"))
	ufmt.Println("[EXPECTED] proxy native escrow balance should be 0 (fully released: 40 + 10 fee)")
	ufmt.Println("[EXPECTED] user native balance should be 40 (QuoteAmount)")
	ufmt.Println("[EXPECTED] relayer native balance should be 10 (BaseAmount - QuoteAmount fee)")
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
// [SCENARIO] 2. Lock 50ugnot into proxy escrow (native ESCROW send funded by attached coins)
// [INFO] proxy native escrow balance: 50
// [EXPECTED] proxy native escrow balance should be 50 (locked)
//
// [SCENARIO] 3. Receive UNESCROW order (Base=50, Quote=40): user gets 40, relayer gets the 10 fee
// [INFO] proxy native escrow balance: 0
// [INFO] user native balance: 40
// [INFO] relayer native balance: 10
// [EXPECTED] proxy native escrow balance should be 0 (fully released: 40 + 10 fee)
// [EXPECTED] user native balance should be 40 (QuoteAmount)
// [EXPECTED] relayer native balance should be 10 (BaseAmount - QuoteAmount fee)
