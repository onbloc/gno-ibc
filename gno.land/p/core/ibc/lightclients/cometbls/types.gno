package cometbls

// Height represents an IBC block height with a revision number.
// Mirrors ibc.core.client.v1.Height.
type Height struct {
	RevisionNumber uint64
	RevisionHeight uint64
}

func (h Height) IsZero() bool {
	return h.RevisionNumber == 0 && h.RevisionHeight == 0
}

func (h Height) GT(other Height) bool {
	if h.RevisionNumber != other.RevisionNumber {
		return h.RevisionNumber > other.RevisionNumber
	}
	return h.RevisionHeight > other.RevisionHeight
}

// MerkleRoot is the commitment root (app hash).
// Mirrors ibc.core.commitment.v1.MerkleRoot.
type MerkleRoot struct {
	Hash []byte
}

// ClientState tracks the state of the CometBLS light client.
// Mirrors union.ibc.lightclients.cometbls.v1.ClientState.
type ClientState struct {
	ChainID        string
	TrustingPeriod uint64 // nanoseconds
	MaxClockDrift  uint64 // nanoseconds
	FrozenHeight   Height
	LatestHeight   Height
}

func (cs ClientState) IsFrozen() bool {
	return !cs.FrozenHeight.IsZero()
}

// ConsensusState holds the verified state at a given height.
// Mirrors union.ibc.lightclients.cometbls.v1.ConsensusState.
type ConsensusState struct {
	Timestamp          uint64 // nanoseconds since Unix epoch
	Root               MerkleRoot
	NextValidatorsHash []byte
}

// LightHeader is the minimal block header committed to by a ZK proof.
// Mirrors union.ibc.lightclients.cometbls.v1.LightHeader.
type LightHeader struct {
	Height             int64
	TimeSeconds        int64
	TimeNanos          int32
	ValidatorsHash     []byte
	NextValidatorsHash []byte
	AppHash            []byte
}

// Header is the ClientMessage used to update the CometBLS light client.
// Mirrors union.ibc.lightclients.cometbls.v1.Header.
type Header struct {
	SignedHeader       LightHeader
	TrustedHeight      Height
	ZeroKnowledgeProof []byte
}

// Misbehaviour contains two conflicting headers for the same height.
// Mirrors union.ibc.lightclients.cometbls.v1.Misbehaviour.
type Misbehaviour struct {
	HeaderA Header
	HeaderB Header
}
