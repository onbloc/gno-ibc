// PKGPATH: gno.land/r/onbloc/ibc/scenario/union
package union

// token_send_native_no_trim_filetest verifies that native tokens (ugnot)
// are NOT trimmed since they already use 6-decimal precision.

import (
	"chain"
	"chain/banker"
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
	coreImplPath   = "gno.land/r/onbloc/ibc/union/core/v1"
	zkgmImplPath   = "gno.land/r/onbloc/ibc/union/apps/ucs03_zkgm/v1"
	adminAddr      = address("g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5")
	senderAddr     = address("g1wymu47drhr0kuq2098m792lytgtj2nyx77yrsm")
	receiverAddr   = address("g1qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqlldmu")
	mockClientType = types.ClientType("scenario-mock-lc")
)

func main(cur realm) {
	ufmt.Println("[SCENARIO] Bootstrap IBC host and open client/connection/channel")
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

	core.ChannelOpenInit(cross(cur), core.NewMsgChannelOpenInit(portId, portId, connectionId, zkgm.Version, "g1relayer"))
	remoteChannelId := types.ChannelId(2)
	core.ChannelOpenAck(cross(cur), core.NewMsgChannelOpenAck(remoteChannelId, zkgm.Version, channelId, nil, 1, "g1relayer"))

	ufmt.Println("")
	ufmt.Println("[SCENARIO] Send INITIALIZE order with native ugnot (6-decimal, no trimming)")
	initOrder := z.TokenOrderV2{
		Sender:      []byte(senderAddr.String()),
		Receiver:    []byte(receiverAddr.String()),
		BaseToken:   []byte("ugnot"),
		BaseAmount:  u256.NewUint(1234567),
		QuoteToken:  []byte("ibc/test-native"),
		QuoteAmount: u256.NewUint(1234567),
		Kind:        z.TOKEN_ORDER_KIND_INITIALIZE,
	}

	ufmt.Printf("[INFO] BaseAmount: %d (6-decimal ugnot, no trimming needed)\n", initOrder.BaseAmount.Uint64())

	proxy := zkgm.ProxyAddress()
	testing.IssueCoins(proxy, chain.NewCoins(chain.NewCoin("ugnot", 1234567)))

	testing.SetRealm(testing.NewUserRealm(senderAddr))
	testing.SetOriginSend(chain.NewCoins(chain.NewCoin("ugnot", 1234567)))
	sendPacket := zkgm.Send(cross(cur), channelId, types.Timestamp(1<<62), [32]byte{}, mustOrderInstruction(initOrder))

	bk := banker.NewReadonlyBanker()
	ufmt.Printf("[INFO] proxy native escrow balance: %d\n", bk.GetCoins(proxy).AmountOf("ugnot"))
	ufmt.Println("[INFO] Send completed successfully (native tokens are not trimmed)")
	ufmt.Println("[EXPECTED] native ugnot should pass through unchanged (no dust)")
	ufmt.Println("[EXPECTED] proxy native escrow balance should be 1234567 (full amount, no trimming)")

	zkgmPacket, err := z.DecodeZkgmPacket(sendPacket.Data)
	if err != nil {
		panic(err)
	}

	decodedOrder, err := z.DecodeTokenOrderV2(zkgmPacket.Instruction.Operand)
	if err != nil {
		panic(err)
	}

	ufmt.Printf("[INFO] packet BaseAmount (decoded): %d\n", decodedOrder.BaseAmount.Uint64())
	ufmt.Println("[EXPECTED] packet BaseAmount should be 1234567 (native no-scale)")
}

func mustOrderInstruction(order z.TokenOrderV2) z.Instruction {
	operand, err := z.EncodeTokenOrderV2(order)
	if err != nil {
		panic(err)
	}
	return z.Instruction{Version: z.INSTR_VERSION_2, Opcode: z.OP_TOKEN_ORDER, Operand: operand}
}

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
	return nil, mockError("mock: misbehaviour unsupported")
}

type mockError string

func (e mockError) Error() string { return string(e) }

// Output:
// [SCENARIO] Bootstrap IBC host and open client/connection/channel
//
// [SCENARIO] Send INITIALIZE order with native ugnot (6-decimal, no trimming)
// [INFO] BaseAmount: 1234567 (6-decimal ugnot, no trimming needed)
// [INFO] proxy native escrow balance: 1234567
// [INFO] Send completed successfully (native tokens are not trimmed)
// [EXPECTED] native ugnot should pass through unchanged (no dust)
// [EXPECTED] proxy native escrow balance should be 1234567 (full amount, no trimming)
// [INFO] packet BaseAmount (decoded): 1234567
// [EXPECTED] packet BaseAmount should be 1234567 (native no-scale)
