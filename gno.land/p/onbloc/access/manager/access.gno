package manager

type Access struct {
	Since TimePoint
	Delay DelayedValue
}

func NewAccess(since TimePoint, grantDelay Delay, executionDelay Delay) Access {
	if since.IsZero() {
		return Access{Since: 0}
	}

	return Access{
		Since: since + TimePoint(grantDelay),
		Delay: NewDelayedValue(executionDelay),
	}
}

func (access Access) executionDelayAt(now TimePoint) Delay {
	return access.Delay.Get(now)
}

func (access Access) fullAt(now TimePoint) FullAccess {
	currentDelay, pendingDelay, effect := access.Delay.GetFull(now)

	return FullAccess{
		Since:        access.Since,
		CurrentDelay: currentDelay,
		PendingDelay: pendingDelay,
		Effect:       effect,
	}
}

func (access Access) withExecutionDelayUpdate(now TimePoint, executionDelay Delay) (Access, TimePoint) {
	delay, effect := access.Delay.WithUpdate(now, executionDelay, 0)
	access.Delay = delay

	return access, effect
}

func (access Access) isActiveAt(now TimePoint) bool {
	if access.Since.IsZero() {
		return false
	}

	return !access.Since.After(now)
}
