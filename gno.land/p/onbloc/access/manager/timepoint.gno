package manager

import "time"

type Timepoint = time.Time

func NewTimepoint(timepoint int64) Timepoint {
	return time.Unix(timepoint, 0).UTC()
}

func CurrentTimepoint() Timepoint {
	return time.Now()
}

func timepointAvailableAt(timepoint Timepoint, delay Delay) Timepoint {
	if timepoint.IsZero() {
		return timepoint
	}
	return timepoint.Add(time.Duration(delay) * time.Second)
}
