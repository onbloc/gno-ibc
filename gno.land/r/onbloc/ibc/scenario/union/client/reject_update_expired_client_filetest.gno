// PKGPATH: gno.land/r/onbloc/ibc/scenario/union/client
package client

// reject_update_expired_client_filetest is the EXCEPTION-path client scenario.
// An Expired light client must reject the normal verified
// UpdateClient path; only the admin ForceUpdateClient recovery path may rebuild
// it. The success half is covered by recover_expired_client_by_force_update.

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

	expiredRejectType = types.ClientType("scenario-expired-reject-lc")
)

var rejectExpired bool

func main(cur realm) {
	println("[SCENARIO] 1. Bootstrap and create a client (Active)")
	clientId := bootstrap(cur)
	report(clientId, "after create")
	println("")

	println("[SCENARIO] 2. The client expires")
	rejectExpired = true
	report(clientId, "after expiry")
	println("")

	println("[SCENARIO] 3. Normal UpdateClient against the expired client is rejected")
	testing.SetRealm(testing.NewUserRealm(adminAddr))
	core.UpdateClient(cross(cur), types.NewMsgUpdateClient(clientId, encodeHeight(2)))
}

func bootstrap(cur realm) types.ClientId {
	testing.SetRealm(testing.NewUserRealm(adminAddr))
	core.UpdateImpl(cross(cur), coreImplPath)
	access.GrantRole(cross(cur), access.RelayerRole, adminAddr)

	core.RegisterClient(cross(cur), expiredRejectType, func(csBytes, _ []byte) (lightclient.Interface, error) {
		return &expiredRejectClient{height: decodeHeight(csBytes)}, nil
	})
	core.CreateClient(cross(cur), core.NewMsgCreateClient(expiredRejectType, encodeHeight(1), encodeHeight(1)))
	return types.ClientId(1)
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

type expiredRejectClient struct {
	height uint64
}

func (m *expiredRejectClient) VerifyMembership(uint64, []byte, []byte, []byte) error { return nil }
func (m *expiredRejectClient) VerifyNonMembership(uint64, []byte, []byte) error      { return nil }
func (m *expiredRejectClient) GetTimestamp() types.Timestamp                         { return types.Timestamp(1) }
func (m *expiredRejectClient) GetTimestampAtHeight(uint64) (types.Timestamp, error)  { return types.Timestamp(1), nil }
func (m *expiredRejectClient) GetLatestHeight() uint64                               { return m.height }
func (m *expiredRejectClient) GetCounterpartyChainID() string                        { return "expired-reject-chain" }

func (m *expiredRejectClient) Status() lightclient.Status {
	if rejectExpired {
		return lightclient.Expired
	}
	return lightclient.Active
}

func (m *expiredRejectClient) VerifyHeader(_ address, header []byte, _ address) (types.StateUpdate, error) {
	m.height = decodeHeight(header)
	return types.StateUpdate{Height: m.height, ClientStateBytes: header, ConsensusStateBytes: header}, nil
}

func (m *expiredRejectClient) VerifyCreation(address, address) (types.ClientCreationResult, error) {
	return types.ClientCreationResult{}, nil
}

func (m *expiredRejectClient) Misbehaviour(address, []byte, address) ([]byte, error) {
	return encodeHeight(m.height), nil
}

// Output:
// [SCENARIO] 1. Bootstrap and create a client (Active)
// [INFO] client 1 after create: status=Active height=1
//
// [SCENARIO] 2. The client expires
// [INFO] client 1 after expiry: status=Expired height=1
//
// [SCENARIO] 3. Normal UpdateClient against the expired client is rejected

// Error:
// client is not active
