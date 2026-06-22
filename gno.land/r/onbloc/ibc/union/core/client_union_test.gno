package core

import (
	"errors"
	"testing"

	"gno.land/p/nt/testutils/v0"
	"gno.land/p/nt/uassert/v0"
	"gno.land/p/onbloc/ibc/union/types"
)

// Union reference:
// https://github.com/unionlabs/union/blob/8cff0ff34f6baa4cdb1e4650a08985dd05de0c5a/cosmwasm/core/src/tests/client/ibc.rs#L31-L63
func TestRegisterClientUnionOk(cur realm, t *testing.T) {
	resetStore(cur)
	lc := &mockClient{chainId: "union-1", height: types.NewHeight(1)}

	RegisterClient(cross(cur), mockType, lc)

	if !HasClient(mockType) {
		t.Fatalf("registered client type not found")
	}
	got, ok := store.registeredClient(mockType)
	if !ok {
		t.Fatalf("registered client missing from store")
	}
	if got != lc {
		t.Fatalf("registered light client mismatch")
	}
}

// Union reference:
// https://github.com/unionlabs/union/blob/8cff0ff34f6baa4cdb1e4650a08985dd05de0c5a/cosmwasm/core/src/tests/client/ibc.rs#L65-L89
func TestRegisterClientUnionRejectsDuplicate(cur realm, t *testing.T) {
	resetStore(cur)
	RegisterClient(cross(cur), mockType, &mockClient{})

	uassert.AbortsContains(t, cur, "client type already exists", func(cur realm) {
		RegisterClient(cross(cur), mockType, &mockClient{})
	})
}

// Union references:
// https://github.com/unionlabs/union/blob/8cff0ff34f6baa4cdb1e4650a08985dd05de0c5a/cosmwasm/core/src/tests/client/ibc.rs#L91-L125
// https://github.com/unionlabs/union/blob/8cff0ff34f6baa4cdb1e4650a08985dd05de0c5a/cosmwasm/core/src/tests/client/ibc.rs#L127-L190
// Gno intentionally ignores msg.Relayer and passes the caller as relayer.
func TestCreateClientUnionUsesRegisteredClient(cur realm, t *testing.T) {
	resetStore(cur)
	creator := testutils.TestAddress("union-client-creator")
	ignoredRelayer := testutils.TestAddress("ignored-relayer")
	testing.SetRealm(testing.NewUserRealm(creator))
	lc := &mockClient{
		chainId: "union-1",
		height:  types.NewHeight(1),
		status:  types.StatusActive,
		creationStorage: map[string][]byte{
			"create-key": []byte("create-value"),
		},
	}
	RegisterClient(cross(cur), mockType, lc)

	clientId := CreateClient(cross(cur), types.MsgCreateClient{
		ClientType:          mockType,
		ClientStateBytes:    []byte("client"),
		ConsensusStateBytes: []byte("consensus"),
		Relayer:             ignoredRelayer.String(),
	})

	c := store.getClient(clientId)
	if c == nil {
		t.Fatalf("client not stored")
	}
	if c.creator != creator {
		t.Fatalf("creator: got %s want %s", c.creator, creator)
	}
	if c.lightClient != lc {
		t.Fatalf("stored light client mismatch")
	}
	if queryClientStateHex(clientId) != "0x636c69656e74" {
		t.Fatalf("client state not stored")
	}
	if queryConsensusStateHex(clientId, 1) != "0x636f6e73656e737573" {
		t.Fatalf("consensus state not stored at latest height")
	}
	if len(lc.creationRelayers) != 1 || lc.creationRelayers[0] != creator {
		t.Fatalf("VerifyCreation relayer: got %v want %s", lc.creationRelayers, creator)
	}
	value, ok := c.getClientStore("create-key")
	if !ok || string(value) != "create-value" {
		t.Fatalf("creation storage write not saved: got %q found=%v", string(value), ok)
	}
}

