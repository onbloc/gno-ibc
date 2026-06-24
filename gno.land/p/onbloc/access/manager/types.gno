package manager

import "strconv"

type Selector string

func NewSelector(selector string) Selector {
	return Selector(selector)
}

type Delay uint32

func NewDelay(delay uint32) Delay {
	return Delay(delay)
}

func (d Delay) Uint32() uint32 {
	return uint32(d)
}

func (d Delay) String() string {
	return strconv.FormatUint(uint64(d), 10)
}

type CanCallResult struct {
	Immediate  bool
	Authorized bool
	Delay      Delay
}

func NewCanCallResult(immediate bool) CanCallResult {
	return CanCallResult{
		Immediate:  immediate,
		Authorized: immediate,
	}
}

func NewDelayedCanCallResult(delay Delay) CanCallResult {
	return CanCallResult{
		Authorized: true,
		Delay:      delay,
	}
}

type HasRoleResult struct {
	IsMember       bool
	ExecutionDelay Delay
}

func NewHasRoleResult(isMember bool) HasRoleResult {
	return HasRoleResult{
		IsMember: isMember,
	}
}

func NewHasRoleResultWithDelay(isMember bool, executionDelay Delay) HasRoleResult {
	return HasRoleResult{
		IsMember:       isMember,
		ExecutionDelay: executionDelay,
	}
}

type OperationId string

func (id OperationId) String() string {
	return string(id)
}

type Nonce uint64

func (nonce Nonce) Uint64() uint64 {
	return uint64(nonce)
}

func (nonce Nonce) String() string {
	return strconv.FormatUint(uint64(nonce), 10)
}

type Schedule struct {
	Timepoint TimePoint
	Nonce     Nonce
}

func NewSchedule(timepoint TimePoint, nonce Nonce) Schedule {
	return Schedule{
		Timepoint: timepoint,
		Nonce:     nonce,
	}
}

func (schedule Schedule) IsSet() bool {
	return !schedule.Timepoint.IsZero()
}
