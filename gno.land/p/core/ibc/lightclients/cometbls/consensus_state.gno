package cometbls

import (
	"errors"

	abienc "gno.land/p/core/encoding/abi"
)

// Ethereum ABI wire format for Union CometBLS ConsensusState.
//
// Encoding rules (Solidity params tuple form):
//   - ConsensusState: 3 words x 32 bytes = 96 bytes (all static)

// [0] timestamp uint64  [1-2] bytes32 x 2
var consensusStateSchema = abienc.Schema{Fields: []abienc.Field{
	{Type: abienc.TypeUint64},
	{Type: abienc.TypeBytes32},
	{Type: abienc.TypeBytes32},
}}

// EncodeConsensusState ABI-encodes a ConsensusState (96 bytes).
// Root.Hash must be exactly 32 bytes.
func EncodeConsensusState(cs ConsensusState) ([]byte, error) {
	appHash, err := toBytes32(cs.Root.Hash, "root hash")
	if err != nil {
		return nil, err
	}
	return abienc.Encode(consensusStateSchema, []any{cs.Timestamp, appHash, [32]byte(cs.NextValidatorsHash)})
}

func DecodeConsensusState(buf []byte) (ConsensusState, error) {
	vals, err := abienc.Decode(consensusStateSchema, buf)
	if err != nil {
		return ConsensusState{}, errors.New("cometbls: " + err.Error())
	}
	var cs ConsensusState
	cs.Timestamp = vals[0].(uint64)
	ah := vals[1].([32]byte)
	cs.Root.Hash = ah[:]
	nvh := vals[2].([32]byte)
	cs.NextValidatorsHash = H256(nvh)
	return cs, nil
}

func toBytes32(b []byte, name string) ([32]byte, error) {
	if len(b) != 32 {
		return [32]byte{}, errors.New("cometbls: " + name + " must be 32 bytes")
	}
	var out [32]byte
	copy(out[:], b)
	return out, nil
}
