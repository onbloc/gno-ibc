package manager

type Access struct {
	Since TimePoint
	Delay Delay
}

func NewAccess(since TimePoint) Access {
	return Access{
		Since: since,
	}
}

func NewAccessWithDelay(since TimePoint, grantDelay Delay, executionDelay Delay) Access {
	if since.IsZero() {
		return Access{Since: 0}
	}

	return Access{
		Since: since + TimePoint(grantDelay),
		Delay: executionDelay,
	}
}

func (access Access) isActiveAt(now TimePoint) bool {
	if access.Since.IsZero() {
		return false
	}

	return !access.Since.After(now)
}
