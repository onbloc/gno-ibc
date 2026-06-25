package manager

import "strconv"

type Selector string

// NewSelector returns a selector from its string representation.
func NewSelector(selector string) Selector {
	return Selector(selector)
}

type Delay uint32

// NewDelay returns a delay in seconds.
// OpenZeppelin reference:
// https://github.com/OpenZeppelin/openzeppelin-contracts/blob/5fd1781b1454fd1ef8e722282f86f9293cacf256/contracts/utils/types/Time.sol#L69-L84
func NewDelay(delay uint32) Delay {
	return Delay(delay)
}

// Uint32 returns d as a uint32.
func (d Delay) Uint32() uint32 {
	return uint32(d)
}

// String returns d as a base-10 string.
func (d Delay) String() string {
	return strconv.FormatUint(uint64(d), 10)
}

type DelayedValue struct {
	Effect      TimePoint
	ValueBefore Delay
	ValueAfter  Delay
}

// NewDelayedValue returns a delayed value whose current value is delay.
// OpenZeppelin reference:
// https://github.com/OpenZeppelin/openzeppelin-contracts/blob/5fd1781b1454fd1ef8e722282f86f9293cacf256/contracts/utils/types/Time.sol#L61-L67
func NewDelayedValue(delay Delay) DelayedValue {
	return DelayedValue{
		ValueAfter: delay,
	}
}

// Get returns the value effective at now.
// OpenZeppelin reference:
// https://github.com/OpenZeppelin/openzeppelin-contracts/blob/5fd1781b1454fd1ef8e722282f86f9293cacf256/contracts/utils/types/Time.sol#L93-L100
func (d DelayedValue) Get(now TimePoint) Delay {
	if d.Effect.IsZero() || !d.Effect.After(now) {
		return d.ValueAfter
	}

	return d.ValueBefore
}

// GetFull returns the current value, pending value, and pending effect time at
// now.
// OpenZeppelin reference:
// https://github.com/OpenZeppelin/openzeppelin-contracts/blob/5fd1781b1454fd1ef8e722282f86f9293cacf256/contracts/utils/types/Time.sol#L86-L91
func (d DelayedValue) GetFull(now TimePoint) (Delay, Delay, TimePoint) {
	if d.Effect.IsZero() || !d.Effect.After(now) {
		return d.ValueAfter, 0, 0
	}

	return d.ValueBefore, d.ValueAfter, d.Effect
}

// WithUpdate returns a delayed value update and the timepoint at which it takes
// effect.
// OpenZeppelin reference:
// https://github.com/OpenZeppelin/openzeppelin-contracts/blob/5fd1781b1454fd1ef8e722282f86f9293cacf256/contracts/utils/types/Time.sol#L103-L113
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

// NewCanCallResult returns a can-call authorization result.
// OpenZeppelin reference:
// https://github.com/OpenZeppelin/openzeppelin-contracts/blob/5fd1781b1454fd1ef8e722282f86f9293cacf256/contracts/access/manager/AccessManager.sol#L140-L156
func NewCanCallResult(immediate bool, authorized bool, delay Delay) CanCallResult {
	return CanCallResult{
		Immediate:  immediate,
		Delay:      delay,
		Authorized: authorized,
	}
}

type HasRoleResult struct {
	IsMember       bool
	ExecutionDelay Delay
}

// NewHasRoleResult returns a role membership query result.
// OpenZeppelin reference:
// https://github.com/OpenZeppelin/openzeppelin-contracts/blob/5fd1781b1454fd1ef8e722282f86f9293cacf256/contracts/access/manager/AccessManager.sol#L211-L220
func NewHasRoleResult(isMember bool, executionDelay Delay) HasRoleResult {
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

// String returns id as a string.
func (id OperationId) String() string {
	return string(id)
}

type Nonce uint64

// Uint64 returns nonce as a uint64.
func (nonce Nonce) Uint64() uint64 {
	return uint64(nonce)
}

// String returns nonce as a base-10 string.
func (nonce Nonce) String() string {
	return strconv.FormatUint(uint64(nonce), 10)
}

type Schedule struct {
	Timepoint TimePoint
	Nonce     Nonce
}

// NewSchedule returns a scheduled operation timepoint and nonce pair.
// OpenZeppelin reference:
// https://github.com/OpenZeppelin/openzeppelin-contracts/blob/5fd1781b1454fd1ef8e722282f86f9293cacf256/contracts/access/manager/AccessManager.sol#L93-L99
func NewSchedule(timepoint TimePoint, nonce Nonce) Schedule {
	return Schedule{
		Timepoint: timepoint,
		Nonce:     nonce,
	}
}

// IsSet reports whether schedule has a non-zero timepoint.
func (schedule Schedule) IsSet() bool {
	return !schedule.Timepoint.IsZero()
}
