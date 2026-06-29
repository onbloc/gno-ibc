// PKGPATH: gno.land/r/onbloc/ibc/scenario/union/client
package client

// reregister_type_rejected_filetest is the BY-TYPE / EXCEPTION client scenario for the
// client-type registry (S-3.5). A client *type* is the factory that mints light-client
// instances; it is registered once and is then shared by every CreateClient of that
// type. This file shows both halves of that contract: one registered type backs many
// independent client instances (ids 1 and 2, each its own Active state), and a second
// registration of the same type is rejected with "client type already exists" so a
// later caller cannot silently swap the factory out from under existing clients. The
// rejection is the terminating panic.

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

	sharedType = types.ClientType("scenario-shared-lc")
)

func main(cur realm) {
	println("[SCENARIO] 1. Register a client type once")
	bootstrap(cur)
	ufmt.Printf("[INFO] type %q registered: %t\n", string(sharedType), core.HasClient(sharedType))
	println("")

	println("[SCENARIO] 2. The one registered type backs many independent client instances")
	first := createInstance(cur, 1)
	second := createInstance(cur, 2)
	report(first, "first instance")
	report(second, "second instance")
	ufmt.Println("[EXPECTED] two distinct client ids, each Active under the same shared factory")
	println("")

	println("[SCENARIO] 3. Re-registering the same type is rejected")
	reregister(cur)
}

func bootstrap(cur realm) {
	testing.SetRealm(testing.NewUserRealm(adminAddr))
	core.UpdateImpl(cross(cur), coreImplPath)
	access.GrantRole(cross(cur), access.RelayerRole, adminAddr)
	registerSharedType(cur)
}

func registerSharedType(cur realm) {
	core.RegisterClient(cross(cur), sharedType, func(csBytes, _ []byte) (lightclient.Interface, error) {
		return &trivialClient{height: 1}, nil
	})
}

// createInstance creates a client of the shared type. CreateClient assigns ids
// sequentially, so expectedId is the deterministic id the caller can thread forward.
func createInstance(cur realm, expectedId uint32) types.ClientId {
	testing.SetRealm(testing.NewUserRealm(adminAddr))
	core.CreateClient(cross(cur), core.NewMsgCreateClient(sharedType, nil, nil))
	return types.ClientId(expectedId)
}

func reregister(cur realm) {
	testing.SetRealm(testing.NewUserRealm(adminAddr))
	registerSharedType(cur)
}

func report(clientId types.ClientId, label string) {
	status, _ := core.GetStatus(clientId)
	ufmt.Printf("[INFO] %s: id=%s status=%s\n", label, clientId.String(), statusLabel(status))
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

// --- trivial always-Active mock light client ---

type trivialClient struct {
	height uint64
}

func (m *trivialClient) VerifyMembership(uint64, []byte, []byte, []byte) error { return nil }
func (m *trivialClient) VerifyNonMembership(uint64, []byte, []byte) error      { return nil }
func (m *trivialClient) GetTimestamp() types.Timestamp                         { return types.Timestamp(1) }
func (m *trivialClient) GetTimestampAtHeight(uint64) (types.Timestamp, error)  { return types.Timestamp(1), nil }
func (m *trivialClient) GetLatestHeight() uint64                               { return m.height }
func (m *trivialClient) GetCounterpartyChainID() string                        { return "trivial-chain" }
func (m *trivialClient) Status() lightclient.Status                            { return lightclient.Active }

func (m *trivialClient) VerifyHeader(_ address, header []byte, _ address) (types.StateUpdate, error) {
	m.height++
	return types.StateUpdate{Height: m.height, ClientStateBytes: header, ConsensusStateBytes: header}, nil
}

func (m *trivialClient) VerifyCreation(address, address) (types.ClientCreationResult, error) {
	return types.ClientCreationResult{}, nil
}

func (m *trivialClient) Misbehaviour(address, []byte, address) ([]byte, error) {
	return nil, nil
}

// Output:
// [SCENARIO] 1. Register a client type once
// [INFO] type "scenario-shared-lc" registered: true
//
// [SCENARIO] 2. The one registered type backs many independent client instances
// [INFO] first instance: id=1 status=Active
// [INFO] second instance: id=2 status=Active
// [EXPECTED] two distinct client ids, each Active under the same shared factory
//
// [SCENARIO] 3. Re-registering the same type is rejected

// Error:
// client type already exists
