// PKGPATH: gno.land/r/onbloc/ibc/scenario/union/app
package app

// route_to_custom_app_by_port_filetest is the BY-TYPE app scenario. Core routes IBC
// callbacks by port to whichever app.IApp implementation is registered there — it is
// app-agnostic. This scenario registers a CUSTOM (non-zkgm) app at the scenario
// realm's own port and drives channel handshake legs to it; the custom app records each
// callback it receives, proving core routed the handshake legs to it by port.

import (
	"strings"
	"testing"

	"gno.land/p/nt/ufmt/v0"
	"gno.land/p/onbloc/ibc/union/lightclient"
	types "gno.land/p/onbloc/ibc/union/types"

	"gno.land/r/onbloc/ibc/union/access"
	core "gno.land/r/onbloc/ibc/union/core"
	_ "gno.land/r/onbloc/ibc/union/core/v1"
)

const (
	coreImplPath = "gno.land/r/onbloc/ibc/union/core/v1"
	adminAddr    = address("g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5")

	// customPort is the scenario realm's own package path; registering from this
	// realm binds the custom app at this port.
	customPort     = "gno.land/r/onbloc/ibc/scenario/union/app"
	customVersion  = "custom-app-v1"
	mockClientType = types.ClientType("scenario-mock-lc")
)

// routed records, in order, the callbacks core delivered to the custom app.
var routed []string

func main(cur realm) {
	println("[SCENARIO] 1. Bootstrap core and register a CUSTOM app at the scenario realm's port")
	connectionId := bootstrap(cur)
	ufmt.Printf("[INFO] custom app bound at its port: %t\n", core.HasApp([]byte(customPort)))
	ufmt.Println("[EXPECTED] the custom (non-zkgm) app should be bound at its own port")
	println("")

	println("[SCENARIO] 2. Full channel handshake legs to that port route callbacks to the custom app")
	openChannel(cur, connectionId)
	ufmt.Printf("[INFO] callbacks the custom app received: %s\n", strings.Join(routed, " -> "))
	ufmt.Println("[EXPECTED] core should route Init/Try/Ack/Confirm callbacks to the custom app")
}

// bootstrap installs the core impl, opens a mock-backed client/connection, and
// registers the custom app at the scenario realm's port. The admin ops run under
// SetRealm(admin); the registration runs under the scenario code realm so the
// derived port is customPort.
func bootstrap(cur realm) types.ConnectionId {
	testing.SetRealm(testing.NewUserRealm(adminAddr))
	core.UpdateImpl(cross(cur), coreImplPath)
	access.GrantRole(cross(cur), access.RelayerRole, adminAddr)

	core.RegisterClient(cross(cur), mockClientType, func(_, _ []byte) (lightclient.Interface, error) {
		return &mockLightClient{}, nil
	})
	core.CreateClient(cross(cur), core.NewMsgCreateClient(mockClientType, nil, nil))
	clientId := types.ClientId(1)

	core.ConnectionOpenInit(cross(cur), core.NewMsgConnectionOpenInit(clientId, types.ClientId(99)))
	connectionId := types.ConnectionId(1)
	core.ConnectionOpenAck(cross(cur), core.NewMsgConnectionOpenAck(connectionId, types.ConnectionId(77), nil, 1))

	// Register the custom app as the scenario code realm so its port is customPort.
	testing.SetRealm(testing.NewCodeRealm(customPort))
	core.RegisterApp(cross(cur), &customApp{})
	return connectionId
}

func openChannel(cur realm, connectionId types.ConnectionId) {
	portId := []byte(customPort)

	testing.SetRealm(testing.NewUserRealm(adminAddr))
	core.ChannelOpenInit(cross(cur), core.NewMsgChannelOpenInit(portId, portId, connectionId, customVersion, "g1relayer"))
	tryChannel := core.NewChannel(types.ChannelStateTryOpen, connectionId, types.ChannelId(8), types.Bytes(portId), customVersion)
	core.ChannelOpenTry(cross(cur), core.NewMsgChannelOpenTry(portId, tryChannel, customVersion, nil, 1, "g1relayer"))
	channelId := types.ChannelId(1)
	core.ChannelOpenAck(cross(cur), core.NewMsgChannelOpenAck(channelId, customVersion, types.ChannelId(2), nil, 1, "g1relayer"))
	core.ChannelOpenConfirm(cross(cur), types.NewMsgChannelOpenConfirm(types.ChannelId(2), nil, 1, "g1relayer"))
}

// --- custom IBC app: records each routed callback, accepts any channel version ---

type customApp struct{}

func (a *customApp) OnChannelOpenInit(_ realm, _ types.ConnectionId, _ types.ChannelId, _ string, _ address) {
	routed = append(routed, "OnChannelOpenInit")
}

func (a *customApp) OnChannelOpenTry(_ realm, _ types.ConnectionId, _ types.ChannelId, _ string, _ string, _ address) {
	routed = append(routed, "OnChannelOpenTry")
}

func (a *customApp) OnChannelOpenAck(_ realm, _ types.ChannelId, _ types.ChannelId, _ string, _ address) {
	routed = append(routed, "OnChannelOpenAck")
}

func (a *customApp) OnChannelOpenConfirm(_ realm, _ types.ChannelId, _ address) {
	routed = append(routed, "OnChannelOpenConfirm")
}

func (a *customApp) OnChannelCloseInit(_ realm, _ types.ChannelId, _ address)    {}
func (a *customApp) OnChannelCloseConfirm(_ realm, _ types.ChannelId, _ address) {}

func (a *customApp) OnRecvPacket(_ realm, _ types.Packet, _ address, _ []byte) types.RecvPacketResult {
	return core.NewRecvPacketResult(types.PacketStatusSuccess, nil)
}

func (a *customApp) OnAcknowledgementPacket(_ realm, _ types.Packet, _ []byte, _ address) {}
func (a *customApp) OnTimeoutPacket(_ realm, _ types.Packet, _ address)                   {}

func (a *customApp) OnIntentRecvPacket(_ realm, _ types.Packet, _ address, _ []byte) types.RecvPacketResult {
	return core.NewRecvPacketResult(types.PacketStatusSuccess, nil)
}

// --- permissive mock light client (accepts any proof) ---

type mockLightClient struct{}

func (m *mockLightClient) VerifyMembership(uint64, []byte, []byte, []byte) error { return nil }
func (m *mockLightClient) VerifyNonMembership(uint64, []byte, []byte) error      { return nil }
func (m *mockLightClient) GetTimestamp() types.Timestamp                         { return types.Timestamp(1) }
func (m *mockLightClient) GetTimestampAtHeight(uint64) (types.Timestamp, error)  { return types.Timestamp(1), nil }
func (m *mockLightClient) GetLatestHeight() uint64                               { return 1 }
func (m *mockLightClient) GetCounterpartyChainID() string                        { return "mock-chain" }
func (m *mockLightClient) Status() lightclient.Status                            { return lightclient.Active }

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
// [SCENARIO] 1. Bootstrap core and register a CUSTOM app at the scenario realm's port
// [INFO] custom app bound at its port: true
// [EXPECTED] the custom (non-zkgm) app should be bound at its own port
//
// [SCENARIO] 2. Full channel handshake legs to that port route callbacks to the custom app
// [INFO] callbacks the custom app received: OnChannelOpenInit -> OnChannelOpenTry -> OnChannelOpenAck -> OnChannelOpenConfirm
// [EXPECTED] core should route Init/Try/Ack/Confirm callbacks to the custom app
