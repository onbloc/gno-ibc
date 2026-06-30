// PKGPATH: gno.land/r/onbloc/ibc/scenario/union/app
package app

// reject_channel_open_unregistered_port_filetest is the EXCEPTION-path app
// scenario for registry misses. Core should fail closed when a channel handshake
// targets a port with no registered IBC app.

import (
	"testing"

	"gno.land/p/nt/ufmt/v0"
	"gno.land/p/onbloc/ibc/union/lightclient"
	types "gno.land/p/onbloc/ibc/union/types"

	"gno.land/r/onbloc/ibc/union/access"
	core "gno.land/r/onbloc/ibc/union/core"
	_ "gno.land/r/onbloc/ibc/union/core/v1"
)

const (
	unregisteredCoreImplPath = "gno.land/r/onbloc/ibc/union/core/v1"
	unregisteredAdminAddr    = address("g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5")
	unregisteredClientType   = types.ClientType("scenario-unregistered-port-lc")
	unregisteredPort         = "gno.land/r/onbloc/ibc/scenario/union/app/missing"
)

func main(cur realm) {
	println("[SCENARIO] 1. Bootstrap core and open a client/connection without registering an app")
	connectionId := bootstrapUnregistered(cur)
	ufmt.Printf("[INFO] app bound at missing port: %t\n", core.HasApp([]byte(unregisteredPort)))
	ufmt.Println("[EXPECTED] no app should be bound at the missing port")
	println("")

	println("[SCENARIO] 2. ChannelOpenInit to the unregistered port -> rejected")
	core.ChannelOpenInit(cross(cur), core.NewMsgChannelOpenInit([]byte(unregisteredPort), []byte(unregisteredPort), connectionId, "missing-v1", "g1relayer"))
}

func bootstrapUnregistered(cur realm) types.ConnectionId {
	testing.SetRealm(testing.NewUserRealm(unregisteredAdminAddr))
	core.UpdateImpl(cross(cur), unregisteredCoreImplPath)
	access.GrantRole(cross(cur), access.RelayerRole, unregisteredAdminAddr)

	core.RegisterClient(cross(cur), unregisteredClientType, func(_, _ []byte) (lightclient.Interface, error) {
		return &unregisteredMockLightClient{}, nil
	})
	core.CreateClient(cross(cur), core.NewMsgCreateClient(unregisteredClientType, nil, nil))

	core.ConnectionOpenInit(cross(cur), core.NewMsgConnectionOpenInit(types.ClientId(1), types.ClientId(99)))
	connectionId := types.ConnectionId(1)
	core.ConnectionOpenAck(cross(cur), core.NewMsgConnectionOpenAck(connectionId, types.ConnectionId(77), nil, 1))
	return connectionId
}

type unregisteredMockLightClient struct{}

func (m *unregisteredMockLightClient) VerifyMembership(uint64, []byte, []byte, []byte) error {
	return nil
}
func (m *unregisteredMockLightClient) VerifyNonMembership(uint64, []byte, []byte) error {
	return nil
}
func (m *unregisteredMockLightClient) GetTimestamp() types.Timestamp { return types.Timestamp(1) }
func (m *unregisteredMockLightClient) GetTimestampAtHeight(uint64) (types.Timestamp, error) {
	return types.Timestamp(1), nil
}
func (m *unregisteredMockLightClient) GetLatestHeight() uint64                { return 1 }
func (m *unregisteredMockLightClient) GetCounterpartyChainID() string         { return "mock-chain" }
func (m *unregisteredMockLightClient) Status() lightclient.Status             { return lightclient.Active }
func (m *unregisteredMockLightClient) VerifyCreation(address, address) (types.ClientCreationResult, error) {
	return types.ClientCreationResult{}, nil
}
func (m *unregisteredMockLightClient) VerifyHeader(_ address, header []byte, _ address) (types.StateUpdate, error) {
	return types.StateUpdate{Height: 1, ClientStateBytes: header, ConsensusStateBytes: header}, nil
}
func (m *unregisteredMockLightClient) Misbehaviour(address, []byte, address) ([]byte, error) {
	return nil, unregisteredMockError("mock: misbehaviour unsupported")
}

type unregisteredMockError string

func (e unregisteredMockError) Error() string { return string(e) }

// Output:
// [SCENARIO] 1. Bootstrap core and open a client/connection without registering an app
// [INFO] app bound at missing port: false
// [EXPECTED] no app should be bound at the missing port
//
// [SCENARIO] 2. ChannelOpenInit to the unregistered port -> rejected

// Error:
// port not found, gno.land/r/onbloc/ibc/scenario/union/app/missing
