package cometbls

import (
	"errors"

	abienc "gno.land/p/core/encoding/abi"
)

// Ethereum ABI wire format for Union CometBLS ClientState.
//
// Encoding rules (Solidity params tuple form):
//   - ClientState: 6 words x 32 bytes = 192 bytes (all static)

// [0] chain_id bytes32  [1-4] uint64 x 4  [5] contract_address bytes32
var clientStateSchema = abienc.Schema{Fields: []abienc.Field{
	{Type: abienc.TypeBytes32},
	{Type: abienc.TypeUint64},
	{Type: abienc.TypeUint64},
	{Type: abienc.TypeUint64},
	{Type: abienc.TypeUint64},
	{Type: abienc.TypeBytes32},
}}

func EncodeClientState(cs ClientState) []byte {
	var chainID [32]byte
	n := len(cs.ChainID)
	if n > 32 {
		n = 32
	}
	copy(chainID[:], cs.ChainID[:n])
	contractAddress := [32]byte(cs.ContractAddress)
	buf, _ := abienc.Encode(clientStateSchema, []any{
		chainID,
		cs.TrustingPeriod,
		cs.MaxClockDrift,
		cs.FrozenHeight,
		cs.LatestHeight,
		contractAddress,
	})
	return buf
}

func DecodeClientState(buf []byte) (ClientState, error) {
	vals, err := abienc.Decode(clientStateSchema, buf)
	if err != nil {
		return ClientState{}, errors.New("cometbls: " + err.Error())
	}
	var cs ClientState
	chainID := vals[0].([32]byte)
	end := 32
	for end > 0 && chainID[end-1] == 0 {
		end--
	}
	cs.ChainID = string(chainID[:end])
	cs.TrustingPeriod = vals[1].(uint64)
	cs.MaxClockDrift = vals[2].(uint64)
	cs.FrozenHeight = vals[3].(uint64)
	cs.LatestHeight = vals[4].(uint64)
	cs.ContractAddress = H256(vals[5].([32]byte))
	return cs, nil
}
