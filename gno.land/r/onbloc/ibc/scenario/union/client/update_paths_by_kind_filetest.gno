// PKGPATH: gno.land/r/onbloc/ibc/scenario/union/client
package client

// update_paths_by_kind_filetest is the BY-TYPE client scenario. It contrasts the
// two distinct ways a client's state is advanced:
//   - the verified path (UpdateClient), which runs the light client's header
//     verification and is only allowed while the client is Active, and
//   - the admin override path (ForceUpdateClient), which rebuilds the client from
//     submitted bytes, bypassing verification — so it can even recover a frozen
//     client back to Active.
// Each step reports the client's status/height so the transitions read as diffs.

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
	verifiedHeight = uint64(5)
	forcedHeight   = uint64(9)
)

func main(cur realm) {
	println("[SCENARIO] 1. Bootstrap, register the type, and create a client")
	clientId := bootstrapAndCreate(cur)
	report(clientId, "after create")
	println("")

	println("[SCENARIO] 2. VERIFIED path: UpdateClient runs header verification (client must be Active)")
	verifiedUpdate(cur, clientId)
	report(clientId, "after UpdateClient")
	println("")

	println("[SCENARIO] 3. Freeze the client via Misbehaviour")
	freeze(cur, clientId)
	report(clientId, "after Misbehaviour")
	println("")

	println("[SCENARIO] 4. ADMIN OVERRIDE path: ForceUpdateClient rebuilds and recovers the frozen client")
	forcedUpdate(cur, clientId)
	report(clientId, "after ForceUpdateClient")
	println("[EXPECTED] verified path advances height while Active; force path rebuilds Active from Frozen")
}

func bootstrapAndCreate(cur realm) types.ClientId {
	testing.SetRealm(testing.NewUserRealm(adminAddr))
	core.UpdateImpl(cross(cur), coreImplPath)
	access.GrantRole(cross(cur), access.RelayerRole, adminAddr)
	core.RegisterClient(cross(cur), mockClientType, func(csBytes, _ []byte) (lightclient.Interface, error) {
		return &mockClient{height: decodeHeight(csBytes)}, nil
	})
	core.CreateClient(cross(cur), core.NewMsgCreateClient(mockClientType, encodeHeight(genesisHeight), encodeHeight(genesisHeight)))
	return types.ClientId(1)
}

func verifiedUpdate(cur realm, clientId types.ClientId) {
	testing.SetRealm(testing.NewUserRealm(adminAddr))
	core.UpdateClient(cross(cur), types.NewMsgUpdateClient(clientId, encodeHeight(verifiedHeight)))
}

func freeze(cur realm, clientId types.ClientId) {
	testing.SetRealm(testing.NewUserRealm(adminAddr))
	core.Misbehaviour(cross(cur), types.NewMsgMisbehaviour(clientId, []byte("evidence"), "g1relayer"))
}

func forcedUpdate(cur realm, clientId types.ClientId) {
	testing.SetRealm(testing.NewUserRealm(adminAddr))
	core.ForceUpdateClient(cross(cur), types.NewMsgForceUpdateClient(clientId, encodeHeight(forcedHeight), encodeHeight(forcedHeight)))
}

func report(clientId types.ClientId, label string) {
	status, _ := core.GetStatus(clientId)
	height, _ := core.GetLatestHeight(clientId)
	ufmt.Printf("[INFO] client %s %s: status=%s height=%d\n", clientId.String(), label, statusLabel(status), height)
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
	height uint64
	frozen bool
}

func (m *mockClient) VerifyMembership(uint64, []byte, []byte, []byte) error { return nil }
func (m *mockClient) VerifyNonMembership(uint64, []byte, []byte) error      { return nil }
func (m *mockClient) GetTimestamp() types.Timestamp                         { return types.Timestamp(1) }
func (m *mockClient) GetTimestampAtHeight(uint64) (types.Timestamp, error)  { return types.Timestamp(1), nil }
func (m *mockClient) GetLatestHeight() uint64                               { return m.height }
func (m *mockClient) GetCounterpartyChainID() string                        { return "mock-counterparty" }

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
// [SCENARIO] 1. Bootstrap, register the type, and create a client
// [INFO] client 1 after create: status=Active height=1
//
// [SCENARIO] 2. VERIFIED path: UpdateClient runs header verification (client must be Active)
// [INFO] client 1 after UpdateClient: status=Active height=5
//
// [SCENARIO] 3. Freeze the client via Misbehaviour
// [INFO] client 1 after Misbehaviour: status=Frozen height=5
//
// [SCENARIO] 4. ADMIN OVERRIDE path: ForceUpdateClient rebuilds and recovers the frozen client
// [INFO] client 1 after ForceUpdateClient: status=Active height=9
// [EXPECTED] verified path advances height while Active; force path rebuilds Active from Frozen
