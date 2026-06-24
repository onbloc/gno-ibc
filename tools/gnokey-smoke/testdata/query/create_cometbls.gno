package main

import (
	"encoding/hex"

	cometblsp "gno.land/p/onbloc/ibc/union/lightclient/cometbls"
	"gno.land/p/onbloc/ibc/union/types"

	"gno.land/r/onbloc/ibc/union/core"
	"gno.land/r/onbloc/ibc/union/lightclients/cometbls"
)

func main(cur realm) {
	contractBytes, err := hex.DecodeString("0cf2ffe8f45a20514018173d3007644817a9767dc0fbdb246696fd9c261ce3bc")
	if err != nil {
		panic(err)
	}
	var contract types.H256
	copy(contract[:], contractBytes)

	root, err := hex.DecodeString("ee7e3e58f98ac95d63ce93b270981df3ee54ca367f8d521ed1f444717595cd36")
	if err != nil {
		panic(err)
	}
	nextValidatorsHash, err := hex.DecodeString("20ddfe7a0f75c65d876316091eccd494a54a2bb324c872015f73e528d53cb9c4")
	if err != nil {
		panic(err)
	}

	clientState, err := cometblsp.EncodeClientState(&cometblsp.ClientState{
		ChainID:         "union-devnet-1337",
		TrustingPeriod:  1 << 62,
		UnbondingPeriod: 1 << 63,
		MaxClockDrift:   10000000000,
		FrozenHeight:    types.Height{},
		LatestHeight:    types.NewHeight(3405691581),
		ContractAddress: contract,
	})
	if err != nil {
		panic(err)
	}
	consensusState, err := cometblsp.EncodeConsensusState(&cometblsp.ConsensusState{
		Timestamp:          1732204251000000000,
		Root:               cometblsp.MerkleRoot{Hash: root},
		NextValidatorsHash: nextValidatorsHash,
	})
	if err != nil {
		panic(err)
	}

	core.CreateClient(cross(cur), core.NewMsgCreateClient(cometbls.ClientType, clientState, consensusState))
}
