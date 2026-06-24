package statelensics23mpt

import (
	"testing"

	"gno.land/p/nt/uassert/v0"
	"gno.land/r/onbloc/ibc/union/access"
	core "gno.land/r/onbloc/ibc/union/core"
	_ "gno.land/r/onbloc/ibc/union/core/v1"
)

func setup(cur realm) {
	loaderAddr := cur.Address()
	testing.SetRealm(testing.NewUserRealm(access.DefaultAdminAddress))
	core.UpdateImpl(cross(cur), "gno.land/r/onbloc/ibc/union/core/v1")
	access.GrantRole(cross(cur), access.RelayerRole, loaderAddr)
}

func TestRegisterClientRegistersType(cur realm, t *testing.T) {
	setup(cur)

	RegisterClient(cross(cur))

	if !core.HasClient(ClientType) {
		t.Fatal("RegisterClient must register the client type")
	}
}

func TestRegisterClientRejectsDuplicate(cur realm, t *testing.T) {
	setup(cur)
	if !core.HasClient(ClientType) {
		RegisterClient(cross(cur))
	}

	uassert.AbortsContains(t, cur, "client type already exists", func(cur realm) {
		RegisterClient(cross(cur))
	})
}
