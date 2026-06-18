package core

import (
	"testing"

	"gno.land/p/nt/testutils/v0"
	"gno.land/p/nt/uassert/v0"
	"gno.land/p/onbloc/ibc/union/types"
)

func setAdminForTest(cur realm) func() {
	oldAdmin := admin
	admin = cur.Address()
	return func() {
		admin = oldAdmin
	}
}

func TestConnectionOpenTryVerifiesProof(cur realm, t *testing.T) {
	resetStore()
	cleanup := setAdminForTest(cur)
	defer cleanup()

	client := &mockClient{status: types.StatusActive}
	clientId := registerMockClient(client)

	id := types.ConnectionId(1)
	ConnectionOpenTry(cross(cur), types.NewMsgConnectionOpenTry(
		clientId,
		types.ClientId(99),
		types.ConnectionId(77),
		[]byte("proof-init"),
		10,
	))

	if id != types.ConnectionId(1) {
		t.Fatalf("ConnectionOpenTry id: got %v want 1", id)
	}
	if len(client.membershipProofs) != 1 {
		t.Fatalf("ConnectionOpenTry membership verifications: got %d want 1", len(client.membershipProofs))
	}
	conn, ok := store.getConnection(id)
	if !ok {
		t.Fatal("ConnectionOpenTry connection not saved")
	}
	if conn.State != types.ConnectionStateTryOpen {
		t.Fatalf("ConnectionOpenTry state: got %v want TryOpen", conn.State)
	}
}

// Converted from Union connection_open_init_ok:
// https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/core/src/tests/connection/ibc.rs#L18-L66
func TestConnectionOpenInitSavesInitConnection(cur realm, t *testing.T) {
	resetStore()
	cleanup := setAdminForTest(cur)
	defer cleanup()

	clientId := registerMockClient(&mockClient{status: types.StatusActive})

	id := types.ConnectionId(1)
	ConnectionOpenInit(cross(cur), types.NewMsgConnectionOpenInit(clientId, types.ClientId(99)))

	conn, ok := store.getConnection(id)
	if !ok {
		t.Fatal("ConnectionOpenInit connection not saved")
	}
	if conn.State != types.ConnectionStateInit {
		t.Fatalf("ConnectionOpenInit state: got %v want Init", conn.State)
	}
	if conn.CounterpartyConnectionId != types.ConnectionId(0) {
		t.Fatalf("ConnectionOpenInit counterparty connection: got %v want unset", conn.CounterpartyConnectionId)
	}
}

// Converted from Union connection_open_ack_ok:
// https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/core/src/tests/connection/ibc.rs#L298-L353
func TestConnectionOpenAckVerifiesProofAndOpensConnection(cur realm, t *testing.T) {
	resetStore()
	cleanup := setAdminForTest(cur)
	defer cleanup()

	client := &mockClient{status: types.StatusActive}
	clientId := registerMockClient(client)
	connectionId := store.nextConnectionId()
	store.saveConnection(connectionId, types.Connection{
		State:                types.ConnectionStateInit,
		ClientId:             clientId,
		CounterpartyClientId: types.ClientId(99),
	})

	ConnectionOpenAck(cross(cur), types.NewMsgConnectionOpenAck(connectionId, types.ConnectionId(77), []byte("proof-try"), 10))

	if len(client.membershipProofs) != 1 {
		t.Fatalf("ConnectionOpenAck membership verifications: got %d want 1", len(client.membershipProofs))
	}
	conn, ok := store.getConnection(connectionId)
	if !ok {
		t.Fatal("ConnectionOpenAck connection not saved")
	}
	if conn.State != types.ConnectionStateOpen {
		t.Fatalf("ConnectionOpenAck state: got %v want Open", conn.State)
	}
}

// Converted from Union connection_open_confirm_ok:
// https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/core/src/tests/connection/ibc.rs#L425-L479
func TestConnectionOpenConfirmVerifiesProofAndOpensConnection(cur realm, t *testing.T) {
	resetStore()
	cleanup := setAdminForTest(cur)
	defer cleanup()

	client := &mockClient{status: types.StatusActive}
	clientId := registerMockClient(client)
	connectionId := store.nextConnectionId()
	store.saveConnection(connectionId, types.Connection{
		State:                    types.ConnectionStateTryOpen,
		ClientId:                 clientId,
		CounterpartyClientId:     types.ClientId(99),
		CounterpartyConnectionId: types.ConnectionId(77),
	})

	ConnectionOpenConfirm(cross(cur), types.NewMsgConnectionOpenConfirm(connectionId, []byte("proof-ack"), 10))

	if len(client.membershipProofs) != 1 {
		t.Fatalf("ConnectionOpenConfirm membership verifications: got %d want 1", len(client.membershipProofs))
	}
	conn, ok := store.getConnection(connectionId)
	if !ok {
		t.Fatal("ConnectionOpenConfirm connection not saved")
	}
	if conn.State != types.ConnectionStateOpen {
		t.Fatalf("ConnectionOpenConfirm state: got %v want Open", conn.State)
	}
}

