package cometbls

import (
	"time"

	cometblsp "gno.land/p/core/ibc/lightclients/cometbls"
	"gno.land/r/core/ibc/core"
)

const ClientType core.ClientType = "07-cometbls"

type clientEntry struct {
	client          *cometblsp.CometBLSClient
	consensusStates map[cometblsp.Height]cometblsp.ConsensusState
	cs              cometblsp.ClientState
}

var entries = make(map[core.ClientId]*clientEntry)

func init() {
	core.RegisterClient(ClientType, Adapter{})
}

func nowNanos() uint64 { return uint64(time.Now().UnixNano()) }

func getEntry(clientId core.ClientId) *clientEntry {
	e, ok := entries[clientId]
	if !ok {
		panic("cometbls: client not found: " + clientId.String())
	}
	return e
}

type Adapter struct{}

func (Adapter) CreateClient(clientId core.ClientId, clientStateBytes, consensusStateBytes []byte) string {
	cs, err := cometblsp.DecodeClientState(clientStateBytes)
	if err != nil {
		panic("cometbls: invalid client state: " + err.Error())
	}
	consState, err := cometblsp.DecodeConsensusState(consensusStateBytes)
	if err != nil {
		panic("cometbls: invalid consensus state: " + err.Error())
	}

	e := &clientEntry{
		consensusStates: make(map[cometblsp.Height]cometblsp.ConsensusState),
		cs:              cs,
	}
	e.client = cometblsp.New(
		func(h cometblsp.Height) (cometblsp.ConsensusState, bool) {
			cs, ok := e.consensusStates[h]
			return cs, ok
		},
		func(h cometblsp.Height, cs cometblsp.ConsensusState) {
			e.consensusStates[h] = cs
		},
	)
	if err := e.client.Initialize(cs, consState); err != nil {
		panic("cometbls: initialize failed: " + err.Error())
	}
	entries[clientId] = e
	return cs.ChainID
}

func (Adapter) UpdateClient(clientId core.ClientId, clientMessage []byte) core.ConsensusStateUpdate {
	e := getEntry(clientId)

	header, err := cometblsp.DecodeHeader(clientMessage)
	if err != nil {
		panic("cometbls: invalid header: " + err.Error())
	}

	msg := cometblsp.NewHeaderMessage(header)
	if err := e.client.VerifyClientMessage(msg, nowNanos()); err != nil {
		panic("cometbls: " + err.Error())
	}

	heights := e.client.UpdateState(msg)
	if len(heights) == 0 {
		panic("cometbls: update state returned no heights")
	}
	newHeight := heights[0]

	consState, ok := e.consensusStates[newHeight]
	if !ok {
		panic("cometbls: consensus state not found after update")
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

func (Adapter) Misbehaviour(clientId core.ClientId, clientMessage []byte) []byte {
	e := getEntry(clientId)

	m, err := cometblsp.DecodeMisbehaviour(clientMessage)
	if err != nil {
		panic("cometbls: invalid misbehaviour: " + err.Error())
	}

	msg := cometblsp.NewMisbehaviourMessage(m)
	if err := e.client.VerifyClientMessage(msg, nowNanos()); err != nil {
		panic("cometbls: " + err.Error())
	}
	if !e.client.CheckForMisbehaviour(msg) {
		panic("cometbls: not misbehaviour")
	}

	e.client.UpdateStateOnMisbehaviour()
	e.cs.FrozenHeight = cometblsp.FrozenHeight

	return cometblsp.EncodeClientState(e.cs)
}

func (Adapter) VerifyMembership(_ core.ClientId, _ core.Height, _, _, _ []byte) {
	panic("cometbls: VerifyMembership not yet implemented")
}

func (Adapter) VerifyNonMembership(_ core.ClientId, _ core.Height, _, _ []byte) {
	panic("cometbls: VerifyNonMembership not yet implemented")
}

func (Adapter) GetTimestamp(clientId core.ClientId, height core.Height) core.Timestamp {
	e := getEntry(clientId)
	ts, ok := e.client.TimestampAtHeight(cometblsp.Height(height))
	if !ok {
		panic("cometbls: consensus state not found at height " + height.String())
	}
	return core.Timestamp(ts)
}

func (Adapter) GetLatestHeight(clientId core.ClientId) core.Height {
	return core.Height(getEntry(clientId).client.LatestHeight())
}

func (Adapter) GetStatus(clientId core.ClientId) core.Status {
	e := getEntry(clientId)
	switch e.client.Status(nowNanos()) {
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
