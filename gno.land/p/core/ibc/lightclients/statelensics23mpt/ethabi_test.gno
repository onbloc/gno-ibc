package statelensics23mpt

import (
	"bytes"
	"encoding/hex"
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

	assertBytes(t, "EncodeClientState", EncodeClientState(value), bz)

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

	encoded := EncodeHeader(value)
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

func TestRejectInvalidClientStateOffsets(t *testing.T) {
	bz := mustHex(
		"00000000000000000000000000000000000000000000000000000000000000e0" +
			"0000000000000000000000000000000000000000000000000000000000000001" +
			"0000000000000000000000000000000000000000000000000000000000000001" +
			"00000000000000000000000000000000000000000000000000000000007e36fd" +
			"0000000000000000000000000000000000000000000000000000000000010000" +
			"0000000000000000000000000000000000000000000000000000000000000020" +
			"0000000000000000000000000000000000000000000000000000000000000040" +
			"0000000000000000000000000000000000000000000000000000000000000008" +
			"3131313535313131000000000000000000000000000000000000000000000000",
	)
	if _, err := DecodeClientState(bz); err == nil {
		t.Fatalf("DecodeClientState accepted uint16 overflow")
	}
}

func TestRejectInvalidConsensusStateRoots(t *testing.T) {
	_, err := EncodeConsensusState(ConsensusState{
		Timestamp:   1,
		StateRoot:   []byte{1},
		StorageRoot: bytes.Repeat([]byte{2}, 32),
	})
	if err == nil {
		t.Fatalf("EncodeConsensusState accepted invalid state root")
	}

	_, err = EncodeConsensusState(ConsensusState{
		Timestamp:   1,
		StateRoot:   bytes.Repeat([]byte{1}, 32),
		StorageRoot: []byte{2},
	})
	if err == nil {
		t.Fatalf("EncodeConsensusState accepted invalid storage root")
	}
}

func assertBytes(t *testing.T, name string, got, want []byte) {
	t.Helper()
	if !bytes.Equal(got, want) {
		t.Fatalf("%s: got %x want %x", name, got, want)
	}
}

func mustHex(s string) []byte {
	bz, err := hex.DecodeString(s)
	if err != nil {
		panic("mustHex: " + err.Error())
	}
	return bz
}

func word32(v uint64) string {
	out := make([]byte, 32)
	out[24] = byte(v >> 56)
	out[25] = byte(v >> 48)
	out[26] = byte(v >> 40)
	out[27] = byte(v >> 32)
	out[28] = byte(v >> 24)
	out[29] = byte(v >> 16)
	out[30] = byte(v >> 8)
	out[31] = byte(v)
	return hex.EncodeToString(out)
}
