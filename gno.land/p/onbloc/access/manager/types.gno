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

type DelayedValue struct {
	Effect      TimePoint
	ValueBefore Delay
	ValueAfter  Delay
}

func NewDelayedValue(delay Delay) DelayedValue {
	return DelayedValue{
		ValueAfter: delay,
	}
}

func (d DelayedValue) Get(now TimePoint) Delay {
	if d.Effect.IsZero() || !d.Effect.After(now) {
		return d.ValueAfter
	}

	return d.ValueBefore
}

func (d DelayedValue) GetFull(now TimePoint) (Delay, Delay, TimePoint) {
	if d.Effect.IsZero() || !d.Effect.After(now) {
		return d.ValueAfter, 0, 0
	}

	return d.ValueBefore, d.ValueAfter, d.Effect
}

func (d DelayedValue) WithUpdate(now TimePoint, newValue Delay, minSetback Delay) (DelayedValue, TimePoint) {
	value := d.Get(now)
	setback := minSetback
	if value > newValue && value-newValue > setback {
		setback = value - newValue
	}

	effect := now + TimePoint(setback)
	return DelayedValue{
		Effect:      effect,
		ValueBefore: value,
		ValueAfter:  newValue,
	}, effect
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

type FullAccess struct {
	Since        TimePoint
	CurrentDelay Delay
	PendingDelay Delay
	Effect       TimePoint
}

type RoleLabel struct {
	Role  RoleId
	Label string
	Found bool
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
