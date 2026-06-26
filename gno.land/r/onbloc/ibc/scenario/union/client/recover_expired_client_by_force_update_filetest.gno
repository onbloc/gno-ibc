// PKGPATH: gno.land/r/onbloc/ibc/scenario/union/client
package client

// recover_expired_client_by_force_update_filetest is the BY-TYPE client scenario for
// recovering an Expired client (S-4.1). A light client that stops receiving updates
// reports Expired and can no longer be updated through the verified path. The admin
// force-updates it with a fresh consensus state, which rebuilds the client to Active,
// after which verified updates work again. Each step reports the client status so the
// Expired → Active recovery reads as a diff.

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

	expiringType  = types.ClientType("scenario-expiring-lc")
	genesisHeight = uint64(1)
	recoverHeight = uint64(5)
	updatedHeight = uint64(8)
)

// expired models a stalled counterparty: while true the client reports Expired.
var expired bool

func main(cur realm) {
	println("[SCENARIO] 1. Bootstrap and create a client (Active)")
	clientId := bootstrap(cur)
	report(clientId, "after create")
	println("")

	println("[SCENARIO] 2. The counterparty stalls: the client expires")
	expired = true
	report(clientId, "after expiry")
	println("")

	println("[SCENARIO] 3. Admin force-updates with a fresh consensus state: recovered to Active")
	forceRecover(cur, clientId)
	report(clientId, "after force-update")
	println("")

	println("[SCENARIO] 4. Verified updates work again")
	verifiedUpdate(cur, clientId)
	report(clientId, "after update")
	println("[EXPECTED] Active -> Expired -> (force-update) Active; height recovers then advances")
}

func bootstrap(cur realm) types.ClientId {
	testing.SetRealm(testing.NewUserRealm(adminAddr))
	core.UpdateImpl(cross(cur), coreImplPath)
	access.GrantRole(cross(cur), access.RelayerRole, adminAddr)

	core.RegisterClient(cross(cur), expiringType, func(csBytes, _ []byte) (lightclient.Interface, error) {
		return &expiringClient{height: decodeHeight(csBytes)}, nil
	})
	core.CreateClient(cross(cur), core.NewMsgCreateClient(expiringType, encodeHeight(genesisHeight), encodeHeight(genesisHeight)))
	return types.ClientId(1)
}

func forceRecover(cur realm, clientId types.ClientId) {
	expired = false // the fresh consensus the admin submits is not expired
	testing.SetRealm(testing.NewUserRealm(adminAddr))
	core.ForceUpdateClient(cross(cur), types.NewMsgForceUpdateClient(clientId, encodeHeight(recoverHeight), encodeHeight(recoverHeight)))
}

func verifiedUpdate(cur realm, clientId types.ClientId) {
	testing.SetRealm(testing.NewUserRealm(adminAddr))
	core.UpdateClient(cross(cur), types.NewMsgUpdateClient(clientId, encodeHeight(updatedHeight)))
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

// --- height codec ---

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

// --- expiring mock light client (Expired while the package `expired` flag is set) ---

type expiringClient struct {
	height uint64
}

func (m *expiringClient) VerifyMembership(uint64, []byte, []byte, []byte) error { return nil }
func (m *expiringClient) VerifyNonMembership(uint64, []byte, []byte) error      { return nil }
func (m *expiringClient) GetTimestamp() types.Timestamp                         { return types.Timestamp(1) }
func (m *expiringClient) GetTimestampAtHeight(uint64) (types.Timestamp, error)  { return types.Timestamp(1), nil }
func (m *expiringClient) GetLatestHeight() uint64                               { return m.height }
func (m *expiringClient) GetCounterpartyChainID() string                        { return "expiring-chain" }

func (m *expiringClient) Status() lightclient.Status {
	if expired {
		return lightclient.Expired
	}
	return lightclient.Active
}

func (m *expiringClient) VerifyHeader(_ address, header []byte, _ address) (types.StateUpdate, error) {
	m.height = decodeHeight(header)
	return types.StateUpdate{Height: m.height, ClientStateBytes: header, ConsensusStateBytes: header}, nil
}

func (m *expiringClient) VerifyCreation(address, address) (types.ClientCreationResult, error) {
	return types.ClientCreationResult{}, nil
}

func (m *expiringClient) Misbehaviour(address, []byte, address) ([]byte, error) {
	return encodeHeight(m.height), nil
}

// Output:
// [SCENARIO] 1. Bootstrap and create a client (Active)
// [INFO] client 1 after create: status=Active height=1
//
// [SCENARIO] 2. The counterparty stalls: the client expires
// [INFO] client 1 after expiry: status=Expired height=1
//
// [SCENARIO] 3. Admin force-updates with a fresh consensus state: recovered to Active
// [INFO] client 1 after force-update: status=Active height=5
//
// [SCENARIO] 4. Verified updates work again
// [INFO] client 1 after update: status=Active height=8
// [EXPECTED] Active -> Expired -> (force-update) Active; height recovers then advances
