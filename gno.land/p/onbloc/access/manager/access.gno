package manager

type Access struct {
	Since TimePoint
	Delay DelayedValue
}

// NewAccess returns an access record whose membership becomes active after the
// role grant delay and whose guarded calls use executionDelay.
// OpenZeppelin reference:
// https://github.com/OpenZeppelin/openzeppelin-contracts/blob/5fd1781b1454fd1ef8e722282f86f9293cacf256/contracts/access/manager/AccessManager.sol#L72-L79
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
