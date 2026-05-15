package cometbls

import (
	"chain/runtime"
	"time"

	"gno.land/p/aib/ibc/types"
	cometblsp "gno.land/p/core/ibc/lightclients/cometbls"
	"gno.land/r/core/ibc/v1/core"
)

const ClientType core.ClientType = "cometbls"

type clientEntry struct {
	consensusStates map[cometblsp.Height]cometblsp.ConsensusState
	cs              cometblsp.ClientState
}

var entries = make(map[core.ClientId]*clientEntry)

var wasmdModuleStoreKey = []byte("wasm")

func nowNanos() uint64 { return uint64(time.Now().UnixNano()) }

func wasmContractStoreKey(contractAddress cometblsp.H256, key []byte) []byte {
	out := make([]byte, 0, 1+32+1+len(key))
	out = append(out, 0x03)
	out = append(out, contractAddress[:]...)
	out = append(out, 0x00)
	out = append(out, key...)
	return out
}

func mustBeCore() {
	if runtime.PreviousRealm().PkgPath() != "gno.land/r/core/ibc/v1/core" {
		panic("cometbls: core only")
	}
}

func getEntry(clientId core.ClientId) *clientEntry {
	e, ok := entries[clientId]
	if !ok {
		panic("cometbls: client not found: " + clientId.String())
	}
	return e
}

type Adapter struct{}

func (Adapter) CreateClient(_ realm, clientId core.ClientId, clientStateBytes, consensusStateBytes []byte) string {
	mustBeCore()

	cs, err := cometblsp.DecodeClientState(clientStateBytes)
	if err != nil {
		panic("cometbls: invalid client state: " + err.Error())
	}
	consState, err := cometblsp.DecodeConsensusState(consensusStateBytes)
	if err != nil {
		panic("cometbls: invalid consensus state: " + err.Error())
	}

	if err := cometblsp.ValidateInitialize(cs, consState); err != nil {
		panic("cometbls: initialize failed: " + err.Error())
	}
	e := &clientEntry{
		consensusStates: map[cometblsp.Height]cometblsp.ConsensusState{cs.LatestHeight: consState},
		cs:              cs,
	}
	entries[clientId] = e
	return cs.ChainID
}

func (Adapter) UpdateClient(_ realm, clientId core.ClientId, clientMessage []byte) core.ConsensusStateUpdate {
	mustBeCore()

	e := getEntry(clientId)

	header, err := cometblsp.DecodeHeader(clientMessage)
	if err != nil {
		panic("cometbls: invalid header: " + err.Error())
	}

	trusted, ok := e.consensusStates[header.TrustedHeight]
	if !ok {
		panic("cometbls: trusted consensus state not found")
	}
	if err := cometblsp.VerifyHeader(e.cs, trusted, header, nowNanos()); err != nil {
		panic("cometbls: " + err.Error())
	}

	newHeight := cometblsp.HeaderHeight(header)
	consState, ok := e.consensusStates[newHeight]
	if !ok {
		consState = cometblsp.ConsensusStateFromHeader(header.SignedHeader)
		e.consensusStates[newHeight] = consState
	}
	e.cs.LatestHeight = newHeight

	consStateBytes, err := cometblsp.EncodeConsensusState(consState)
	if err != nil {
		panic("cometbls: encode consensus state: " + err.Error())
	}
	clientStateBytes := cometblsp.EncodeClientState(e.cs)

	return core.ConsensusStateUpdate{
		Height:              core.Height(newHeight),
		ConsensusStateBytes: consStateBytes,
		ClientStateBytes:    clientStateBytes,
	}
}

func (Adapter) Misbehaviour(_ realm, clientId core.ClientId, clientMessage []byte) []byte {
	mustBeCore()

	e := getEntry(clientId)

	m, err := cometblsp.DecodeMisbehaviour(clientMessage)
	if err != nil {
		panic("cometbls: invalid misbehaviour: " + err.Error())
	}

	trustedA, ok := e.consensusStates[m.HeaderA.TrustedHeight]
	if !ok {
		panic("cometbls: trusted consensus state not found for header A")
	}
	trustedB, ok := e.consensusStates[m.HeaderB.TrustedHeight]
	if !ok {
		panic("cometbls: trusted consensus state not found for header B")
	}

	if err := cometblsp.VerifyMisbehaviour(e.cs, trustedA, trustedB, m, nowNanos()); err != nil {
		panic("cometbls: " + err.Error())
	}
	e.cs.FrozenHeight = cometblsp.FrozenHeight

	return cometblsp.EncodeClientState(e.cs)
}

func (Adapter) VerifyMembership(clientId core.ClientId, height core.Height, proof, key, value []byte) {
	e := getEntry(clientId)
	if status := adapterStatus(e); status != cometblsp.StatusActive {
		panic("cometbls: client is " + status)
	}
	proofs, err := cometblsp.DecodeProofs(proof)
	if err != nil {
		panic("cometbls: invalid membership proof: " + err.Error())
	}
	path := types.MerklePath{KeyPath: [][]byte{wasmdModuleStoreKey, wasmContractStoreKey(e.cs.ContractAddress, key)}}
	cs := e.consensusStates[cometblsp.Height(height)]
	if err := cometblsp.VerifyMembership(cs, proofs, path, value); err != nil {
		panic("cometbls: membership verification failed: " + err.Error())
	}
}

func (Adapter) VerifyNonMembership(clientId core.ClientId, height core.Height, proof, key []byte) {
	e := getEntry(clientId)
	if status := adapterStatus(e); status != cometblsp.StatusActive {
		panic("cometbls: client is " + status)
	}
	proofs, err := cometblsp.DecodeProofs(proof)
	if err != nil {
		panic("cometbls: invalid non-membership proof: " + err.Error())
	}
	path := types.MerklePath{KeyPath: [][]byte{wasmdModuleStoreKey, wasmContractStoreKey(e.cs.ContractAddress, key)}}
	cs := e.consensusStates[cometblsp.Height(height)]
	if err := cometblsp.VerifyNonMembership(cs, proofs, path); err != nil {
		panic("cometbls: non-membership verification failed: " + err.Error())
	}
}

func (Adapter) GetTimestamp(clientId core.ClientId, height core.Height) core.Timestamp {
	e := getEntry(clientId)
	cs, ok := e.consensusStates[cometblsp.Height(height)]
	if !ok {
		panic("cometbls: consensus state not found at height " + height.String())
	}
	return core.Timestamp(cs.Timestamp)
}

func (Adapter) GetLatestHeight(clientId core.ClientId) core.Height {
	return core.Height(getEntry(clientId).cs.LatestHeight)
}

func (Adapter) GetStatus(clientId core.ClientId) core.Status {
	e := getEntry(clientId)
	switch adapterStatus(e) {
	case cometblsp.StatusActive:
		return core.StatusActive
	case cometblsp.StatusFrozen:
		return core.StatusFrozen
	case cometblsp.StatusExpired:
		return core.StatusExpired
	default:
		return core.StatusUnknown
	}
}

func adapterStatus(e *clientEntry) string {
	latest := e.consensusStates[e.cs.LatestHeight]
	return cometblsp.Status(e.cs, latest, nowNanos())
}