// Union references:
// https://github.com/unionlabs/union/blob/8cff0ff34f6baa4cdb1e4650a08985dd05de0c5a/cosmwasm/core/src/tests/client/ibc.rs#L194-L265
// https://github.com/unionlabs/union/blob/8cff0ff34f6baa4cdb1e4650a08985dd05de0c5a/cosmwasm/core/src/tests/client/ibc.rs#L448-L548
// Gno intentionally ignores msg.Relayer and passes the caller as relayer.
func TestUpdateClientUnionMirrorsStateUpdate(cur realm, t *testing.T) {
	resetStore(cur)
	ignoredRelayer := testutils.TestAddress("ignored-relayer")
	wantRelayer := cur.Address()
	lc := &mockClient{
		chainId: "union-1",
		height:  types.NewHeight(1),
		status:  types.StatusActive,
		updateStorage: map[string][]byte{
			"update-key": []byte("update-value"),
		},
	}
	RegisterClient(cross(cur), mockType, lc)
	clientId := CreateClient(cross(cur), types.NewMsgCreateClient(mockType, []byte("old-client"), []byte("old-consensus")))

	height := UpdateClient(cross(cur), types.MsgUpdateClient{
		ClientId:      clientId,
		ClientMessage: []byte("header"),
		Relayer:       ignoredRelayer.String(),
	})

	if height != types.NewHeight(2) {
		t.Fatalf("updated height: got %s want 2", height.String())
	}
	if queryClientStateHex(clientId) != "0x6373" {
		t.Fatalf("updated client state not mirrored")
	}
	if queryConsensusStateHex(clientId, 2) != "0x636f6e73" {
		t.Fatalf("updated consensus state not mirrored")
	}
	if len(lc.headerMessages) != 1 || string(lc.headerMessages[0]) != "header" {
		t.Fatalf("header not passed to light client")
	}
	if len(lc.headerRelayers) != 1 || lc.headerRelayers[0] != wantRelayer {
		t.Fatalf("VerifyHeader relayer: got %v want %s", lc.headerRelayers, wantRelayer)
	}
	value, ok := store.getClient(clientId).getClientStore("update-key")
	if !ok || string(value) != "update-value" {
		t.Fatalf("update storage write not saved: got %q found=%v", string(value), ok)
	}
}

// Union reference:
// https://github.com/unionlabs/union/blob/8cff0ff34f6baa4cdb1e4650a08985dd05de0c5a/cosmwasm/core/src/tests/client/ibc.rs#L267-L330
func TestUpdateClientUnionRejectsLightClientUpdateError(cur realm, t *testing.T) {
	resetStore(cur)
	lc := &mockClient{
		chainId: "union-1",
		height:  types.NewHeight(1),
		status:  types.StatusActive,
	}
	RegisterClient(cross(cur), mockType, lc)
	clientId := CreateClient(cross(cur), types.NewMsgCreateClient(mockType, []byte("old-client"), []byte("old-consensus")))

	lc.updateErr = errors.New("union update failed")

	uassert.AbortsContains(t, cur, "update client: union update failed", func(cur realm) {
		UpdateClient(cross(cur), types.MsgUpdateClient{
			ClientId:      clientId,
			ClientMessage: []byte("header"),
		})
	})
}

// Union reference:
// https://github.com/unionlabs/union/blob/8cff0ff34f6baa4cdb1e4650a08985dd05de0c5a/cosmwasm/core/src/tests/client/ibc.rs#L333-L446
func TestForceUpdateClientUnionMirrorsSubmittedState(cur realm, t *testing.T) {
	resetStore(cur)
	adminAddr := testutils.TestAddress("admin")
	testing.SetRealm(testing.NewUserRealm(adminAddr))
	admin = adminAddr

	lc := &mockClient{
		chainId: "union-1",
		height:  types.NewHeight(1),
		status:  types.StatusActive,
		creationStorage: map[string][]byte{
			"force-key": []byte("old-force-value"),
		},
	}
	RegisterClient(cross(cur), mockType, lc)
	clientId := CreateClient(cross(cur), types.NewMsgCreateClient(mockType, []byte("old-client"), []byte("old-consensus")))

	lc.height = types.NewHeight(3)
	lc.creationStorage = map[string][]byte{
		"force-key": []byte("force-value"),
	}
	height := ForceUpdateClient(cross(cur), types.NewMsgForceUpdateClient(clientId, []byte("force-client"), []byte("force-consensus")))

	if height != types.NewHeight(3) {
		t.Fatalf("force update height: got %s want 3", height.String())
	}
	if queryClientStateHex(clientId) != "0x666f7263652d636c69656e74" {
		t.Fatalf("force client state not mirrored")
	}
	if queryConsensusStateHex(clientId, 3) != "0x666f7263652d636f6e73656e737573" {
		t.Fatalf("force consensus state not mirrored")
	}
	value, ok := store.getClient(clientId).getClientStore("force-key")
	if !ok || string(value) != "force-value" {
		t.Fatalf("force storage write not saved: got %q found=%v", string(value), ok)
	}
}
