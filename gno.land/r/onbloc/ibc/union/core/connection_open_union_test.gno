package core

import (
	"strings"
	"testing"

	"gno.land/p/onbloc/ibc/union/types"
)

func setupUnionConnectionTest(cur realm) (types.ClientId, *mockClient, func()) {
	resetStore(cur)
	cleanup := setAdminForTest(cur)
	client := &mockClient{status: types.StatusActive}
	return registerMockClient(client), client, cleanup
}

func assertUnionConnectionEqual(t *testing.T, id types.ConnectionId, want types.Connection) {
	t.Helper()
	got, ok := store.getConnection(id)
	if !ok {
		t.Fatal("connection not saved")
	}
	if got.State != want.State {
		t.Fatalf("connection state: got %v want %v", got.State, want.State)
	}
	if got.ClientId != want.ClientId {
		t.Fatalf("connection client id: got %v want %v", got.ClientId, want.ClientId)
	}
	if got.CounterpartyClientId != want.CounterpartyClientId {
		t.Fatalf("connection counterparty client id: got %v want %v", got.CounterpartyClientId, want.CounterpartyClientId)
	}
	if got.CounterpartyConnectionId != want.CounterpartyConnectionId {
		t.Fatalf("connection counterparty connection id: got %v want %v", got.CounterpartyConnectionId, want.CounterpartyConnectionId)
	}
}

func mustPanicContains(t *testing.T, want string, fn func()) {
	t.Helper()
	defer func() {
		r := recover()
		if r == nil {
			t.Fatal("expected panic but none occurred")
		}
		got := r.(string)
		if !strings.Contains(got, want) {
			t.Fatalf("panic: got %q want containing %q", got, want)
		}
	}()
	fn()
}

// Converted from Union connection_open_init_ok:
// https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/core/src/tests/connection/ibc.rs#L18-L66
func TestUnionConnectionOpenInitOk(cur realm, t *testing.T) {
	clientId, _, cleanup := setupUnionConnectionTest(cur)
	defer cleanup()

	ConnectionOpenInit(cross(cur), types.NewMsgConnectionOpenInit(clientId, types.ClientId(2)))
}

// Converted from Union connection_open_init_commitment_saved:
// https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/core/src/tests/connection/ibc.rs#L68-L111
func TestUnionConnectionOpenInitCommitmentSaved(cur realm, t *testing.T) {
	clientId, _, cleanup := setupUnionConnectionTest(cur)
	defer cleanup()

	ConnectionOpenInit(cross(cur), types.NewMsgConnectionOpenInit(clientId, types.ClientId(2)))

	assertUnionConnectionEqual(t, types.ConnectionId(1), types.Connection{
		State:                types.ConnectionStateInit,
		ClientId:             clientId,
		CounterpartyClientId: types.ClientId(2),
	})
}

// Converted from Union connection_open_try_ok:
// https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/core/src/tests/connection/ibc.rs#L113-L168
func TestUnionConnectionOpenTryOk(cur realm, t *testing.T) {
	clientId, client, cleanup := setupUnionConnectionTest(cur)
	defer cleanup()

	ConnectionOpenTry(cross(cur), types.NewMsgConnectionOpenTry(
		clientId,
		types.ClientId(2),
		types.ConnectionId(1),
		[]byte{1, 2, 3},
		1,
	))

	if len(client.membershipProofs) != 1 {
		t.Fatalf("membership verifications: got %d want 1", len(client.membershipProofs))
	}
}

// Converted from Union connection_open_try_client_not_found:
// https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/core/src/tests/connection/ibc.rs#L170-L226
func TestUnionConnectionOpenTryClientNotFound(cur realm, t *testing.T) {
	resetStore(cur)
	cleanup := setAdminForTest(cur)
	defer cleanup()

	mustPanicContains(t, "client 1 not found", func() {
		connectionOpenTry(types.NewMsgConnectionOpenTry(
			types.ClientId(1),
			types.ClientId(2),
			types.ConnectionId(1),
			[]byte{1, 2, 3},
			1,
		), true)
	})
}

