package manager

type TargetConfig struct {
	FunctionRoles map[Selector]RoleId
	Closed        bool
	AdminDelay    DelayedValue
}

// NewTargetConfig returns a target configuration with the provided closed flag.
// OpenZeppelin reference:
// https://github.com/OpenZeppelin/openzeppelin-contracts/blob/5fd1781b1454fd1ef8e722282f86f9293cacf256/contracts/access/manager/AccessManager.sol#L65-L70
func NewTargetConfig(closed bool) *TargetConfig {
	return &TargetConfig{
		FunctionRoles: make(map[Selector]RoleId),
		Closed:        closed,
	}
}

func (targetConfig *TargetConfig) setFunctionRole(selector Selector, role RoleId) {
	targetConfig.ensureFunctionRoles()

	targetConfig.FunctionRoles[selector] = role
}

func (targetConfig *TargetConfig) setFunctionRoles(selectors []Selector, role RoleId) {
	for i := range selectors {
		targetConfig.setFunctionRole(selectors[i], role)
	}
}

func (targetConfig *TargetConfig) functionRole(selector Selector) RoleId {
	targetConfig.ensureFunctionRoles()

	role, found := targetConfig.FunctionRoles[selector]
	if !found {
		return AdminRole
	}

	return role
}

func (targetConfig *TargetConfig) setClosed(closed bool) {
	targetConfig.Closed = closed
}

func (targetConfig *TargetConfig) isClosed() bool {
	return targetConfig.Closed
}

func (targetConfig *TargetConfig) setAdminDelay(delay Delay) {
	targetConfig.AdminDelay = NewDelayedValue(delay)
}

func (targetConfig *TargetConfig) setAdminDelayWithSetback(delay Delay, now TimePoint) TimePoint {
	adminDelay, effect := targetConfig.AdminDelay.WithUpdate(now, delay, MinSetback)
	targetConfig.AdminDelay = adminDelay

	return effect
}

func (targetConfig *TargetConfig) adminDelayAt(now TimePoint) Delay {
	return targetConfig.AdminDelay.Get(now)
}

func (targetConfig *TargetConfig) adminDelay() Delay {
	return targetConfig.adminDelayAt(CurrentTimePoint())
}

func (targetConfig *TargetConfig) ensureFunctionRoles() {
	if targetConfig.FunctionRoles == nil {
		targetConfig.FunctionRoles = make(map[Selector]RoleId)
	}
}
