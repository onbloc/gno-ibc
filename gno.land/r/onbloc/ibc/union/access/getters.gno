package access

import "gno.land/p/onbloc/access/manager"

// HasRole returns role membership status for account.
// Union reference:
// https://github.com/unionlabs/union/blob/8cff0ff34f6baa4cdb1e4650a08985dd05de0c5a/cosmwasm/access-manager/src/contract.rs#L1172-L1197
func HasRole(cur realm, role manager.RoleId, account address) manager.HasRoleResult {
	return accessState.HasRole(role, account)
}

// GetRoleAdmin returns the admin role configured for role.
// Union reference:
// https://github.com/unionlabs/union/blob/8cff0ff34f6baa4cdb1e4650a08985dd05de0c5a/cosmwasm/access-manager/src/contract.rs#L1119-L1126
func GetRoleAdmin(cur realm, role manager.RoleId) manager.RoleId {
	return accessState.GetRoleAdmin(role)
}

// GetRoleGrantDelay returns the grant delay configured for role.
// Union reference:
// https://github.com/unionlabs/union/blob/8cff0ff34f6baa4cdb1e4650a08985dd05de0c5a/cosmwasm/access-manager/src/contract.rs#L1137-L1145
func GetRoleGrantDelay(cur realm, role manager.RoleId) manager.Delay {
	return accessState.GetRoleGrantDelay(role)
}

// GetFunctionRole returns the selector role for the calling realm's target path.
// Union reference:
// https://github.com/unionlabs/union/blob/8cff0ff34f6baa4cdb1e4650a08985dd05de0c5a/cosmwasm/access-manager/src/contract.rs#L1091-L1107
func GetFunctionRole(cur realm, selector manager.Selector) manager.RoleId {
	return GetTargetFunctionRole(cur, selector)
}

// GetTargetFunctionRole returns the selector role for the calling realm's target path.
// Union reference:
// https://github.com/unionlabs/union/blob/8cff0ff34f6baa4cdb1e4650a08985dd05de0c5a/cosmwasm/access-manager/src/contract.rs#L1091-L1107
func GetTargetFunctionRole(cur realm, selector manager.Selector) manager.RoleId {
	target := cur.Previous().PkgPath()
	return accessState.GetTargetFunctionRole(target, selector)
}

// IsTargetClosed reports whether the calling realm's target path is closed.
// Union reference:
// https://github.com/unionlabs/union/blob/8cff0ff34f6baa4cdb1e4650a08985dd05de0c5a/cosmwasm/access-manager/src/contract.rs#L1082-L1089
func IsTargetClosed(cur realm) bool {
	target := cur.Previous().PkgPath()
	return accessState.IsTargetClosed(target)
}

// CanCall reports whether caller can call selector on the calling realm's target path.
// Union reference:
// https://github.com/unionlabs/union/blob/8cff0ff34f6baa4cdb1e4650a08985dd05de0c5a/cosmwasm/access-manager/src/contract.rs#L1033-L1068
func CanCall(cur realm, selector manager.Selector, caller address) manager.CanCallResult {
	target := cur.Previous().PkgPath()
	return accessState.CanCall(caller, target, selector)
}

// IsAuthorized reports immediate call authorization for the calling realm's target path.
// Union reference:
// https://github.com/unionlabs/union/blob/8cff0ff34f6baa4cdb1e4650a08985dd05de0c5a/cosmwasm/access-manager/src/contract.rs#L1033-L1068
func IsAuthorized(cur realm, selector manager.Selector, caller address) bool {
	target := cur.Previous().PkgPath()
	return accessState.IsAuthorized(caller, target, selector)
}

// CanAdminRole reports whether caller can administer role.
func CanAdminRole(cur realm, role manager.RoleId, caller address) manager.CanCallResult {
	return accessState.CanAdminRole(role, caller)
}

// CanManageTarget reports whether caller can manage target configuration.
func CanManageTarget(cur realm, caller address) manager.CanCallResult {
	return accessState.CanManageTarget(caller)
}
