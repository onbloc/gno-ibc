// PKGPATH: gno.land/r/onbloc/ibc/scenario/union/client
package client

// freeze_blocks_client_ops_filetest is the EXCEPTION-path client scenario for
// misbehaviour freezing (S-4.3, "freeze griefing"). A relayer that submits a valid
// misbehaviour proof freezes the light client. A frozen client is the IBC safety
// stop: core's getActiveClient rejects every verified operation against it until an
// admin recovers it. This file proves the griefing reaches its intended safety state
// (status Active -> Frozen, printed as a diff) and that the frozen client then refuses
// a verified UpdateClient with "client is not active" — the terminating panic. The
// admin recovery side (force-update back to Active) is covered by the success-path
// counterpart recover_expired_client_by_force_update; recover() cannot resume past a
// cross-realm panic, so the denial is the last observable step here.

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

	freezableType = types.ClientType("scenario-freezable-lc")
)

// frozen models the safety stop: once a valid misbehaviour is processed the client
// reports Frozen and stays there until an admin rebuilds it.
var frozen bool

func main(cur realm) {
	println("[SCENARIO] 1. Bootstrap and create a client (Active)")
	clientId := bootstrap(cur)
	report(clientId, "after create")
	println("")

	println("[SCENARIO] 2. A relayer submits a valid misbehaviour proof: the client freezes")
	submitMisbehaviour(cur, clientId)
	report(clientId, "after misbehaviour")
	ufmt.Println("[EXPECTED] status flips Active -> Frozen (the griefing safety stop)")
	println("")

	println("[SCENARIO] 3. Any verified operation against the frozen client is rejected")
	updateFrozen(cur, clientId)
}

func bootstrap(cur realm) types.ClientId {
	testing.SetRealm(testing.NewUserRealm(adminAddr))
	core.UpdateImpl(cross(cur), coreImplPath)
	access.GrantRole(cross(cur), access.RelayerRole, adminAddr)

	core.RegisterClient(cross(cur), freezableType, func(csBytes, _ []byte) (lightclient.Interface, error) {
		return &freezableClient{height: 1}, nil
	})
	core.CreateClient(cross(cur), core.NewMsgCreateClient(freezableType, nil, nil))
	return types.ClientId(1)
}

func submitMisbehaviour(cur realm, clientId types.ClientId) {
	testing.SetRealm(testing.NewUserRealm(adminAddr))
	core.Misbehaviour(cross(cur), types.NewMsgMisbehaviour(clientId, []byte("double-sign"), ""))
}

func updateFrozen(cur realm, clientId types.ClientId) {
	testing.SetRealm(testing.NewUserRealm(adminAddr))
	core.UpdateClient(cross(cur), types.NewMsgUpdateClient(clientId, []byte("new-header")))
}

func report(clientId types.ClientId, label string) {
	status, _ := core.GetStatus(clientId)
	ufmt.Printf("[INFO] client %s %s: status=%s\n", clientId.String(), label, statusLabel(status))
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

// --- freezable mock light client (Frozen while the package `frozen` flag is set) ---

type freezableClient struct {
	height uint64
}

func (m *freezableClient) VerifyMembership(uint64, []byte, []byte, []byte) error { return nil }
func (m *freezableClient) VerifyNonMembership(uint64, []byte, []byte) error      { return nil }
func (m *freezableClient) GetTimestamp() types.Timestamp                         { return types.Timestamp(1) }
func (m *freezableClient) GetTimestampAtHeight(uint64) (types.Timestamp, error)  { return types.Timestamp(1), nil }
func (m *freezableClient) GetLatestHeight() uint64                               { return m.height }
func (m *freezableClient) GetCounterpartyChainID() string                        { return "freezable-chain" }

func (m *freezableClient) Status() lightclient.Status {
	if frozen {
		return lightclient.Frozen
	}
	return lightclient.Active
}

func (m *freezableClient) VerifyHeader(_ address, header []byte, _ address) (types.StateUpdate, error) {
	m.height++
	return types.StateUpdate{Height: m.height, ClientStateBytes: header, ConsensusStateBytes: header}, nil
}

func (m *freezableClient) VerifyCreation(address, address) (types.ClientCreationResult, error) {
	return types.ClientCreationResult{}, nil
}

// Misbehaviour proof is accepted and freezes the client; returning non-empty bytes
// makes core persist the frozen client-state mirror.
func (m *freezableClient) Misbehaviour(address, []byte, address) ([]byte, error) {
	frozen = true
	return []byte("frozen-client-state"), nil
}

// Output:
// [SCENARIO] 1. Bootstrap and create a client (Active)
// [INFO] client 1 after create: status=Active
//
// [SCENARIO] 2. A relayer submits a valid misbehaviour proof: the client freezes
// [INFO] client 1 after misbehaviour: status=Frozen
// [EXPECTED] status flips Active -> Frozen (the griefing safety stop)
//
// [SCENARIO] 3. Any verified operation against the frozen client is rejected

// Error:
// client is not active
