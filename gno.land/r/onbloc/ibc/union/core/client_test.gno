package core

import (
	"testing"

	"gno.land/p/nt/uassert/v0"
	"gno.land/p/onbloc/ibc/union/types"
)

func TestCreateClientRejectsUnregisteredType(cur realm, t *testing.T) {
	resetStore(cur)

	uassert.AbortsContains(t, cur, "client type not found", func(cur realm) {
		CreateClient(cross(cur), types.NewMsgCreateClient(mockType, nil, nil))
	})
}

// Union implementation behavior: update_client stores consensus_state_bytes
// unconditionally because the field is not optional in UpdateStateResponse.
func TestUpdateClientStoresEmptyConsensusState(cur realm, t *testing.T) {
	resetStore(cur)
	lc := &mockClient{
		chainId:                   "union-1",
		height:                    types.NewHeight(1),
		status:                    types.StatusActive,
		updateConsensusStateBytes: []byte{},
	}
	RegisterClient(cross(cur), mockType, lc)
	CreateClient(cross(cur), types.NewMsgCreateClient(mockType, []byte("old-client"), []byte("old-consensus")))
	clientId := types.ClientId(1)

	UpdateClient(cross(cur), types.MsgUpdateClient{
		ClientId:      clientId,
		ClientMessage: []byte("header"),
	})

	bz, ok := store.getClient(clientId).getConsensusState(types.NewHeight(2))
	if !ok {
		t.Fatalf("empty consensus state was not stored")
	}
	if len(bz) != 0 {
		t.Fatalf("empty consensus state: got %q want empty", string(bz))
	}
}