// Converted from Union connection_open_try_commitment_saved:
// https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/core/src/tests/connection/ibc.rs#L233-L296
func TestUnionConnectionOpenTryCommitmentSaved(cur realm, t *testing.T) {
	clientId, _, cleanup := setupUnionConnectionTest(cur)
	defer cleanup()

	ConnectionOpenTry(cross(cur), types.NewMsgConnectionOpenTry(
		clientId,
		types.ClientId(2),
		types.ConnectionId(1),
		[]byte{1, 2, 3},
		1,
	))

	assertUnionConnectionEqual(t, types.ConnectionId(1), types.Connection{
		State:                    types.ConnectionStateTryOpen,
		ClientId:                 clientId,
		CounterpartyClientId:     types.ClientId(2),
		CounterpartyConnectionId: types.ConnectionId(1),
	})
}

// Converted from Union connection_open_ack_ok:
// https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/core/src/tests/connection/ibc.rs#L298-L353
func TestUnionConnectionOpenAckOk(cur realm, t *testing.T) {
	clientId, client, cleanup := setupUnionConnectionTest(cur)
	defer cleanup()

	ConnectionOpenInit(cross(cur), types.NewMsgConnectionOpenInit(clientId, types.ClientId(2)))
	ConnectionOpenAck(cross(cur), types.NewMsgConnectionOpenAck(
		types.ConnectionId(1),
		types.ConnectionId(1),
		[]byte{1, 2, 3},
		1,
	))

	if len(client.membershipProofs) != 1 {
		t.Fatalf("membership verifications: got %d want 1", len(client.membershipProofs))
	}
}

// Converted from Union connection_open_ack_commitment_saved:
// https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/core/src/tests/connection/ibc.rs#L360-L423
func TestUnionConnectionOpenAckCommitmentSaved(cur realm, t *testing.T) {
	clientId, _, cleanup := setupUnionConnectionTest(cur)
	defer cleanup()

	ConnectionOpenInit(cross(cur), types.NewMsgConnectionOpenInit(clientId, types.ClientId(2)))
	ConnectionOpenAck(cross(cur), types.NewMsgConnectionOpenAck(
		types.ConnectionId(1),
		types.ConnectionId(1),
		[]byte{1, 2, 3},
		1,
	))

	assertUnionConnectionEqual(t, types.ConnectionId(1), types.Connection{
		State:                    types.ConnectionStateOpen,
		ClientId:                 clientId,
		CounterpartyClientId:     types.ClientId(2),
		CounterpartyConnectionId: types.ConnectionId(1),
	})
}

// Converted from Union connection_open_confirm_ok:
// https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/core/src/tests/connection/ibc.rs#L425-L479
func TestUnionConnectionOpenConfirmOk(cur realm, t *testing.T) {
	clientId, client, cleanup := setupUnionConnectionTest(cur)
	defer cleanup()

	ConnectionOpenTry(cross(cur), types.NewMsgConnectionOpenTry(
		clientId,
		types.ClientId(2),
		types.ConnectionId(1),
		[]byte{1, 2, 3},
		1,
	))
	ConnectionOpenConfirm(cross(cur), types.NewMsgConnectionOpenConfirm(types.ConnectionId(1), []byte{1, 2, 3}, 1))

	if len(client.membershipProofs) != 2 {
		t.Fatalf("membership verifications: got %d want 2", len(client.membershipProofs))
	}
}

// Converted from Union connection_open_try_confirm_commitment_saved:
// https://github.com/unionlabs/union/blob/edaacacccc3544d69ce1fac0aa1c7e9b6fe83216/cosmwasm/core/src/tests/connection/ibc.rs#L486-L544
func TestUnionConnectionOpenTryConfirmCommitmentSaved(cur realm, t *testing.T) {
	clientId, _, cleanup := setupUnionConnectionTest(cur)
	defer cleanup()

	ConnectionOpenTry(cross(cur), types.NewMsgConnectionOpenTry(
		clientId,
		types.ClientId(2),
		types.ConnectionId(1),
		[]byte{1, 2, 3},
		1,
	))
	ConnectionOpenConfirm(cross(cur), types.NewMsgConnectionOpenConfirm(types.ConnectionId(1), []byte{1, 2, 3}, 1))

	assertUnionConnectionEqual(t, types.ConnectionId(1), types.Connection{
		State:                    types.ConnectionStateOpen,
		ClientId:                 clientId,
		CounterpartyClientId:     types.ClientId(2),
		CounterpartyConnectionId: types.ConnectionId(1),
	})
}
