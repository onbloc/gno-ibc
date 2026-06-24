package main

import (
	"bytes"

	statelensp "gno.land/p/onbloc/ibc/union/lightclient/state_lens/ics23_mpt"

	"gno.land/r/onbloc/ibc/union/core"
	statelens "gno.land/r/onbloc/ibc/union/lightclients/statelensics23mpt"
)

func main(cur realm) {
	consensusState, err := statelensp.EncodeConsensusState(statelensp.ConsensusState{
		Timestamp:   1,
		StateRoot:   bytes.Repeat([]byte{0x04}, 32),
		StorageRoot: bytes.Repeat([]byte{0x05}, 32),
	})
	if err != nil {
		panic(err)
	}
	clientState, err := statelensp.EncodeClientState(statelensp.ClientState{
		L2ChainID:         "local-l2",
		L1ClientID:        1,
		L2ClientID:        1,
		L2LatestHeight:    1,
		TimestampOffset:   64,
		StateRootOffset:   0,
		StorageRootOffset: 32,
	})
	if err != nil {
		panic(err)
	}
	core.CreateClient(cross(cur), core.NewMsgCreateClient(statelens.ClientType, clientState, consensusState))
}
