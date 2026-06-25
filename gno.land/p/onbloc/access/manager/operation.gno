package manager

import (
	"crypto/sha256"
	"encoding/hex"
)

const (
	OperationExpiration Delay = 7 * 24 * 60 * 60

	SelectorSetFunctionRole     Selector = "set_function_role"
	SelectorSetFunctionRoles    Selector = "set_function_roles"
	SelectorSetTargetClosed     Selector = "set_target_closed"
	SelectorSetTargetAdminDelay Selector = "set_target_admin_delay"
)

// HashOperation returns the identifier for a delayed operation.
// OpenZeppelin reference:
// https://github.com/OpenZeppelin/openzeppelin-contracts/blob/5fd1781b1454fd1ef8e722282f86f9293cacf256/contracts/access/manager/AccessManager.sol#L582-L588
func HashOperation(caller address, target string, selector Selector, dataHash string) OperationId {
	sum := sha256.Sum256([]byte(caller.String() + "/" + target + "/" + string(selector) + "/" + dataHash))

	return OperationId("0x" + hex.EncodeToString(sum[:]))
}

func (schedule Schedule) isReady(now TimePoint) bool {
	return schedule.IsSet() && !schedule.Timepoint.After(now)
}

func (schedule Schedule) isExpired(now TimePoint) bool {
	return schedule.IsSet() && now.After(schedule.Timepoint+TimePoint(OperationExpiration))
}
