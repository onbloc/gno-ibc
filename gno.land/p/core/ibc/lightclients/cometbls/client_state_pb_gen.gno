package cometbls

import (
	"errors"

	abienc "gno.land/p/core/encoding/abi"
)

var clientStateSchema = abienc.Schema{Fields: []abienc.Field{
	{Type: abienc.TypeBytes32},
	{Type: abienc.TypeUint64},
	{Type: abienc.TypeUint64},
	{Type: abienc.TypeUint64},
	{Type: abienc.TypeUint64},
	{Type: abienc.TypeBytes32},
}}

func EncodeClientState(m ClientState) ([]byte, error) {
	var chainIdWord [32]byte
	chainBytes := []byte(m.ChainID)
	if len(chainBytes) > 31 {
		chainBytes = chainBytes[:31]
	}
	copy(chainIdWord[:], chainBytes)

	return abienc.Encode(clientStateSchema, []any{
		chainIdWord,
		m.TrustingPeriod,
		m.MaxClockDrift,
		uint64(m.FrozenHeight),
		uint64(m.LatestHeight),
		[32]byte(m.ContractAddress),
	})
}

func DecodeClientState(buf []byte) (ClientState, error) {
	vals, err := abienc.Decode(clientStateSchema, buf)
	if err != nil {
		return ClientState{}, errors.New("cometbls: " + err.Error())
	}
	var cs ClientState
	chainIdWord := vals[0].([32]byte)
	cs.ChainID = trimNullBytes(chainIdWord)
	cs.TrustingPeriod = vals[1].(uint64)
	cs.MaxClockDrift = vals[2].(uint64)
	cs.FrozenHeight = vals[3].(uint64)
	cs.LatestHeight = vals[4].(uint64)
	cs.ContractAddress = H256(vals[5].([32]byte))
	return cs, nil
}

func trimNullBytes(b [32]byte) string {
	end := 32
	for end > 0 && b[end-1] == 0 {
		end--
	}
	return string(b[:end])
}
