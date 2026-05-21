package main

import (
	"encoding/hex"

	core "gno.land/r/core/ibc/v1/core"
	cometbls "gno.land/r/core/ibc/v1/lightclients/cometbls"
)

func main() {
	clientState, err := hex.DecodeString("756e696f6e2d6465766e65742d313333370000000000000000000000000000000000000000000000000000000000000000000000000000000460623fc85e000000000000000000000000000000000000000000000000000000000002540be400000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000cafebabd0cf2ffe8f45a20514018173d3007644817a9767dc0fbdb246696fd9c261ce3bc")
	if err != nil {
		panic(err)
	}
	consensusState, err := hex.DecodeString("000000000000000000000000000000000000000000000000180a0696b346ce00ee7e3e58f98ac95d63ce93b270981df3ee54ca367f8d521ed1f444717595cd3620ddfe7a0f75c65d876316091eccd494a54a2bb324c872015f73e528d53cb9c4")
	if err != nil {
		panic(err)
	}
	id := core.CreateClient(cross, core.MsgCreateClient{
		ClientType:          cometbls.ClientType,
		ClientStateBytes:    clientState,
		ConsensusStateBytes: consensusState,
	})
	println("cometbls_client_id", id.String())
}
