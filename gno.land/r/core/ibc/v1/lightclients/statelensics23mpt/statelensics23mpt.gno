package statelensics23mpt

import (
	"crypto/keccak256"
	"encoding/binary"
	"errors"

	"gno.land/p/core/ethereum/storage"
	statelensp "gno.land/p/core/ibc/lightclients/statelensics23mpt"
	"gno.land/r/core/ibc/v1/core"
)

const ClientType core.ClientType = "08-state-lens-ics23-mpt"

var (
	ErrConsensusStateTooShort = errors.New("statelensics23mpt: l2 consensus state too short")
	ErrInvalidCommitmentKey   = errors.New("statelensics23mpt: invalid commitment key")
	ErrInvalidCommitmentValue = errors.New("statelensics23mpt: invalid commitment value")
	ErrStoredValueMismatch    = errors.New("statelensics23mpt: stored value mismatch")
)

type clientEntry struct {
	consensusStates map[statelensp.Height]statelensp.ConsensusState
	cs              statelensp.ClientState
}

var entries = make(map[core.ClientId]*clientEntry)

func getEntry(clientId core.ClientId) *clientEntry {
	e, ok := entries[clientId]
	if !ok {
		panic("statelensics23mpt: client not found: " + clientId.String())
	}
	return e
}

type Adapter struct{}

func (Adapter) CreateClient(_ realm, clientId core.ClientId, clientStateBytes, consensusStateBytes []byte) string {
	cs, err := statelensp.DecodeClientState(clientStateBytes)
	if err != nil {
		panic("statelensics23mpt: invalid client state: " + err.Error())
	}
	consState, err := statelensp.DecodeConsensusState(consensusStateBytes)
	if err != nil {
		panic("statelensics23mpt: invalid consensus state: " + err.Error())
	}

	e := &clientEntry{
		consensusStates: make(map[statelensp.Height]statelensp.ConsensusState),
		cs:              cs,
	}
	e.consensusStates[cs.L2LatestHeight] = consState
	entries[clientId] = e
	return cs.L2ChainID
}

func (Adapter) UpdateClient(_ realm, clientId core.ClientId, clientMessage []byte) core.ConsensusStateUpdate {
	e := getEntry(clientId)

	header, err := statelensp.DecodeHeader(clientMessage)
	if err != nil {
		panic("statelensics23mpt: invalid header: " + err.Error())
	}

	consensusPath := core.ConsensusStatePath(core.ClientId(e.cs.L2ClientID), core.Height(header.L2Height))
	consensusHash := keccak256.Sum256(header.L2ConsensusState)
	core.VerifyClientMembership(
		cross,
		core.ClientId(e.cs.L1ClientID),
		core.Height(header.L1Height),
		header.L2ConsensusStateProof,
		consensusPath[:],
		consensusHash[:],
	)

	consState, err := extractConsensusState(header.L2ConsensusState, e.cs)
	if err != nil {
		panic(err)
	}

	e.consensusStates[header.L2Height] = consState
	if e.cs.L2LatestHeight < header.L2Height {
		e.cs.L2LatestHeight = header.L2Height
	}

	consStateBytes, err := statelensp.EncodeConsensusState(consState)
	if err != nil {
		panic("statelensics23mpt: encode consensus state: " + err.Error())
	}

	return core.ConsensusStateUpdate{
		Height:              core.Height(header.L2Height),
		ConsensusStateBytes: consStateBytes,
		ClientStateBytes:    statelensp.EncodeClientState(e.cs),
	}
}

