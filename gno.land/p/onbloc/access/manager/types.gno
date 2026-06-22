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
	Since          Timepoint
	ExecutionDelay Delay
}

type TargetConfig struct {
	FunctionRoles map[Selector]RoleId
	AdminDelay    Delay
	Closed        bool
}

type CanCallResult struct {
	Immediate bool
	Delay     Delay
}

type HasRoleResult struct {
	IsMember       bool
	ExecutionDelay Delay
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

func NewAccess(since Timepoint, executionDelay Delay) Access {
	return Access{
		Since:          since,
		ExecutionDelay: executionDelay,
	}
}

func NewTargetConfig(adminDelay Delay, closed bool) *TargetConfig {
	return &TargetConfig{
		FunctionRoles: make(map[Selector]RoleId),
		AdminDelay:    adminDelay,
		Closed:        closed,
	}
}

func NewCanCallResult(immediate bool, delay Delay) CanCallResult {
	return CanCallResult{
		Immediate: immediate,
		Delay:     delay,
	}
}

func NewHasRoleResult(isMember bool, executionDelay Delay) HasRoleResult {
	return HasRoleResult{
		IsMember:       isMember,
		ExecutionDelay: executionDelay,
	}
}
