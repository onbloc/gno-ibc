// PKGPATH: gno.land/r/onbloc/ibc/scenario/union/client
package client

// create_and_update_client_filetest is the NORMAL-path client-lifecycle scenario.
// It registers a light-client type, creates a client (id 1, Active), then updates
// it with a header that advances the verified height. The client's status and
// latest height are verified as a before/after diff across each step.

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
	coreImplPath = "gno.land/r/onbloc/ibc/union/core/v1"
	adminAddr    = address("g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5")

	mockClientType = types.ClientType("scenario-mock-lc")
	genesisHeight  = uint64(1)
	updatedHeight  = uint64(7)
)

func main(cur realm) {
	println("[SCENARIO] 1. Bootstrap core and register a light-client type")
	bootstrap(cur)
	println("")

	println("[SCENARIO] 2. Create a client of that type")
	clientId := createClient(cur)
	println("")

	println("[SCENARIO] 3. Update the client with a header advancing the height")
	updateClient(cur, clientId)
}

// bootstrap installs the core impl and grants the admin the relayer role (client
// lifecycle entrypoints are relayer-gated). SetRealm and the cross(cur) calls share
// this frame so the admin is the authorized caller.
func bootstrap(cur realm) {
	testing.SetRealm(testing.NewUserRealm(adminAddr))
	core.UpdateImpl(cross(cur), coreImplPath)
	access.GrantRole(cross(cur), access.RelayerRole, adminAddr)

	core.RegisterClient(cross(cur), mockClientType, func(csBytes, _ []byte) (lightclient.Interface, error) {
		return &mockClient{height: decodeHeight(csBytes), chainID: "mock-counterparty"}, nil
	})
	ufmt.Printf("[INFO] client type registered: %t\n", core.GetRegisteredClientType(mockClientType))
	ufmt.Println("[EXPECTED] the mock client type should be registered")
}

// createClient creates a client seeded at genesisHeight and reports its identity.
func createClient(cur realm) types.ClientId {
	testing.SetRealm(testing.NewUserRealm(adminAddr))
	core.CreateClient(cross(cur), core.NewMsgCreateClient(mockClientType, encodeHeight(genesisHeight), encodeHeight(genesisHeight)))
	clientId := types.ClientId(1)

	reportStatus(clientId, "after create")
	ufmt.Println("[EXPECTED] first client should be id 1, status Active, latest height 1")
	return clientId
}

// updateClient submits a header advancing the verified height, then reports the
// height as a diff against the create-time value.
func updateClient(cur realm, clientId types.ClientId) {
	before, _ := core.GetLatestHeight(clientId)

	testing.SetRealm(testing.NewUserRealm(adminAddr))
	core.UpdateClient(cross(cur), types.NewMsgUpdateClient(clientId, encodeHeight(updatedHeight)))

	after, _ := core.GetLatestHeight(clientId)
	ufmt.Printf("[INFO] latest height: %d -> %d\n", before, after)
	reportStatus(clientId, "after update")
	ufmt.Println("[EXPECTED] latest height should advance 1 -> 7 and the client stay Active")
}

func reportStatus(clientId types.ClientId, label string) {
	status, _ := core.GetStatus(clientId)
	height, _ := core.GetLatestHeight(clientId)
	ufmt.Printf("[INFO] client %s %s: status=%s height=%d\n", clientId.String(), label, statusLabel(status), height)
}

// statusLabel maps the uint8 types.Status to a readable name (types.Status has no
// String method).
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

// --- height codec (8-byte big-endian) ---

func encodeHeight(h uint64) []byte {
	out := make([]byte, 8)
	for i := 0; i < 8; i++ {
		out[7-i] = byte(h >> (8 * i))
	}
	return out
}

func decodeHeight(b []byte) uint64 {
	if len(b) < 8 {
		return 0
	}
	var h uint64
	for i := 0; i < 8; i++ {
		h = h<<8 | uint64(b[i])
	}
	return h
}

// --- mock light client with a mutable verified height and freeze flag ---

type mockClient struct {
	height  uint64
	frozen  bool
	chainID string
}

func (m *mockClient) VerifyMembership(uint64, []byte, []byte, []byte) error { return nil }
func (m *mockClient) VerifyNonMembership(uint64, []byte, []byte) error      { return nil }
func (m *mockClient) GetTimestamp() types.Timestamp                         { return types.Timestamp(1) }
func (m *mockClient) GetTimestampAtHeight(uint64) (types.Timestamp, error)  { return types.Timestamp(1), nil }
func (m *mockClient) GetLatestHeight() uint64                               { return m.height }
func (m *mockClient) GetCounterpartyChainID() string                        { return m.chainID }

func (m *mockClient) Status() lightclient.Status {
	if m.frozen {
		return lightclient.Frozen
	}
	return lightclient.Active
}

func (m *mockClient) VerifyHeader(_ address, header []byte, _ address) (types.StateUpdate, error) {
	m.height = decodeHeight(header)
	return types.StateUpdate{Height: m.height, ClientStateBytes: header, ConsensusStateBytes: header}, nil
}

func (m *mockClient) VerifyCreation(address, address) (types.ClientCreationResult, error) {
	return types.ClientCreationResult{}, nil
}

func (m *mockClient) Misbehaviour(address, []byte, address) ([]byte, error) {
	m.frozen = true
	return encodeHeight(m.height), nil
}

// Output:
// [SCENARIO] 1. Bootstrap core and register a light-client type
// [INFO] client type registered: true
// [EXPECTED] the mock client type should be registered
//
// [SCENARIO] 2. Create a client of that type
// [INFO] client 1 after create: status=Active height=1
// [EXPECTED] first client should be id 1, status Active, latest height 1
//
// [SCENARIO] 3. Update the client with a header advancing the height
// [INFO] latest height: 1 -> 7
// [INFO] client 1 after update: status=Active height=7
// [EXPECTED] latest height should advance 1 -> 7 and the client stay Active