func (Adapter) VerifyMembership(clientId core.ClientId, height core.Height, proof, key, value []byte) {
	a := Adapter{}
	status := a.GetStatus(clientId)
	if status != core.StatusActive {
		panic("statelensics23mpt: client is not active")
	}

	e := getEntry(clientId)
	consState, ok := e.consensusStates[statelensp.Height(height)]
	if !ok {
		panic("statelensics23mpt: consensus state not found at height " + height.String())
	}
	storageProof, err := storage.DecodeProof(proof)
	if err != nil {
		panic("statelensics23mpt: invalid storage proof: " + err.Error())
	}
	if err := verifyCommitmentKey(key, storageProof.Key); err != nil {
		panic(err)
	}
	if len(value) != 32 {
		panic(ErrInvalidCommitmentValue)
	}
	if !equalBytes(storageProof.Value, value) {
		panic(ErrStoredValueMismatch)
	}
	if err := storage.VerifyProof(consState.StorageRoot, storage.Proof{
		Key:   storageProof.Key,
		Value: storageProof.Value,
		Proof: storageProof.Proof,
	}); err != nil {
		panic("statelensics23mpt: storage membership verification failed: " + err.Error())
	}
}

func (Adapter) VerifyNonMembership(clientId core.ClientId, height core.Height, proof, key []byte) {
	a := Adapter{}
	status := a.GetStatus(clientId)
	if status != core.StatusActive {
		panic("statelensics23mpt: client is not active")
	}

	e := getEntry(clientId)
	consState, ok := e.consensusStates[statelensp.Height(height)]
	if !ok {
		panic("statelensics23mpt: consensus state not found at height " + height.String())
	}
	storageProof, err := storage.DecodeProof(proof)
	if err != nil {
		panic("statelensics23mpt: invalid storage proof: " + err.Error())
	}
	if err := verifyCommitmentKey(key, storageProof.Key); err != nil {
		panic(err)
	}
	if err := storage.VerifyAbsence(consState.StorageRoot, storage.Proof{
		Key:   storageProof.Key,
		Proof: storageProof.Proof,
	}); err != nil {
		panic("statelensics23mpt: storage non-membership verification failed: " + err.Error())
	}
}

func (Adapter) GetTimestamp(clientId core.ClientId, height core.Height) core.Timestamp {
	cs, ok := getEntry(clientId).consensusStates[statelensp.Height(height)]
	if !ok {
		panic("statelensics23mpt: consensus state not found at height " + height.String())
	}
	return core.Timestamp(cs.Timestamp)
}

func (Adapter) GetLatestHeight(clientId core.ClientId) core.Height {
	return core.Height(getEntry(clientId).cs.L2LatestHeight)
}

func (Adapter) GetStatus(clientId core.ClientId) core.Status {
	return core.GetClientStatus(core.ClientId(getEntry(clientId).cs.L1ClientID))
}

func extractConsensusState(data []byte, cs statelensp.ClientState) (statelensp.ConsensusState, error) {
	timestamp, err := extractUint64(data, int(cs.TimestampOffset))
	if err != nil {
		return statelensp.ConsensusState{}, err
	}
	stateRoot, err := extractBytes32(data, int(cs.StateRootOffset))
	if err != nil {
		return statelensp.ConsensusState{}, err
	}
	storageRoot, err := extractBytes32(data, int(cs.StorageRootOffset))
	if err != nil {
		return statelensp.ConsensusState{}, err
	}
	return statelensp.ConsensusState{
		Timestamp:   timestamp,
		StateRoot:   stateRoot,
		StorageRoot: storageRoot,
	}, nil
}

func extractUint64(data []byte, offset int) (uint64, error) {
	if offset < 0 || offset+8 > len(data) {
		return 0, ErrConsensusStateTooShort
	}
	return binary.BigEndian.Uint64(data[offset : offset+8]), nil
}

func extractBytes32(data []byte, offset int) ([]byte, error) {
	if offset < 0 || offset+32 > len(data) {
		return nil, ErrConsensusStateTooShort
	}
	out := make([]byte, 32)
	copy(out, data[offset:offset+32])
	return out, nil
}

func verifyCommitmentKey(path []byte, proofKey []byte) error {
	expected, err := storage.IBCCommitmentKey(path)
	if err != nil {
		return ErrInvalidCommitmentKey
	}
	if !equalBytes(expected[:], proofKey) {
		return ErrInvalidCommitmentKey
	}
	return nil
}

func equalBytes(a, b []byte) bool {
	if len(a) != len(b) {
		return false
	}
	for i := range a {
		if a[i] != b[i] {
			return false
		}
	}
	return true
}
