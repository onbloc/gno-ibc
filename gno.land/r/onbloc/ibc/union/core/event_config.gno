package core

// EventConfig is kept as a placeholder for future host event options.
type EventConfig struct{}

// DefaultEventConfig returns the default host event policy.
func DefaultEventConfig() EventConfig {
	return EventConfig{}
}

// GetEventConfig returns the current host event policy.
func GetEventConfig() EventConfig {
	return DefaultEventConfig()
}
