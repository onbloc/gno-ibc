package access

import (
	"strconv"

	manager "gno.land/p/onbloc/access/manager"
)

const (
	ErrorAccessManagerUnauthorizedAccount = "AccessManagerUnauthorizedAccount"
	ErrorAccessManagerUnauthorizedCall    = "AccessManagerUnauthorizedCall"
)

func AccessManagerUnauthorizedAccountError(caller address, requiredRole manager.RoleId) string {
	return ErrorAccessManagerUnauthorizedAccount +
		": " + caller.String() +
		" must have role " + strconv.FormatUint(uint64(requiredRole), 10)
}

func AccessManagerUnauthorizedCallError(caller address, target string, selector manager.Selector) string {
	return ErrorAccessManagerUnauthorizedCall +
		": " + caller.String() +
		" is not authorized to call " + string(selector) +
		" on " + target
}
