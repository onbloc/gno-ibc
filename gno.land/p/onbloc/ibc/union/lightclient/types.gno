package lightclient

import "gno.land/p/onbloc/ibc/union/types"

type Status = string

const (
	Active Status = "Active"

	Frozen Status = "Frozen"

	Expired Status = "Expired"

	Unknown Status = "Unknown"

	Unauthorized Status = "Unauthorized"
)

type Interface interface {
	VerifyMembership(height uint64, key []byte, proof []byte, value []byte) error

	VerifyNonMembership(height uint64, key []byte, proof []byte) error

	GetTimestamp() types.Timestamp

	GetLatestHeight() uint64

	GetCounterpartyChainID() string

	Status() Status

	VerifyHeader(caller address, header []byte, relayer address) (types.StateUpdate, error)

	VerifyCreation(caller address, relayer address) (types.ClientCreationResult, error)

	Misbehaviour(caller address, misbehaviour []byte, relayer address) (types.ClientState, error)
}
