package cometbls

import (
	"gno.land/r/union/core"
)

// var coreAddress address;

func Register(_ realm) {
	core.RegisterClient(cross, "cometbls", Cometbls{})
}

type Cometbls struct{}

func (c Cometbls) CreateClient(clientId core.ClientId, clientStateBytes, consensusStateBytes []byte) string {
	// snip
	return ""
}

func (c Cometbls) UpdateClient(clientId core.ClientId, clientMessage []byte) core.ConsensusStateUpdate {
	// snip
	return core.ConsensusStateUpdate{}
}

func (c Cometbls) Misbehaviour(clientId core.ClientId, clientMessage []byte) []byte {
	// snip
	return []byte{}
}

func (c Cometbls) VerifyMembership(clientId core.ClientId, height core.Height, proof []byte, key []byte, value []byte) {
	// snip
}

func (c Cometbls) VerifyNonMembership(clientId core.ClientId, height core.Height, proof []byte, key []byte) {
	// snip
}

func (c Cometbls) GetTimestamp(client_id core.ClientId, height core.Height) core.Timestamp {
	// snip
	return core.Timestamp(0)
}

func (c Cometbls) GetLatestHeight(client_id core.ClientId) core.Height {
	// snip
	return core.Height(0)
}

func (c Cometbls) GetStatus(client_id core.ClientId) core.Status {
	// snip
	return core.StatusUnknown
}

// STATE

type State struct {
	clientStates    map[core.ClientId][]byte
	consensusStates map[core.ClientId]map[core.Height][]byte
}

func (s State) saveClientState(clientId core.ClientId, clientStateBytes []byte) {
	s.clientStates[clientId] = clientStateBytes
}

func (s State) saveConsensusState(clientId core.ClientId, height core.Height, consensusStateBytes []byte) {
	s.consensusStates[clientId][height] = consensusStateBytes
}

// func Render(_ string) string {
// 	var s = "registered clients: {";

//     for key := range clientRegistry {
//         s += " "
//         s += key
//     }

//     s += "}"

//     return s
// }
