package main

import (
	"bytes"

	statelensp "gno.land/p/core/ibc/lightclients/statelensics23mpt"
	core "gno.land/r/core/ibc/v1/core"
	statelens "gno.land/r/core/ibc/v1/lightclients/statelensics23mpt"
)

func main() {
	consensusState, err := statelensp.EncodeConsensusState(statelensp.ConsensusState{
		Timestamp:   1,
		StateRoot:   bytes.Repeat([]byte{0x01}, 32),
		StorageRoot: bytes.Repeat([]byte{0x02}, 32),
	})
	if err != nil {
		panic(err)
	}
	id := core.CreateClient(cross, core.MsgCreateClient{
		ClientType: statelens.ClientType,
		ClientStateBytes: statelensp.EncodeClientState(statelensp.ClientState{
			L2ChainID:         "local-l2",
			L1ClientID:        1,
			L2ClientID:        1,
			L2LatestHeight:    1,
			TimestampOffset:   64,
			StateRootOffset:   0,
			StorageRootOffset: 32,
		}),
		ConsensusStateBytes: consensusState,
	})
	println("statelens_client_id", id.String())
}