// Converted from Union force_connection_open_try dispatch:
// https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/core/src/contract.rs#L195-L208
func TestForceConnectionOpenTryBypassesProofVerification(cur realm, t *testing.T) {
	resetStore()
	cleanup := setAdminForTest(cur)
	defer cleanup()

	client := &mockClient{status: types.StatusFrozen}
	clientId := registerMockClient(client)

	id := types.ConnectionId(1)
	ForceConnectionOpenTry(cross(cur), types.NewMsgConnectionOpenTry(
		clientId,
		types.ClientId(99),
		types.ConnectionId(77),
		[]byte("ignored-proof"),
		10,
	))

	if id != types.ConnectionId(1) {
		t.Fatalf("ForceConnectionOpenTry id: got %v want 1", id)
	}
	if len(client.membershipProofs) != 0 {
		t.Fatalf("ForceConnectionOpenTry membership verifications: got %d want 0", len(client.membershipProofs))
	}
	conn, ok := store.getConnection(id)
	if !ok {
		t.Fatal("ForceConnectionOpenTry connection not saved")
	}
	if conn.State != types.ConnectionStateTryOpen {
		t.Fatalf("ForceConnectionOpenTry state: got %v want TryOpen", conn.State)
	}
}

// Converted from Union force_connection_open_ack dispatch:
// https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/core/src/contract.rs#L223-L234
func TestForceConnectionOpenAckBypassesProofVerification(cur realm, t *testing.T) {
	resetStore()
	cleanup := setAdminForTest(cur)
	defer cleanup()

	client := &mockClient{status: types.StatusFrozen}
	clientId := registerMockClient(client)
	connectionId := store.nextConnectionId()
	store.saveConnection(connectionId, types.Connection{
		State:                types.ConnectionStateInit,
		ClientId:             clientId,
		CounterpartyClientId: types.ClientId(99),
	})

	ForceConnectionOpenAck(cross(cur), types.NewMsgConnectionOpenAck(
		connectionId,
		types.ConnectionId(77),
		[]byte("ignored-proof"),
		10,
	))

	if len(client.membershipProofs) != 0 {
		t.Fatalf("ForceConnectionOpenAck membership verifications: got %d want 0", len(client.membershipProofs))
	}
	conn, ok := store.getConnection(connectionId)
	if !ok {
		t.Fatal("ForceConnectionOpenAck connection not saved")
	}
	if conn.State != types.ConnectionStateOpen {
		t.Fatalf("ForceConnectionOpenAck state: got %v want Open", conn.State)
	}
	if conn.CounterpartyConnectionId != types.ConnectionId(77) {
		t.Fatalf("ForceConnectionOpenAck counterparty connection: got %v want 77", conn.CounterpartyConnectionId)
	}
}

// Converted from Union force_connection_open_confirm dispatch:
// https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/core/src/contract.rs#L247-L258
func TestForceConnectionOpenConfirmBypassesProofVerification(cur realm, t *testing.T) {
	resetStore()
	cleanup := setAdminForTest(cur)
	defer cleanup()

	client := &mockClient{status: types.StatusFrozen}
	clientId := registerMockClient(client)
	connectionId := store.nextConnectionId()
	store.saveConnection(connectionId, types.Connection{
		State:                    types.ConnectionStateTryOpen,
		ClientId:                 clientId,
		CounterpartyClientId:     types.ClientId(99),
		CounterpartyConnectionId: types.ConnectionId(77),
	})

	ForceConnectionOpenConfirm(cross(cur), types.NewMsgConnectionOpenConfirm(
		connectionId,
		[]byte("ignored-proof"),
		10,
	))

	if len(client.membershipProofs) != 0 {
		t.Fatalf("ForceConnectionOpenConfirm membership verifications: got %d want 0", len(client.membershipProofs))
	}
	conn, ok := store.getConnection(connectionId)
	if !ok {
		t.Fatal("ForceConnectionOpenConfirm connection not saved")
	}
	if conn.State != types.ConnectionStateOpen {
		t.Fatalf("ForceConnectionOpenConfirm state: got %v want Open", conn.State)
	}
}

func TestForceConnectionOpenTryPanicsWhenCallerIsNotAdmin(cur realm, t *testing.T) {
	resetStore()
	admin = testutils.TestAddress("authorized-admin")
	defer func() { admin = "" }()

	uassert.AbortsContains(t, cur, "unauthorized", func(cur realm) {
		ForceConnectionOpenTry(cur, types.NewMsgConnectionOpenTry(
			types.ClientId(1),
			types.ClientId(99),
			types.ConnectionId(77),
			nil,
			10,
		))
	})
}
