package ics23mpt

import (
	"bytes"
	"testing"
)

func TestClientStateEthABIVector(t *testing.T) {
	// Reference vector copied from Union's state-lens-ics23-mpt light client
	// type tests. Keep this hardcoded: it pins the unprefixed Solidity
	// abi_encode_params wire format expected by relayers and Solidity clients.
	//
	// Source:
	// https://github.com/unionlabs/union/blob/main/lib/state-lens-ics23-mpt-light-client-types/src/client_state.rs
	//
	// Reference command noted upstream:
	// voyager rpc -r voy.run client-state 17000 3
	l2ChainIDOffset := "00000000000000000000000000000000000000000000000000000000000000e0"
	l1ClientID := "0000000000000000000000000000000000000000000000000000000000000001"
	l2ClientID := "0000000000000000000000000000000000000000000000000000000000000001"
	l2LatestHeight := "00000000000000000000000000000000000000000000000000000000007e36fd"
	timestampOffset := "0000000000000000000000000000000000000000000000000000000000000078"
	stateRootOffset := "0000000000000000000000000000000000000000000000000000000000000020"
	storageRootOffset := "0000000000000000000000000000000000000000000000000000000000000040"
	l2ChainIDLength := "0000000000000000000000000000000000000000000000000000000000000008"
	l2ChainIDData := "3131313535313131000000000000000000000000000000000000000000000000" // "11155111"

	bz := mustHex(
		l2ChainIDOffset +
			l1ClientID +
			l2ClientID +
			l2LatestHeight +
			timestampOffset +
			stateRootOffset +
			storageRootOffset +
			l2ChainIDLength +
			l2ChainIDData,
	)

	value := ClientState{
		L2ChainID:         "11155111",
		L1ClientID:        1,
		L2ClientID:        1,
		L2LatestHeight:    8271613,
		TimestampOffset:   120,
		StateRootOffset:   32,
		StorageRootOffset: 64,
	}

	encoded, err := EncodeClientState(value)
	if err != nil {
		t.Fatalf("EncodeClientState: %v", err)
	}
	assertBytes(t, "EncodeClientState", encoded, bz)

	got, err := DecodeClientState(bz)
	if err != nil {
		t.Fatalf("DecodeClientState: %v", err)
	}
	if got != value {
		t.Fatalf("DecodeClientState: got %#v want %#v", got, value)
	}
}

func TestConsensusStateEthABIVector(t *testing.T) {
	// Reference vector copied from Union's state-lens-ics23-mpt consensus
	// state type tests.
	//
	// Source:
	// https://github.com/unionlabs/union/blob/main/lib/state-lens-ics23-mpt-light-client-types/src/consensus_state.rs
	//
	// Reference command noted upstream:
	// voyager rpc -r voy.run rpc consensus-state 11155111 3 3697397
	timestamp := "000000000000000000000000000000000000000000000000321386383136d3f2"
	stateRoot := "00000000000000000000000000000000000000000000000000000000003e7d40"
	storageRoot := "56013ecdec1cff8ae46d82d3a021ebe40b327a0a6b915383af7756c3fc53797f"

	bz := mustHex(
		timestamp +
			stateRoot +
			storageRoot,
	)

	value := ConsensusState{
		Timestamp:   3608375302355866610,
		StateRoot:   mustHex(stateRoot),
		StorageRoot: mustHex(storageRoot),
	}

	encoded, err := EncodeConsensusState(value)
	if err != nil {
		t.Fatalf("EncodeConsensusState: %v", err)
	}
	assertBytes(t, "EncodeConsensusState", encoded, bz)

	got, err := DecodeConsensusState(bz)
	if err != nil {
		t.Fatalf("DecodeConsensusState: %v", err)
	}
	if got.Timestamp != value.Timestamp ||
		!bytes.Equal(got.StateRoot, value.StateRoot) ||
		!bytes.Equal(got.StorageRoot, value.StorageRoot) {
		t.Fatalf("DecodeConsensusState: got %#v want %#v", got, value)
	}
}

func TestHeaderEthABI(t *testing.T) {
	// Header has no fixed upstream hex fixture in Union's type tests at the
	// time this test was added. The shape is pinned against the reference type:
	// https://github.com/unionlabs/union/blob/main/lib/state-lens-light-client-types/src/header.rs
	value := Header{
		L1Height:              11,
		L2Height:              22,
		L2ConsensusStateProof: mustHex("aabbcc"),
		L2ConsensusState:      mustHex("01020304"),
	}

	l1Height := word32(11)
	l2Height := word32(22)
	l2ConsensusStateProofOffset := word32(128)
	l2ConsensusStateOffset := word32(192)
	l2ConsensusStateProofLength := word32(3)
	l2ConsensusStateProofData := "aabbcc0000000000000000000000000000000000000000000000000000000000"
	l2ConsensusStateLength := word32(4)
	l2ConsensusStateData := "0102030400000000000000000000000000000000000000000000000000000000"

	want := mustHex(
		l1Height +
			l2Height +
			l2ConsensusStateProofOffset +
			l2ConsensusStateOffset +
			l2ConsensusStateProofLength +
			l2ConsensusStateProofData +
			l2ConsensusStateLength +
			l2ConsensusStateData,
	)

	encoded, err := EncodeHeader(value)
	if err != nil {
		t.Fatalf("EncodeHeader: %v", err)
	}
	assertBytes(t, "EncodeHeader", encoded, want)

	got, err := DecodeHeader(encoded)
	if err != nil {
		t.Fatalf("DecodeHeader: %v", err)
	}
	if got.L1Height != value.L1Height ||
		got.L2Height != value.L2Height ||
		!bytes.Equal(got.L2ConsensusStateProof, value.L2ConsensusStateProof) ||
		!bytes.Equal(got.L2ConsensusState, value.L2ConsensusState) {
		t.Fatalf("DecodeHeader: got %#v want %#v", got, value)
	}
}
