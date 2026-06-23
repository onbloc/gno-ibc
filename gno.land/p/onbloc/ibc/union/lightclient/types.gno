package lightclient

import "gno.land/p/onbloc/ibc/union/types"

type Status string

const (
	Active Status = "Active"

	Frozen Status = "Frozen"

	Expired Status = "Expired"

	Unknown Status = "Unknown"

	Unauthorized Status = "Unauthorized"
)

func (s Status) ToType() types.Status {
	switch s {
	case Active:
		return types.StatusActive
	case Expired:
		return types.StatusExpired
	case Frozen:
		return types.StatusFrozen
	default:
		return types.StatusUnknown
	}
}

type Interface interface {
	VerifyMembership(height uint64, key []byte, proof []byte, value []byte) error

	VerifyNonMembership(height uint64, key []byte, proof []byte) error

	GetTimestamp() types.Timestamp

	// GetTimestampAtHeight returns the consensus timestamp recorded at a specific
	// height. Packet timeout verification needs the counterparty timestamp at the
	// proof height, not just the latest. Returns an error when no consensus state
	// exists at the height.
	GetTimestampAtHeight(height uint64) (types.Timestamp, error)

	GetLatestHeight() uint64

	GetCounterpartyChainID() string

	Status() Status

	VerifyHeader(caller address, header []byte, relayer address) (types.StateUpdate, error)

	VerifyCreation(caller address, relayer address) (types.ClientCreationResult, error)

	Misbehaviour(caller address, misbehaviour []byte, relayer address) ([]byte, error)
}
