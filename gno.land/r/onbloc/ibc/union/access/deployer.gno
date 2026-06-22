package access

import (
	manager "gno.land/p/onbloc/access/manager"
	"gno.land/p/onbloc/ibc/union/types"
)

const CoreRealmPath = "gno.land/r/onbloc/ibc/union/core"

func init(cur realm) {
	resetAccess(cur.Previous().Address())
}

// resetAccess mirrors the deploy-time setup that Union performs through its
// deployer after instantiating AccessManager. Gno has no instantiate message, so
// this realm applies that setup during init.
func resetAccess(initialAdmin address) {
	accessState = manager.NewState()
	grantRoleUnchecked(manager.AdminRole, initialAdmin)
	grantRoleUnchecked(RelayerRole, initialAdmin)
	setupRoles()
}

// Union reference:
// https://github.com/unionlabs/union/blob/8cff0ff34f6baa4cdb1e4650a08985dd05de0c5a/cosmwasm/deployer/src/main.rs#L1779
func setupRoles() {
	accessState.SetTargetFunctionRoles(CoreRealmPath, types.RelayerSelectors(), RelayerRole)
}
