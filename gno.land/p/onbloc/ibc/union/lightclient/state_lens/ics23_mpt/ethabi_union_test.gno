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
	bz := mustHex(
		"00000000000000000000000000000000000000000000000000000000000000e0" + // l2_chain_id offset
			"0000000000000000000000000000000000000000000000000000000000000001" + // l1_client_id
			"0000000000000000000000000000000000000000000000000000000000000001" + // l2_client_id
			"00000000000000000000000000000000000000000000000000000000007e36fd" + // l2_latest_height
			"0000000000000000000000000000000000000000000000000000000000000078" + // timestamp_offset
			"0000000000000000000000000000000000000000000000000000000000000020" + // state_root_offset
			"0000000000000000000000000000000000000000000000000000000000000040" + // storage_root_offset
			"0000000000000000000000000000000000000000000000000000000000000008" + // l2_chain_id length
			"3131313535313131000000000000000000000000000000000000000000000000", // "11155111"
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
	bz := mustHex(
		"000000000000000000000000000000000000000000000000321386383136d3f2" + // timestamp
			"00000000000000000000000000000000000000000000000000000000003e7d40" + // state_root
			"56013ecdec1cff8ae46d82d3a021ebe40b327a0a6b915383af7756c3fc53797f", // storage_root
	)

	value := ConsensusState{
		Timestamp:   3608375302355866610,
		StateRoot:   mustHex("00000000000000000000000000000000000000000000000000000000003e7d40"),
		StorageRoot: mustHex("56013ecdec1cff8ae46d82d3a021ebe40b327a0a6b915383af7756c3fc53797f"),
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
	want := mustHex(
		word32(11) +
			word32(22) +
			word32(128) +
			word32(192) +
			word32(3) +
			"aabbcc0000000000000000000000000000000000000000000000000000000000" +
			word32(4) +
			"0102030400000000000000000000000000000000000000000000000000000000",
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
