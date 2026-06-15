package cometbls

import (
	"time"

	"gno.land/p/aib/ibc/types"
	cometblsp "gno.land/p/onbloc/ibc/lightclient/cometbls"
	"gno.land/r/onbloc/unionibc/v1/core"
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

func mustBeCore(cur realm) {
	if cur.Previous().PkgPath() != "gno.land/r/onbloc/unionibc/v1/core" {
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

func NewAdapter(cur realm) Adapter {
	return Adapter{}
}

func Register(cur realm) {
	core.RegisterClient(cross(cur), ClientType, NewAdapter(cross(cur)))
}

func (Adapter) CreateClient(cur realm, clientId core.ClientId, clientStateBytes, consensusStateBytes []byte) string {
	mustBeCore(cur)

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

func (Adapter) UpdateClient(cur realm, clientId core.ClientId, clientMessage []byte) core.ConsensusStateUpdate {
	mustBeCore(cur)

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
	consState := applyHeaderHeight(e, newHeight, cometblsp.ConsensusStateFromHeader(header.SignedHeader))

	consStateBytes, err := cometblsp.EncodeConsensusState(consState)
	if err != nil {
		panic("cometbls: encode consensus state: " + err.Error())
	}
	clientStateBytes := cometblsp.EncodeClientState(e.cs)

	return core.NewConsensusStateUpdate(cross(cur), core.Height(newHeight), consStateBytes, clientStateBytes)
}

func applyHeaderHeight(e *clientEntry, newHeight cometblsp.Height, consState cometblsp.ConsensusState) cometblsp.ConsensusState {
	stored, ok := e.consensusStates[newHeight]
	if !ok {
		stored = consState
		e.consensusStates[newHeight] = stored
	}
	if newHeight > e.cs.LatestHeight {
		e.cs.LatestHeight = newHeight
	}
	return stored
}

func (Adapter) Misbehaviour(cur realm, clientId core.ClientId, clientMessage []byte) []byte {
	mustBeCore(cur)

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

// consensusStateAt returns the consensus state at the given height.
// It panics if no consensus state exists at that height.
//
// Proof verification must reject unknown heights rather than relying on
// verification against a zero-value consensus state.
func consensusStateAt(e *clientEntry, height core.Height) cometblsp.ConsensusState {
	cs, ok := e.consensusStates[cometblsp.Height(height)]
	if !ok {
		panic("cometbls: consensus state not found at height " + height.String())
	}
	return cs
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
	cs := consensusStateAt(e, height)
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
	cs := consensusStateAt(e, height)
	if err := cometblsp.VerifyNonMembership(cs, proofs, path); err != nil {
		panic("cometbls: non-membership verification failed: " + err.Error())
	}
}

func (Adapter) GetTimestamp(clientId core.ClientId, height core.Height) core.Timestamp {
	e := getEntry(clientId)
	cs := consensusStateAt(e, height)
	return core.Timestamp(cs.Timestamp)
}

func (Adapter) GetLatestHeight(clientId core.ClientId) core.Height {
	return core.Height(getEntry(clientId).cs.LatestHeight)
}

func (Adapter) ForceUpdateClient(cur realm, clientId core.ClientId, clientStateBytes, consensusStateBytes []byte) core.ConsensusStateUpdate {
	mustBeCore(cur)
	height, consStateBytes, csBytes := applyForceUpdate(clientId, clientStateBytes, consensusStateBytes)
	return core.NewConsensusStateUpdate(cross(cur), height, consStateBytes, csBytes)
}

// applyForceUpdate applies a force update to the client state and consensus state
// without performing any caller authorization checks.
//
// This function exists so adapter-level tests can exercise the force-update
// logic without requiring a core caller.
//
// SECURITY WARNING:
//
// applyForceUpdate performs no authorization on its own.
//
// The only authorization gates for force updates are:
//   - mustBeCore() in Adapter.ForceUpdateClient
//   - the deployer check in core.ForceUpdateClient
//
// Any additional caller added within this package would bypass both
// authorization checks. Do not call applyForceUpdate from any new entrypoint.
func applyForceUpdate(clientId core.ClientId, clientStateBytes, consensusStateBytes []byte) (core.Height, []byte, []byte) {
	cs, err := cometblsp.DecodeClientState(clientStateBytes)
	if err != nil {
		panic("cometbls: invalid client state: " + err.Error())
	}
	consState, err := cometblsp.DecodeConsensusState(consensusStateBytes)
	if err != nil {
		panic("cometbls: invalid consensus state: " + err.Error())
	}
	if err := cometblsp.ValidateInitialize(cs, consState); err != nil {
		panic("cometbls: invalid force-update state: " + err.Error())
	}

	e := getEntry(clientId)

	// Force update is a recovery operation: only permit clients that are no
	// longer usable. New status values should be denied until explicitly vetted.
	if status := adapterStatus(e); status != cometblsp.StatusExpired && status != cometblsp.StatusFrozen {
		panic("cometbls: force-update only allowed on expired or frozen client")
	}

	// Preserve counterparty identity fields.
	//
	// Force updates are recovery operations, not retargeting mechanisms.
	// Without these checks, a privileged caller could silently redirect the
	// client to a different chain or contract address.
	if cs.ChainID != e.cs.ChainID {
		panic("cometbls: force-update cannot change ChainID")
	}
	if cs.TrustingPeriod != e.cs.TrustingPeriod {
		panic("cometbls: force-update cannot change TrustingPeriod")
	}
	if cs.MaxClockDrift != e.cs.MaxClockDrift {
		panic("cometbls: force-update cannot change MaxClockDrift")
	}
	if cs.ContractAddress != e.cs.ContractAddress {
		panic("cometbls: force-update cannot change ContractAddress")
	}

	// Strict-equal heights are rejected too — replacing an existing consensus
	// state at the live height with different bytes would silently invalidate
	// any membership proof previously verified at that height.
	if cs.LatestHeight <= e.cs.LatestHeight {
		panic("cometbls: force-update height must strictly advance")
	}

	// Clear any frozen status unconditionally.
	//
	// Force update is treated as an explicit recovery operation.
	cs.FrozenHeight = 0
	e.cs = cs

	// Discard all prior consensus states.
	//
	// Proofs against older heights will no longer verify after a force update.
	// Any in-flight packets referencing those heights must be resolved before
	// invoking this operation.
	e.consensusStates = map[cometblsp.Height]cometblsp.ConsensusState{cs.LatestHeight: consState}

	encConsState, err := cometblsp.EncodeConsensusState(consState)
	if err != nil {
		panic("cometbls: encode consensus state: " + err.Error())
	}

	return core.Height(cs.LatestHeight), encConsState, cometblsp.EncodeClientState(e.cs)
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
