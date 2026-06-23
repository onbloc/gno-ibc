package manager

func (access Access) isActiveAt(now Timepoint) bool {
	if access.Since.IsZero() {
		return false
	}
	return !access.Since.After(now)
}
