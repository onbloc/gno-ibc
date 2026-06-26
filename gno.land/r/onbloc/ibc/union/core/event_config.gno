package core

import "gno.land/r/onbloc/ibc/union/access"

const (
	defaultMaxEventAttrValueLen      = 1024
	defaultMaxPacketDataEventColumns = 50
)

var eventConfig = DefaultEventConfig()

// EventConfig controls host event attribute splitting and sizing.
type EventConfig struct {
	// SplitEventAttrs controls whether large event attributes are emitted as
	// indexed columns and whether split-dependent size checks are enforced.
	SplitEventAttrs bool

	// MaxEventAttrValueLen is the maximum value length of each split event
	// attribute column.
	MaxEventAttrValueLen uint

	// MaxPacketDataEventColumns is the maximum number of packet_data columns
	// allowed when packet_data size checks are enforced.
	MaxPacketDataEventColumns uint
}

// NewEventConfig constructs an EventConfig value. SetEventConfig validates the
// value before storing it.
func NewEventConfig(splitEventAttrs bool, maxEventAttrValueLen uint, maxPacketDataEventColumns uint) EventConfig {
	return EventConfig{
		SplitEventAttrs:           splitEventAttrs,
		MaxEventAttrValueLen:      maxEventAttrValueLen,
		MaxPacketDataEventColumns: maxPacketDataEventColumns,
	}
}

// DefaultEventConfig returns the default host event attribute policy.
func DefaultEventConfig() EventConfig {
	return EventConfig{
		SplitEventAttrs:           true,
		MaxEventAttrValueLen:      defaultMaxEventAttrValueLen,
		MaxPacketDataEventColumns: defaultMaxPacketDataEventColumns,
	}
}

// GetEventConfig returns the current host event attribute policy.
func GetEventConfig() EventConfig {
	return eventConfig
}

// SetEventConfig updates the host event attribute policy.
// The caller must be authorized for SelectorSetEventConfig.
func SetEventConfig(cur realm, config EventConfig) {
	access.AssertCanCall(0, cur, SelectorSetEventConfig)

	setEventConfig(config)
}

func setEventConfig(config EventConfig) {
	assertValidEventConfig(config)
	eventConfig = config
}

func assertValidEventConfig(config EventConfig) {
	if config.MaxEventAttrValueLen == 0 {
		panic("max event attr value len must be positive")
	}
	if config.MaxPacketDataEventColumns == 0 {
		panic("max packet data event columns must be positive")
	}
}
