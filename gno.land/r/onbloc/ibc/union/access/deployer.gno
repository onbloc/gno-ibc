package access

import manager "gno.land/p/onbloc/access/manager"

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
	applyUnionDeployerRoleSetup()
}

func applyUnionDeployerRoleSetup() {
	accessState.SetTargetFunctionRoles(CoreTarget, unionDeployerRelayerSelectors(), RelayerRole)
}

// Union reference:
// https://github.com/unionlabs/union/blob/8cff0ff34f6baa4cdb1e4650a08985dd05de0c5a/cosmwasm/deployer/src/main.rs#L1823-L1837
func unionDeployerRelayerSelectors() []manager.Selector {
	return []manager.Selector{
		SelectorCreateClient,
		SelectorUpdateClient,
		SelectorConnectionOpenInit,
		SelectorConnectionOpenTry,
		SelectorConnectionOpenAck,
		SelectorConnectionOpenConfirm,
		SelectorChannelOpenInit,
		SelectorChannelOpenTry,
		SelectorChannelOpenAck,
		SelectorChannelOpenConfirm,
		SelectorBatchSend,
		SelectorBatchAcks,
		SelectorPacketRecv,
		SelectorIntentPacketRecv,
		SelectorPacketAck,
		SelectorPacketTimeout,
	}
}
