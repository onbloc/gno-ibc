package statelensics23mpt

import (
	"bytes"
	"crypto/keccak256"
	"errors"

	ics23mpt "gno.land/p/onbloc/ibc/union/lightclient/state_lens/ics23_mpt"
	"gno.land/p/onbloc/ibc/union/types"
	"gno.land/p/onbloc/verifier/evm/storage"
	"gno.land/r/onbloc/ibc/union/core"
)

// Union reference:
// https://github.com/unionlabs/union/blob/6215985a5f27e24e9a34aa7259f38b0059c9a5ab/lib/voyager-primitives/src/lib.rs#L129
const ClientType types.ClientType = "state-lens/ics23/mpt"

var (
	ErrInvalidCommitmentValue = errors.New("statelensics23mpt: invalid commitment value")
	ErrStoredValueMismatch    = errors.New("statelensics23mpt: stored value mismatch")
)

type clientEntry struct {
	consensusStates map[ics23mpt.Height]ics23mpt.ConsensusState
	cs              ics23mpt.ClientState
}

var entries = make(map[types.ClientId]*clientEntry)

func mustBeCore(cur realm) {
	if cur.Previous().PkgPath() != "gno.land/r/onbloc/ibc/union/core" {
		panic("statelensics23mpt: core only")
	}
}

func getEntry(clientId types.ClientId) *clientEntry {
	e, ok := entries[clientId]
	if !ok {
		panic("statelensics23mpt: client not found: " + clientId.String())
	}
	return e
}

type Adapter struct{}

// NewAdapter constructs an Adapter inside this realm so cross-realm callers
// (e.g. smoke scripts and loader realms) can build one without tripping the
// Phase 3 cross-realm allocation guard.
func NewAdapter(cur realm) Adapter {
	return Adapter{}
}

func Register(cur realm) {
	core.RegisterClient(cross(cur), ClientType, NewAdapter(cross(cur)))
}

func (Adapter) CreateClient(cur realm, clientId types.ClientId, clientStateBytes, consensusStateBytes []byte) string {
	mustBeCore(cur)

	cs, err := ics23mpt.DecodeClientState(clientStateBytes)
	if err != nil {
		panic("statelensics23mpt: invalid client state: " + err.Error())
	}
	consState, err := ics23mpt.DecodeConsensusState(consensusStateBytes)
	if err != nil {
		panic("statelensics23mpt: invalid consensus state: " + err.Error())
	}

	e := &clientEntry{
		consensusStates: make(map[ics23mpt.Height]ics23mpt.ConsensusState),
		cs:              cs,
	}
	e.consensusStates[cs.L2LatestHeight] = consState
	entries[clientId] = e
	return cs.L2ChainID
}

func (Adapter) UpdateClient(cur realm, clientId types.ClientId, clientMessage []byte) types.ConsensusStateUpdate {
	mustBeCore(cur)

	e := getEntry(clientId)

	header, err := ics23mpt.DecodeHeader(clientMessage)
	if err != nil {
		panic("statelensics23mpt: invalid header: " + err.Error())
	}

	consensusPath := types.ConsensusStatePath(types.ClientId(e.cs.L2ClientID), types.NewHeight(uint64(header.L2Height)))
	consensusHash := keccak256.Sum256(header.L2ConsensusState)
	core.VerifyClientMembership(
		cross(cur),
		types.ClientId(e.cs.L1ClientID),
		types.NewHeight(uint64(header.L1Height)),
		header.L2ConsensusStateProof,
		consensusPath[:],
		consensusHash[:],
	)

	consState, err := ics23mpt.ExtractConsensusState(header.L2ConsensusState, e.cs)
	if err != nil {
		panic(err)
	}

	e.consensusStates[header.L2Height] = consState
	if e.cs.L2LatestHeight < header.L2Height {
		e.cs.L2LatestHeight = header.L2Height
	}

	consStateBytes, err := ics23mpt.EncodeConsensusState(consState)
	if err != nil {
		panic("statelensics23mpt: encode consensus state: " + err.Error())
	}

	clientStateBytes, err := ics23mpt.EncodeClientState(e.cs)
	if err != nil {
		panic("statelensics23mpt: encode client state: " + err.Error())
	}

	return core.NewConsensusStateUpdate(cross(cur), types.NewHeight(uint64(header.L2Height)), consStateBytes, clientStateBytes)
}

func (Adapter) VerifyMembership(clientId types.ClientId, height types.Height, proof, key, value []byte) {
	a := Adapter{}
	status := a.GetStatus(clientId)
	if status != types.StatusActive {
		panic("statelensics23mpt: client is not active")
	}

	e := getEntry(clientId)
	consState, ok := e.consensusStates[ics23mpt.Height(height.Height)]
	if !ok {
		panic("statelensics23mpt: consensus state not found at height " + height.String())
	}
	storageProof, err := storage.DecodeProof(proof)
	if err != nil {
		panic("statelensics23mpt: invalid storage proof: " + err.Error())
	}
	if err := ics23mpt.VerifyCommitmentKey(key, storageProof.Key); err != nil {
		panic(err)
	}
	if len(value) != 32 {
		panic(ErrInvalidCommitmentValue)
	}
	if !bytes.Equal(storageProof.Value, value) {
		panic(ErrStoredValueMismatch)
	}
	if err := storage.VerifyProof(copyBytes(consState.StorageRoot), storage.Proof{
		Key:   storageProof.Key,
		Value: storageProof.Value,
		Proof: storageProof.Proof,
	}); err != nil {
		panic("statelensics23mpt: storage membership verification failed: " + err.Error())
	}
}

func (Adapter) VerifyNonMembership(clientId types.ClientId, height types.Height, proof, key []byte) {
	a := Adapter{}
	status := a.GetStatus(clientId)
	if status != types.StatusActive {
		panic("statelensics23mpt: client is not active")
	}

	e := getEntry(clientId)
	consState, ok := e.consensusStates[ics23mpt.Height(height.Height)]
	if !ok {
		panic("statelensics23mpt: consensus state not found at height " + height.String())
	}
	storageProof, err := storage.DecodeProof(proof)
	if err != nil {
		panic("statelensics23mpt: invalid storage proof: " + err.Error())
	}
	if err := ics23mpt.VerifyCommitmentKey(key, storageProof.Key); err != nil {
		panic(err)
	}
	if err := storage.VerifyAbsence(copyBytes(consState.StorageRoot), storage.Proof{
		Key:   storageProof.Key,
		Proof: storageProof.Proof,
	}); err != nil {
		panic("statelensics23mpt: storage non-membership verification failed: " + err.Error())
	}
}

func (Adapter) GetTimestamp(clientId types.ClientId, height types.Height) types.Timestamp {
	cs, ok := getEntry(clientId).consensusStates[ics23mpt.Height(height.Height)]
	if !ok {
		panic("statelensics23mpt: consensus state not found at height " + height.String())
	}
	return types.Timestamp(cs.Timestamp)
}

func (Adapter) GetLatestHeight(clientId types.ClientId) types.Height {
	return types.NewHeight(uint64(getEntry(clientId).cs.L2LatestHeight))
}

func (Adapter) GetStatus(clientId types.ClientId) types.Status {
	l1ClientId := types.ClientId(getEntry(clientId).cs.L1ClientID)
	status := core.GetClientStatus(l1ClientId)
	if status == types.StatusUnknown {
		return types.StatusFrozen
	}
	return status
}

func copyBytes(b []byte) []byte {
	out := make([]byte, len(b))
	copy(out, b)
	return out
}
