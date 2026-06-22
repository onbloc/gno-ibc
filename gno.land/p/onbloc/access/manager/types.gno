package manager

type RoleId uint64
type Selector string
type Delay uint32

const (
	AdminRole  RoleId = 0
	PublicRole RoleId = 1<<64 - 1 // uint64 max
)

type State struct {
	Roles   map[RoleId]*RoleConfig
	Targets map[string]*TargetConfig
}

type RoleConfig struct {
	Members    map[address]Access
	Admin      RoleId
	GrantDelay Delay
}

type Access struct {
	Since Timepoint
}

type TargetConfig struct {
	FunctionRoles map[Selector]RoleId
	Closed        bool
}

type CanCallResult struct {
	Immediate bool
}

type HasRoleResult struct {
	IsMember bool
}

func NewRoleId(id uint64) RoleId {
	return RoleId(id)
}

func NewSelector(selector string) Selector {
	return Selector(selector)
}

func NewDelay(delay uint32) Delay {
	return Delay(delay)
}

func NewState() State {
	return State{
		Roles:   make(map[RoleId]*RoleConfig),
		Targets: make(map[string]*TargetConfig),
	}
}

func NewRoleConfig(admin RoleId, grantDelay Delay) *RoleConfig {
	return &RoleConfig{
		Members:    make(map[address]Access),
		Admin:      admin,
		GrantDelay: grantDelay,
	}
}

func NewAccess(since Timepoint) Access {
	return Access{
		Since: since,
	}
}

func NewTargetConfig(closed bool) *TargetConfig {
	return &TargetConfig{
		FunctionRoles: make(map[Selector]RoleId),
		Closed:        closed,
	}
}

func NewCanCallResult(immediate bool) CanCallResult {
	return CanCallResult{
		Immediate: immediate,
	}
}

func NewHasRoleResult(isMember bool) HasRoleResult {
	return HasRoleResult{
		IsMember: isMember,
	}
}
