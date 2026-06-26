// PKGPATH: gno.land/r/onbloc/ibc/scenario/union/app
package app

// register_app_and_route_handshake_filetest is the NORMAL-path app scenario. It
// registers the zkgm app at its port (HasApp false -> true), then drives a channel
// handshake to that port. Core routes the OnChannelOpenInit / OnChannelOpenAck
// callbacks to the registered app, advancing the channel Init -> Open — verified as
// a channel-state diff.

import (
	"testing"

	"gno.land/p/nt/ufmt/v0"
	"gno.land/p/onbloc/ibc/union/lightclient"
	types "gno.land/p/onbloc/ibc/union/types"

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
	mockClientType = types.ClientType("scenario-mock-lc")
)

func main(cur realm) {
	println("[SCENARIO] 1. Bootstrap core+zkgm and open a client/connection (app not yet registered)")
	connectionId := bootstrap(cur)
	ufmt.Printf("[INFO] app bound at zkgm port: %t\n", core.HasApp([]byte(zkgm.ProxyPkgPath())))
	ufmt.Println("[EXPECTED] no app should be bound at the port yet")
	println("")

	println("[SCENARIO] 2. Register the zkgm app at its port")
	testing.SetRealm(testing.NewUserRealm(adminAddr))
	zkgm.RegisterCoreApp(cross(cur))
	ufmt.Printf("[INFO] app bound at zkgm port: %t\n", core.HasApp([]byte(zkgm.ProxyPkgPath())))
	ufmt.Println("[EXPECTED] the zkgm app should now be bound")
	println("")

	println("[SCENARIO] 3. Channel handshake routes OnChannelOpenInit/Ack to the app (Init -> Open)")
	openChannel(cur, connectionId)
}

// bootstrap installs the impls, grants the relayer role, and opens a mock-backed
// client and connection. It stops short of registering the app or opening a channel.
func bootstrap(cur realm) types.ConnectionId {
	testing.SetRealm(testing.NewUserRealm(adminAddr))
	core.UpdateImpl(cross(cur), coreImplPath)
	zkgm.UpdateImpl(cross(cur), zkgmImplPath)
	zkgm.SetRateLimitDisabled(cross(cur), true)
	access.GrantRole(cross(cur), access.RelayerRole, adminAddr)

	core.RegisterClient(cross(cur), mockClientType, func(_, _ []byte) (lightclient.Interface, error) {
		return &mockLightClient{}, nil
	})
	core.CreateClient(cross(cur), core.NewMsgCreateClient(mockClientType, nil, nil))
	clientId := types.ClientId(1)

	core.ConnectionOpenInit(cross(cur), core.NewMsgConnectionOpenInit(clientId, types.ClientId(99)))
	connectionId := types.ConnectionId(1)
	core.ConnectionOpenAck(cross(cur), core.NewMsgConnectionOpenAck(connectionId, types.ConnectionId(77), nil, 1))
	return connectionId
}

// openChannel drives the Init and Ack handshake legs and reports the channel state
// after each, proving the app received the routed callbacks.
func openChannel(cur realm, connectionId types.ConnectionId) {
	portId := []byte(zkgm.ProxyPkgPath())

	testing.SetRealm(testing.NewUserRealm(adminAddr))
	core.ChannelOpenInit(cross(cur), core.NewMsgChannelOpenInit(portId, portId, connectionId, zkgm.Version, "g1relayer"))
	channelId := types.ChannelId(1)
	reportChannel(channelId, "after OpenInit")

	core.ChannelOpenAck(cross(cur), core.NewMsgChannelOpenAck(channelId, zkgm.Version, types.ChannelId(2), nil, 1, "g1relayer"))
	reportChannel(channelId, "after OpenAck")
	ufmt.Println("[EXPECTED] channel should advance Init -> Open as the app handles each handshake leg")
}

func reportChannel(channelId types.ChannelId, label string) {
	ch, err := core.GetChannel(channelId)
	if err != nil {
		ufmt.Printf("[INFO] channel %s %s: <missing>\n", channelId.String(), label)
		return
	}
	ufmt.Printf("[INFO] channel %s %s: state=%s\n", channelId.String(), label, channelStateLabel(ch.State))
}

func channelStateLabel(s types.ChannelState) string {
	switch s {
	case types.ChannelStateInit:
		return "Init"
	case types.ChannelStateTryOpen:
		return "TryOpen"
	case types.ChannelStateOpen:
		return "Open"
	case types.ChannelStateClosed:
		return "Closed"
	default:
		return "Unknown"
	}
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
// [SCENARIO] 1. Bootstrap core+zkgm and open a client/connection (app not yet registered)
// [INFO] app bound at zkgm port: false
// [EXPECTED] no app should be bound at the port yet
//
// [SCENARIO] 2. Register the zkgm app at its port
// [INFO] app bound at zkgm port: true
// [EXPECTED] the zkgm app should now be bound
//
// [SCENARIO] 3. Channel handshake routes OnChannelOpenInit/Ack to the app (Init -> Open)
// [INFO] channel 1 after OpenInit: state=Init
// [INFO] channel 1 after OpenAck: state=Open
// [EXPECTED] channel should advance Init -> Open as the app handles each handshake leg
