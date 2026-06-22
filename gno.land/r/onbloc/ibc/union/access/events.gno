package access

import "chain"

const EventTypeAdminChanged = "AdminChanged"

func EmitAdminChangedEvent(oldAdmin address, newAdmin address) {
	chain.Emit(
		EventTypeAdminChanged,
		"old_admin", oldAdmin.String(),
		"new_admin", newAdmin.String(),
	)
}
