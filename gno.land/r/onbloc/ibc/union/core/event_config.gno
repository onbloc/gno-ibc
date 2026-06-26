package core

import "gno.land/r/onbloc/ibc/union/access"

const (
	defaultMaxEventAttrValueLen      = 1024
	defaultMaxPacketDataEventColumns = 50
)

var eventConfig = DefaultEventConfig()

// EventConfig controls host event attribute sizing policies.
type EventConfig struct {
	MaxEventAttrValueLen      int
	MaxPacketDataEventColumns int
}

// NewEventConfig constructs an EventConfig in the core realm.
func NewEventConfig(cur realm, maxEventAttrValueLen int, maxPacketDataEventColumns int) EventConfig {
	assertIsRlmCurrent(0, cur)
	assertIsProxyRealm(0, cur)

	return EventConfig{
		MaxEventAttrValueLen:      maxEventAttrValueLen,
		MaxPacketDataEventColumns: maxPacketDataEventColumns,
	}
}

// DefaultEventConfig returns the default host event attribute sizing policy.
func DefaultEventConfig() EventConfig {
	return EventConfig{
		MaxEventAttrValueLen:      defaultMaxEventAttrValueLen,
		MaxPacketDataEventColumns: defaultMaxPacketDataEventColumns,
	}
}

// GetEventConfig returns the current host event attribute sizing policy.
func GetEventConfig() EventConfig {
	return eventConfig
}

// SetEventConfig updates the host event attribute sizing policy.
func SetEventConfig(cur realm, config EventConfig) {
	access.AssertCanCall(0, cur, SelectorSetEventConfig)

	setEventConfig(config)
}

func setEventConfig(config EventConfig) {
	assertValidEventConfig(config)
	eventConfig = config
}

func assertValidEventConfig(config EventConfig) {
	if config.MaxEventAttrValueLen < 0 {
		panic("max event attr value len must be non-negative")
	}
	if config.MaxPacketDataEventColumns <= 0 {
		panic("max packet data event columns must be positive")
	}
}
