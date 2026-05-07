package cometbls

// Height is a block height for ibc-union.
// Mirrors the ibc-union spec where height is a plain uint64 (revision 0 only).
type Height = uint64

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
	return cs.FrozenHeight != 0
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

// Nanos returns the header timestamp as nanoseconds since Unix epoch.
// Callers must ensure TimeSeconds and TimeNanos are non-negative; verifyHeader enforces this.
func (lh LightHeader) Nanos() uint64 {
	return uint64(lh.TimeSeconds)*1_000_000_000 + uint64(lh.TimeNanos)
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
