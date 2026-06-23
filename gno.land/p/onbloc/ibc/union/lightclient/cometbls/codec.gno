package cometbls

import (
	"errors"

	abienc "gno.land/p/onbloc/encoding/abi"
	"gno.land/p/onbloc/ibc/union/types"
)

// Wire formats for the cometbls client and consensus state.
//
// ibc-union heights carry a single revision (revision 0), so only the revision
// height is encoded; decoding rebuilds the Height with types.NewHeight.

var clientStateSchema = abienc.Schema{Fields: []abienc.Field{
	{Type: abienc.TypeString},  // ChainID
	{Type: abienc.TypeUint64},  // TrustingPeriod
	{Type: abienc.TypeUint64},  // UnbondingPeriod
	{Type: abienc.TypeUint64},  // MaxClockDrift
	{Type: abienc.TypeUint64},  // FrozenHeight (revision height)
	{Type: abienc.TypeUint64},  // LatestHeight (revision height)
	{Type: abienc.TypeBytes32}, // ContractAddress
}}

var consensusStateSchema = abienc.Schema{Fields: []abienc.Field{
	{Type: abienc.TypeUint64},  // Timestamp
	{Type: abienc.TypeBytes32}, // Root (app hash)
	{Type: abienc.TypeBytes32}, // NextValidatorsHash
}}

func EncodeClientState(cs *ClientState) ([]byte, error) {
	if cs == nil {
		return nil, errors.New("cometbls: nil client state")
	}
	return abienc.Encode(clientStateSchema, []any{
		cs.ChainID,
		cs.TrustingPeriod,
		cs.UnbondingPeriod,
		cs.MaxClockDrift,
		cs.FrozenHeight.RevisionHeight,
		cs.GetLatestRevisionHeight(),
		[32]byte(cs.ContractAddress),
	})
}

func DecodeClientState(buf []byte) (*ClientState, error) {
	vals, err := abienc.Decode(clientStateSchema, buf)
	if err != nil {
		return nil, errors.New("cometbls: " + err.Error())
	}
	contractAddress := vals[6].([32]byte)
	return &ClientState{
		ChainID:         vals[0].(string),
		TrustingPeriod:  vals[1].(uint64),
		UnbondingPeriod: vals[2].(uint64),
		MaxClockDrift:   vals[3].(uint64),
		FrozenHeight:    types.NewHeight(vals[4].(uint64)),
		LatestHeight:    types.NewHeight(vals[5].(uint64)),
		ContractAddress: H256(contractAddress),
	}, nil
}

func EncodeConsensusState(cs *ConsensusState) ([]byte, error) {
	if cs == nil {
		return nil, errors.New("cometbls: nil consensus state")
	}
	root, err := toBytes32(cs.Root.Hash, "root hash")
	if err != nil {
		return nil, err
	}
	nextValidatorsHash, err := toBytes32(cs.NextValidatorsHash, "next validators hash")
	if err != nil {
		return nil, err
	}
	return abienc.Encode(consensusStateSchema, []any{
		cs.Timestamp,
		root,
		nextValidatorsHash,
	})
}

func DecodeConsensusState(buf []byte) (*ConsensusState, error) {
	vals, err := abienc.Decode(consensusStateSchema, buf)
	if err != nil {
		return nil, errors.New("cometbls: " + err.Error())
	}
	root := vals[1].([32]byte)
	nextValidatorsHash := vals[2].([32]byte)
	return &ConsensusState{
		Timestamp:          vals[0].(uint64),
		Root:               MerkleRoot{Hash: bytes32Slice(root)},
		NextValidatorsHash: bytes32Slice(nextValidatorsHash),
	}, nil
}

func bytes32Slice(b [32]byte) []byte {
	out := make([]byte, 32)
	copy(out, b[:])
	return out
}
