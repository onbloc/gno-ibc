package manager

const (
	AdminRole  RoleId = 0
	PublicRole RoleId = 1<<64 - 1 // uint64 max

	// MinSetback mirrors OpenZeppelin/Union's minimum delay-change setback.
	MinSetback Delay = 5 * 24 * 60 * 60
)
