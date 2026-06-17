package cometbls

import (
	"time"

	"gno.land/p/nt/ufmt/v0"
	"gno.land/p/onbloc/ibc/union/types"
)

type Header struct {
	SignedHeader       *LightHeader
	TrustedHeight      *types.Height
	ZeroKnowledgeProof []byte
}

func NewHeader(
	signedHeader *LightHeader,
	trustedHeight *types.Height,
	zeroKnowledgeProof []byte,
) *Header {
	return &Header{
		SignedHeader:       signedHeader,
		TrustedHeight:      trustedHeight,
		ZeroKnowledgeProof: zeroKnowledgeProof,
	}
}

func (Header) ClientType() string {
	return ClientType
}

func (h *Header) ConsensusState() *ConsensusState {
	return &ConsensusState{
		Timestamp:          uint64(h.GetTime().UnixNano()),
		Root:               MerkleRoot{Hash: h.SignedHeader.AppHash},
		NextValidatorsHash: h.SignedHeader.NextValidatorsHash,
	}
}

// GetHeight returns the height of the signed (untrusted) header. CometBLS
// carries a single revision, so it shares the trusted height's revision number.
func (h *Header) GetHeight() types.Height {
	return types.NewHeightWithRevision(h.TrustedHeight.RevisionNumber, uint64(h.SignedHeader.Height))
}

func (h *Header) GetTime() time.Time {
	return h.SignedHeader.Time
}

// ValidateBasic calls the SignedHeader ValidateBasic function and checks
// that validatorsets are not nil.
// NOTE: TrustedHeight and TrustedValidators may be empty when creating client
// with MsgCreateClient
func (h *Header) ValidateBasic() error {
	if h.SignedHeader == nil {
		return makeError(ErrInvalidHeader, "signed header cannot be nil")
	}

	// TrustedHeight is less than Header for updates and misbehaviour
	if h.TrustedHeight.GTE(h.GetHeight()) {
		return makeError(
			ErrInvalidHeaderHeight,
			ufmt.Sprintf("TrustedHeight %d must be less than header height %d", h.TrustedHeight, h.GetHeight()),
		)
	}

	return nil
}

type LightHeader struct {
	Height             int64
	Time               time.Time
	ValidatorsHash     []byte
	NextValidatorsHash []byte
	AppHash            []byte
}

func NewLightHeader(height int64, time time.Time, validatorsHash, nextValidatorsHash, appHash []byte) *LightHeader {
	return &LightHeader{Height: height, Time: time, ValidatorsHash: validatorsHash, NextValidatorsHash: nextValidatorsHash, AppHash: appHash}
}
