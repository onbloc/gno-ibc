package manager

import "time"

type Timepoint int64

func NewTimepoint(timepoint int64) Timepoint {
	return Timepoint(timepoint)
}

func CurrentTimepoint() Timepoint {
	return NewTimepoint(time.Now().Unix())
}

func (t Timepoint) availableAt(delay Delay) Timepoint {
	since := t + Timepoint(delay)
	if since == 0 {
		return NewTimepoint(1)
	}
	return since
}
